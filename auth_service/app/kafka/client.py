from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from app.config import Settings
from app.domain.events import kafka_headers, kafka_key
from app.observability.apm import apm_background_transaction, apm_span, capture_apm_exception
from app.utils.redaction import redact

logger = logging.getLogger("app.kafka")


class KafkaClient:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.producer = None
        self.consumer = None

    async def connect(self) -> None:
        try:
            from aiokafka import AIOKafkaConsumer, AIOKafkaProducer
        except ImportError as exc:
            raise RuntimeError("aiokafka is required for Kafka integration") from exc
        if self.settings.kafka_auto_create_topics:
            await self._create_topics_best_effort()
        async with apm_span("Kafka producer.start", "messaging.kafka", labels={"broker": self.settings.kafka_bootstrap_servers}):
            self.producer = AIOKafkaProducer(bootstrap_servers=self.settings.kafka_bootstrap_servers)
            await self.producer.start()
        self.consumer = AIOKafkaConsumer(
            *self.settings.kafka_consume_topics,
            bootstrap_servers=self.settings.kafka_bootstrap_servers,
            group_id=self.settings.kafka_consumer_group,
            enable_auto_commit=False,
            auto_offset_reset="earliest",
        )
        async with apm_span("Kafka consumer.start", "messaging.kafka", labels={"group": self.settings.kafka_consumer_group}):
            await self.consumer.start()

    async def _create_topics_best_effort(self) -> None:
        try:
            from aiokafka.admin import AIOKafkaAdminClient, NewTopic
            topics = sorted(set(self.settings.kafka_consume_topics + [self.settings.kafka_events_topic, self.settings.kafka_dead_letter_topic]))
            admin = AIOKafkaAdminClient(
                bootstrap_servers=self.settings.kafka_bootstrap_servers,
                client_id=f"{self.settings.service_name}-topic-admin",
            )
            await admin.start()
            try:
                async with apm_span("Kafka admin.create_topics", "messaging.kafka", labels={"topics": ",".join(topics[:10])}):
                    await admin.create_topics(
                        [NewTopic(name=topic, num_partitions=3, replication_factor=1) for topic in topics],
                        validate_only=False,
                    )
            except Exception as exc:
                logger.warning(
                    "Kafka topic creation best-effort failed",
                    extra={
                        "event": "kafka.topic_create.failed",
                        "error_code": "KAFKA_TOPIC_CREATE_FAILED",
                        "extra": {"error": str(exc)},
                    },
                )
            finally:
                await admin.close()
        except Exception as exc:
            logger.warning(
                "Kafka topic creation best-effort failed",
                extra={
                    "event": "kafka.topic_create.failed",
                    "error_code": "KAFKA_TOPIC_CREATE_FAILED",
                    "extra": {"error": str(exc)},
                },
            )

    async def publish(self, topic: str, envelope: dict[str, Any]) -> None:
        if self.producer is None:
            raise RuntimeError("Kafka producer is not initialized")
        async with apm_span("Kafka publish", "messaging.kafka", labels={"topic": topic, "event_type": envelope.get("event_type", "unknown")}):
            await self.producer.send_and_wait(
                topic,
                json.dumps(redact(envelope), default=str).encode("utf-8"),
                key=kafka_key(envelope).encode("utf-8"),
                headers=kafka_headers(envelope),
            )

    async def health(self) -> None:
        if self.producer is None:
            raise RuntimeError("Kafka producer is not initialized")
        async with apm_span("Kafka metadata", "messaging.kafka", labels={"broker": self.settings.kafka_bootstrap_servers}):
            await self.producer.client.force_metadata_update()

    async def close(self) -> None:
        if self.consumer is not None:
            await self.consumer.stop()
        if self.producer is not None:
            await self.producer.stop()


class OutboxPublisher:
    def __init__(self, repository, kafka: KafkaClient, poll_seconds: float = 1.0):
        self.repository = repository
        self.kafka = kafka
        self.poll_seconds = poll_seconds
        self._stopped = asyncio.Event()
        self._task: asyncio.Task | None = None

    def start(self) -> None:
        self._task = asyncio.create_task(self.run(), name="auth-outbox-publisher")

    async def stop(self) -> None:
        self._stopped.set()
        if self._task is not None:
            await asyncio.wait([self._task], timeout=5)

    async def run(self) -> None:
        while not self._stopped.is_set():
            try:
                async with apm_background_transaction("auth.outbox.poll", "messaging"):
                    rows = await self.repository.fetch_pending_outbox(limit=50)
                if not rows:
                    await asyncio.sleep(self.poll_seconds)
                    continue
                for row in rows:
                    payload = row["payload"]
                    if isinstance(payload, str):
                        payload = json.loads(payload)
                    try:
                        async with apm_background_transaction("auth.outbox.publish", "messaging"):
                            await self.kafka.publish(row["topic"], payload)
                            await self.repository.mark_outbox_sent(str(row["id"]))
                    except Exception as exc:
                        await self.repository.mark_outbox_failed(str(row["id"]), str(exc))
                        capture_apm_exception(exc)
                        logger.warning(
                            "Kafka outbox publish failed",
                            extra={
                                "event": "kafka.outbox.publish_failed",
                                "error_code": "KAFKA_PUBLISH_FAILED",
                                "extra": {"outbox_id": str(row["id"])},
                            },
                        )
            except Exception:
                capture_apm_exception()
                logger.exception("Outbox publisher loop failed", extra={"event": "kafka.outbox.loop_failed", "error_code": "OUTBOX_LOOP_FAILED"})
                await asyncio.sleep(self.poll_seconds)


class InboxConsumer:
    def __init__(self, repository, kafka: KafkaClient):
        self.repository = repository
        self.kafka = kafka
        self._stopped = asyncio.Event()
        self._task: asyncio.Task | None = None

    def start(self) -> None:
        self._task = asyncio.create_task(self.run(), name="auth-inbox-consumer")

    async def stop(self) -> None:
        self._stopped.set()
        if self._task is not None:
            await asyncio.wait([self._task], timeout=5)

    async def run(self) -> None:
        consumer = self.kafka.consumer
        if consumer is None:
            return
        while not self._stopped.is_set():
            try:
                async with apm_background_transaction("auth.inbox.consume", "messaging"):
                    msg = await consumer.getone()
                    payload = json.loads(msg.value.decode("utf-8"))
                    event_id = payload.get("event_id")
                    if not event_id:
                        await consumer.commit()
                        continue
                    inserted = await self.repository.insert_inbox_event(
                        event_id=event_id,
                        tenant=payload.get("tenant"),
                        topic=msg.topic,
                        partition=msg.partition,
                        offset=msg.offset,
                        event_type=payload.get("event_type", "unknown"),
                        source_service=payload.get("service"),
                        payload=payload,
                    )
                    try:
                        # Apply admin registration approval/rejection even if the inbox row
                        # already exists. This makes duplicate delivery and older RECEIVED /
                        # PROCESSED rows safe and idempotent, and it prevents approved admins
                        # from staying pending in auth.auth_users.
                        await self.repository.apply_admin_decision_event(payload)
                        if inserted:
                            await self.repository.mark_inbox_processed(event_id, status="PROCESSED")
                    except Exception as exc:
                        if inserted:
                            await self.repository.mark_inbox_processed(event_id, status="FAILED", error=str(exc)[:2000])
                        raise
                    await consumer.commit()
            except Exception as exc:
                capture_apm_exception(exc)
                logger.warning(
                    "Kafka inbox consume failed",
                    extra={
                        "event": "kafka.inbox.consume_failed",
                        "error_code": "KAFKA_CONSUME_FAILED",
                        "extra": {"error": str(exc)},
                    },
                )
                await asyncio.sleep(1)


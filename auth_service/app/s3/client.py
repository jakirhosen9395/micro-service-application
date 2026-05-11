from __future__ import annotations

import asyncio
import json
from typing import Any

from app.config import Settings
from app.observability.apm import apm_span
from app.utils.redaction import redact


class S3Client:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.client = None

    async def connect(self) -> None:
        try:
            import boto3
            from botocore.config import Config
        except ImportError as exc:
            raise RuntimeError("boto3 is required for S3 integration") from exc
        async with apm_span("S3 client.create", "storage.s3", labels={"bucket": self.settings.s3_bucket}):
            self.client = boto3.client(
                "s3",
                endpoint_url=self.settings.s3_endpoint,
                aws_access_key_id=self.settings.s3_access_key,
                aws_secret_access_key=self.settings.s3_secret_key,
                region_name=self.settings.s3_region,
                config=Config(s3={"addressing_style": "path" if self.settings.s3_force_path_style else "virtual"}),
            )
        # Do not fail application startup solely because bucket-level HeadBucket is
        # forbidden by a MinIO policy. /health performs the real dependency check.

    async def health(self) -> None:
        if self.client is None:
            raise RuntimeError("S3 client is not initialized")
        async with apm_span("S3 health", "storage.s3", labels={"bucket": self.settings.s3_bucket}):
            try:
                await asyncio.to_thread(self.client.head_bucket, Bucket=self.settings.s3_bucket)
                return
            except Exception as exc:
                message = str(exc)
                if "404" in message or "NoSuchBucket" in message:
                    await asyncio.to_thread(self.client.create_bucket, Bucket=self.settings.s3_bucket)
                    return
                if "403" not in message and "Forbidden" not in message:
                    raise
            # Some MinIO users can PutObject but cannot HeadBucket. Probe the
            # exact write path used by this service instead of requiring bucket
            # metadata permissions.
            probe_key = f"{self.settings.s3_audit_prefix}/health/.auth_service_probe.json"
            await asyncio.to_thread(
                self.client.put_object,
                Bucket=self.settings.s3_bucket,
                Key=probe_key,
                Body=b'{"status":"ok"}\n',
                ContentType="application/json; charset=utf-8",
            )

    async def put_json(self, key: str, payload: dict[str, Any]) -> None:
        if self.client is None:
            raise RuntimeError("S3 client is not initialized")
        body = json.dumps(redact(payload), ensure_ascii=False, indent=2, default=str).encode("utf-8")
        async with apm_span("S3 put_object", "storage.s3", labels={"bucket": self.settings.s3_bucket}):
            await asyncio.to_thread(
                self.client.put_object,
                Bucket=self.settings.s3_bucket,
                Key=key,
                Body=body,
                ContentType="application/json; charset=utf-8",
            )

    async def close(self) -> None:
        self.client = None

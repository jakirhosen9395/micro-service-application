from __future__ import annotations

from app.config import Settings
from app.observability.apm import apm_span


class ElasticsearchClient:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.client = None

    async def connect(self) -> None:
        try:
            from elasticsearch import AsyncElasticsearch
        except ImportError as exc:
            raise RuntimeError("elasticsearch is required for Elasticsearch integration") from exc
        async with apm_span("Elasticsearch client.create", "db.elasticsearch", labels={"url": self.settings.elasticsearch_url}):
            self.client = AsyncElasticsearch(
                self.settings.elasticsearch_url,
                basic_auth=(self.settings.elasticsearch_username, self.settings.elasticsearch_password),
                request_timeout=5,
            )
        await self.health()

    async def health(self) -> None:
        if self.client is None:
            raise RuntimeError("Elasticsearch client is not initialized")
        async with apm_span("Elasticsearch info", "db.elasticsearch", labels={"url": self.settings.elasticsearch_url}):
            await self.client.info()

    async def close(self) -> None:
        if self.client is not None:
            await self.client.close()

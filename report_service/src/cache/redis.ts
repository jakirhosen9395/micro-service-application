import { Redis as IORedis } from "ioredis";
import type { AppConfig } from "../config/config.js";
import { withApmSpan } from "../observability/apm.js";

export class RedisCache {
  public readonly client: IORedis;
  private readonly namespace: string;

  public constructor(private readonly config: AppConfig) {
    this.namespace = `${config.service.environment}:${config.service.name}:`;
    this.client = new IORedis({
      host: config.redis.host,
      port: config.redis.port,
      password: config.redis.password,
      db: config.redis.db,
      lazyConnect: true,
      maxRetriesPerRequest: null,
      enableReadyCheck: true
    });
  }

  public key(parts: Array<string | number>): string {
    return `${this.namespace}${parts.map((part) => String(part)).join(":")}`;
  }

  public async connect(): Promise<void> {
    await withApmSpan("redis.connect", "cache", "redis", "connect", () => this.client.connect());
    await this.health();
  }

  public async health(): Promise<void> {
    const pong = await withApmSpan("redis.ping", "cache", "redis", "ping", () => this.client.ping());
    if (pong !== "PONG") throw new Error("Redis ping failed");
  }

  public async getJson<T>(key: string): Promise<T | undefined> {
    const raw = await withApmSpan("redis.get", "cache", "redis", "get", () => this.client.get(key));
    if (!raw) return undefined;
    return JSON.parse(raw) as T;
  }

  public async setJson(key: string, value: unknown, ttlSeconds = this.config.redis.cacheTtlSeconds): Promise<void> {
    await withApmSpan("redis.set", "cache", "redis", "set", () => this.client.set(key, JSON.stringify(value), "EX", ttlSeconds));
  }

  public async delete(key: string): Promise<void> {
    await withApmSpan("redis.del", "cache", "redis", "del", () => this.client.del(key));
  }

  public async deletePrefix(prefix: string): Promise<void> {
    let cursor = "0";
    do {
      const [nextCursor, keys] = await withApmSpan("redis.scan", "cache", "redis", "scan", () => this.client.scan(cursor, "MATCH", `${prefix}*`, "COUNT", 100));
      cursor = nextCursor;
      if (keys.length > 0) await withApmSpan("redis.del_prefix_batch", "cache", "redis", "del", () => this.client.del(...keys));
    } while (cursor !== "0");
  }

  public async close(): Promise<void> {
    await this.client.quit();
  }
}

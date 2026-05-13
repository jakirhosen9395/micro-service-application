import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import pg from "pg";
import type { AppConfig } from "../config/config.js";
import type { AppLogger } from "../logging/logger.js";
import { captureApmError, withApmSpan } from "../observability/apm.js";

const { Pool } = pg;
export type QueryResultRow = pg.QueryResultRow;
export type PoolClient = pg.PoolClient;

export class PostgresDatabase {
  public readonly pool: pg.Pool;

  public constructor(private readonly config: AppConfig, private readonly logger: AppLogger) {
    this.pool = new Pool({
      host: config.postgres.host,
      port: config.postgres.port,
      user: config.postgres.user,
      password: config.postgres.password,
      database: config.postgres.database,
      max: config.postgres.poolSize,
      application_name: config.service.name
    });
  }

  public async connect(): Promise<void> {
    const client = await withApmSpan("postgres.pool.connect", "db", "postgresql", "connect", () => this.pool.connect());
    try {
      await client.query("select 1");
    } finally {
      client.release();
    }
  }

  public async query<T extends QueryResultRow = QueryResultRow>(text: string, values: unknown[] = []): Promise<pg.QueryResult<T>> {
    return withApmSpan("postgres.query", "db", "postgresql", "query", () => this.pool.query<T>(text, values));
  }

  public async transaction<T>(handler: (client: PoolClient) => Promise<T>): Promise<T> {
    return withApmSpan("postgres.transaction", "db", "postgresql", "transaction", async () => {
      const client = await withApmSpan("postgres.pool.connect", "db", "postgresql", "connect", () => this.pool.connect());
      try {
        await client.query("begin");
        const result = await handler(client);
        await client.query("commit");
        return result;
      } catch (error) {
        try {
          await client.query("rollback");
        } catch (rollbackError) {
          captureApmError(rollbackError, { dependency: "postgresql", operation: "rollback" });
          this.logger.error("database transaction rollback failed", {
            logger: "app.database",
            event: "postgres.transaction.rollback_failed",
            dependency: "postgresql",
            exception_class: rollbackError instanceof Error ? rollbackError.name : "Error",
            exception_message: rollbackError instanceof Error ? rollbackError.message : String(rollbackError),
            stack_trace: rollbackError instanceof Error ? rollbackError.stack ?? null : null
          });
        }
        throw error;
      } finally {
        client.release();
      }
    });
  }

  public async runMigrations(): Promise<void> {
    if (this.config.postgres.migrationMode !== "auto") return;
    this.logger.info("database migrations starting", { logger: "app.migration", event: "migration.started", dependency: "postgres" });
    const migrationsDir = join(process.cwd(), "migrations");
    const files = (await readdir(migrationsDir)).filter((name) => name.endsWith(".sql")).sort();
    for (const file of files) {
      const sql = await readFile(join(migrationsDir, file), "utf8");
      await this.query(sql);
      this.logger.info("database migration applied", {
        logger: "app.migration",
        event: "migration.applied",
        dependency: "postgres",
        extra: { file }
      });
    }
    this.logger.info("database migrations completed", { logger: "app.migration", event: "migration.completed", dependency: "postgres" });
  }

  public async health(): Promise<void> {
    await withApmSpan("postgres.health", "db", "postgresql", "health", () => this.query("select 1"));
  }

  public async close(): Promise<void> {
    await this.pool.end();
  }
}

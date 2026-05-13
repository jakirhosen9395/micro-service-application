import { MongoClient, type Collection, type Db } from "mongodb";
import type { AppConfig } from "../config/config.js";
import type { AppLogger, CanonicalLogDocument } from "./logger.js";

export class MongoLogWriter {
  private client?: MongoClient;
  private db?: Db;
  private collection?: Collection<CanonicalLogDocument>;

  public constructor(private readonly config: AppConfig, private readonly logger?: AppLogger) {}

  public async connect(): Promise<void> {
    const username = encodeURIComponent(this.config.mongo.username);
    const password = encodeURIComponent(this.config.mongo.password);
    const authSource = encodeURIComponent(this.config.mongo.authSource);
    const uri = `mongodb://${username}:${password}@${this.config.mongo.host}:${this.config.mongo.port}/${this.config.mongo.database}?authSource=${authSource}`;
    this.client = new MongoClient(uri, {
      serverSelectionTimeoutMS: 5000,
      appName: this.config.service.name
    });
    await this.client.connect();
    this.db = this.client.db(this.config.mongo.database);
    this.collection = this.db.collection<CanonicalLogDocument>(this.config.mongo.logCollection);
    await this.createIndexes();
  }

  public async createIndexes(): Promise<void> {
    if (!this.collection) throw new Error("MongoDB log collection is not initialized");
    await this.collection.createIndex({ timestamp: -1 });
    await this.collection.createIndex({ level: 1, timestamp: -1 });
    await this.collection.createIndex({ event: 1, timestamp: -1 });
    await this.collection.createIndex({ request_id: 1 });
    await this.collection.createIndex({ trace_id: 1 });
    await this.collection.createIndex({ elastic_trace_id: 1 });
    await this.collection.createIndex({ user_id: 1, timestamp: -1 });
    await this.collection.createIndex({ path: 1, status_code: 1, timestamp: -1 });
    await this.collection.createIndex({ error_code: 1, timestamp: -1 });
    if (this.config.service.environment !== "production") {
      await this.collection.createIndex({ timestamp: 1 }, { expireAfterSeconds: 1_209_600, name: "ttl_non_production_logs" });
    }
  }

  public async insert(document: CanonicalLogDocument): Promise<void> {
    if (!this.collection) return;
    await this.collection.insertOne(document);
  }

  public async health(): Promise<void> {
    if (!this.db) throw new Error("MongoDB client is not initialized");
    await this.db.command({ ping: 1 });
  }

  public async close(): Promise<void> {
    await this.client?.close();
  }
}

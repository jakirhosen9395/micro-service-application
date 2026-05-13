import { DeleteObjectCommand, GetObjectCommand, HeadBucketCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import type { Readable } from "node:stream";
import type { AppConfig } from "../config/config.js";
import { withApmSpan } from "../observability/apm.js";

export class S3Storage {
  public readonly client: S3Client;

  public constructor(private readonly config: AppConfig) {
    this.client = new S3Client({
      region: config.s3.region,
      endpoint: config.s3.endpoint,
      forcePathStyle: config.s3.forcePathStyle,
      credentials: {
        accessKeyId: config.s3.accessKey,
        secretAccessKey: config.s3.secretKey
      }
    });
  }

  public async health(): Promise<void> {
    await withApmSpan("s3.head_bucket", "storage", "s3", "head_bucket", () => this.client.send(new HeadBucketCommand({ Bucket: this.config.s3.bucket })).then(() => undefined));
  }

  public async putObject(input: { key: string; body: Buffer | string; contentType: string; metadata?: Record<string, string> }): Promise<void> {
    await withApmSpan("s3.put_object", "storage", "s3", "put_object", () => this.client.send(new PutObjectCommand({
      Bucket: this.config.s3.bucket,
      Key: input.key,
      Body: input.body,
      ContentType: input.contentType,
      Metadata: input.metadata
    })).then(() => undefined));
  }

  public async getObject(key: string): Promise<{ body: Readable; contentType?: string; contentLength?: number }> {
    const response = await withApmSpan("s3.get_object", "storage", "s3", "get_object", () => this.client.send(new GetObjectCommand({ Bucket: this.config.s3.bucket, Key: key })));
    if (!response.Body) throw new Error("S3 object has no body");
    return { body: response.Body as Readable, contentType: response.ContentType, contentLength: response.ContentLength };
  }

  public async getObjectAsBuffer(key: string, maxBytes?: number): Promise<{ buffer: Buffer; contentType?: string }> {
    const range = maxBytes ? `bytes=0-${Math.max(0, maxBytes - 1)}` : undefined;
    const response = await withApmSpan("s3.get_object_preview", "storage", "s3", "get_object", () => this.client.send(new GetObjectCommand({ Bucket: this.config.s3.bucket, Key: key, Range: range })));
    if (!response.Body) throw new Error("S3 object has no body");
    const chunks: Buffer[] = [];
    for await (const chunk of response.Body as AsyncIterable<Buffer | Uint8Array | string>) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    return { buffer: Buffer.concat(chunks), contentType: response.ContentType };
  }

  public async deleteObject(key: string): Promise<void> {
    await withApmSpan("s3.delete_object", "storage", "s3", "delete_object", () => this.client.send(new DeleteObjectCommand({ Bucket: this.config.s3.bucket, Key: key })).then(() => undefined));
  }
}

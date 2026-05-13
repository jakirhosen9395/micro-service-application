import { Kafka, logLevel, type Consumer, type EachMessagePayload, type KafkaMessage, type Producer, type Admin } from "kafkajs";
import type { AppConfig } from "../config/config.js";
import type { AppLogger } from "../logging/logger.js";
import type { EventEnvelope } from "../events/envelope.js";
import { eventHeaders, kafkaMessageKey } from "../events/envelope.js";
import { withApmSpan, withApmTransaction } from "../observability/apm.js";

export class KafkaBus {
  private readonly kafka: Kafka;
  private producer?: Producer;
  private admin?: Admin;
  private consumer?: Consumer;

  public constructor(private readonly config: AppConfig, private readonly logger: AppLogger) {
    this.kafka = new Kafka({
      clientId: config.service.name,
      brokers: config.kafka.bootstrapServers,
      logLevel: logLevel.NOTHING
    });
  }

  public async connectProducerAndAdmin(): Promise<void> {
    this.producer = this.kafka.producer({ allowAutoTopicCreation: this.config.kafka.autoCreateTopics });
    this.admin = this.kafka.admin();
    await withApmSpan("kafka.producer.connect", "messaging", "kafka", "connect", () => this.producer!.connect());
    await withApmSpan("kafka.admin.connect", "messaging", "kafka", "connect", () => this.admin!.connect());
    await this.ensureTopics();
  }

  public async ensureTopics(): Promise<void> {
    if (!this.admin || !this.config.kafka.autoCreateTopics) return;
    const topics = new Set<string>([
      this.config.kafka.eventsTopic,
      this.config.kafka.deadLetterTopic,
      ...this.config.kafka.consumeTopics
    ]);
    await withApmSpan("kafka.admin.create_topics", "messaging", "kafka", "create_topics", () => this.admin!.createTopics({
      waitForLeaders: true,
      topics: [...topics].map((topic) => ({ topic, numPartitions: 1, replicationFactor: 1 }))
    })).catch((error: unknown) => {
      const message = error instanceof Error ? error.message : String(error);
      if (!message.includes("Topic with this name already exists") && !message.includes("already exists")) throw error;
    });
  }

  public async publish(topic: string, envelope: EventEnvelope): Promise<void> {
    if (!this.producer) throw new Error("Kafka producer is not connected");
    await withApmSpan("kafka.producer.send", "messaging", "kafka", "send", () => this.producer!.send({
      topic,
      messages: [{
        key: kafkaMessageKey(envelope),
        value: JSON.stringify(envelope),
        headers: eventHeaders(envelope)
      }]
    }));
  }

  public async runConsumer(handler: (payload: EachMessagePayload) => Promise<void>): Promise<void> {
    this.consumer = this.kafka.consumer({ groupId: this.config.kafka.consumerGroup, allowAutoTopicCreation: this.config.kafka.autoCreateTopics });
    await withApmSpan("kafka.consumer.connect", "messaging", "kafka", "connect", () => this.consumer!.connect());
    for (const topic of this.config.kafka.consumeTopics) {
      await withApmSpan("kafka.consumer.subscribe", "messaging", "kafka", "subscribe", () => this.consumer!.subscribe({ topic, fromBeginning: false }));
    }
    await this.consumer.run({
      eachMessage: async (payload) => {
        await withApmTransaction(
          `Kafka consume ${payload.topic}`,
          "messaging",
          {
            messaging_system: "kafka",
            messaging_destination: payload.topic,
            kafka_topic: payload.topic,
            kafka_partition: payload.partition,
            kafka_offset: payload.message.offset
          },
          () => handler(payload)
        );
      }
    });
  }

  public parseMessage(message: KafkaMessage): EventEnvelope {
    if (!message.value) throw new Error("Kafka message has empty value");
    return JSON.parse(message.value.toString("utf8")) as EventEnvelope;
  }

  public async health(): Promise<void> {
    if (!this.admin) throw new Error("Kafka admin is not connected");
    await withApmSpan("kafka.admin.metadata", "messaging", "kafka", "metadata", () => this.admin!.fetchTopicMetadata({ topics: [this.config.kafka.eventsTopic] }));
  }

  public async close(): Promise<void> {
    await this.consumer?.disconnect().catch((error: unknown) => this.logger.warn("Kafka consumer disconnect failed", { event: "kafka.consumer.disconnect_failed", dependency: "kafka", extra: { error: error instanceof Error ? error.message : String(error) } }));
    await this.producer?.disconnect().catch((error: unknown) => this.logger.warn("Kafka producer disconnect failed", { event: "kafka.producer.disconnect_failed", dependency: "kafka", extra: { error: error instanceof Error ? error.message : String(error) } }));
    await this.admin?.disconnect().catch((error: unknown) => this.logger.warn("Kafka admin disconnect failed", { event: "kafka.admin.disconnect_failed", dependency: "kafka", extra: { error: error instanceof Error ? error.message : String(error) } }));
  }
}

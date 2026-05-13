package kafka

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"strings"
	"time"

	"user_service/internal/config"
	"user_service/internal/domain"
	"user_service/internal/logging"
	"user_service/internal/observability"
	"user_service/internal/persistence"

	kafkago "github.com/segmentio/kafka-go"
)

type Bus struct {
	cfg    config.Config
	log    *logging.Logger
	repo   persistence.Repository
	writer *kafkago.Writer
	reader *kafkago.Reader
	stop   chan struct{}
}

func New(ctx context.Context, cfg config.Config, log *logging.Logger, repo persistence.Repository) (*Bus, error) {
	b := &Bus{cfg: cfg, log: log, repo: repo, stop: make(chan struct{})}
	if err := b.Ping(ctx); err != nil {
		return nil, err
	}
	if cfg.KafkaAutoCreateTopics {
		_ = b.createTopics(ctx)
	}
	b.writer = &kafkago.Writer{Addr: kafkago.TCP(cfg.KafkaBootstrapServers...), Balancer: &kafkago.Hash{}, RequiredAcks: kafkago.RequireAll, Async: false, BatchTimeout: 100 * time.Millisecond}
	b.reader = kafkago.NewReader(kafkago.ReaderConfig{Brokers: cfg.KafkaBootstrapServers, GroupID: cfg.KafkaConsumerGroup, GroupTopics: cfg.KafkaConsumeTopics, MinBytes: 1, MaxBytes: 10e6, CommitInterval: time.Second})
	return b, nil
}

func (b *Bus) Close() error {
	if b == nil {
		return nil
	}
	select {
	case <-b.stop:
	default:
		close(b.stop)
	}
	if b.writer != nil {
		_ = b.writer.Close()
	}
	if b.reader != nil {
		return b.reader.Close()
	}
	return nil
}

func (b *Bus) Ping(ctx context.Context) error {
	if b == nil || len(b.cfg.KafkaBootstrapServers) == 0 {
		return errors.New("kafka not configured")
	}
	return observability.CaptureDependency(ctx, "Kafka broker ping", observability.SpanTypeKafka, func(spanCtx context.Context) error {
		for _, address := range b.cfg.KafkaBootstrapServers {
			d := net.Dialer{Timeout: 3 * time.Second}
			conn, err := d.DialContext(spanCtx, "tcp", address)
			if err == nil {
				_ = conn.Close()
				return nil
			}
		}
		return errors.New("kafka unavailable")
	})
}

func (b *Bus) createTopics(ctx context.Context) error {
	var conn *kafkago.Conn
	err := observability.CaptureDependency(ctx, "Kafka create topics connect", observability.SpanTypeKafka, func(spanCtx context.Context) error {
		var dialErr error
		conn, dialErr = kafkago.DialContext(spanCtx, "tcp", b.cfg.KafkaBootstrapServers[0])
		return dialErr
	})
	if err != nil {
		return err
	}
	defer conn.Close()
	topics := []string{b.cfg.KafkaEventsTopic, b.cfg.KafkaDeadLetterTopic}
	topics = append(topics, b.cfg.KafkaConsumeTopics...)
	configs := make([]kafkago.TopicConfig, 0, len(topics))
	seen := map[string]bool{}
	for _, t := range topics {
		t = strings.TrimSpace(t)
		if t == "" || seen[t] {
			continue
		}
		seen[t] = true
		configs = append(configs, kafkago.TopicConfig{Topic: t, NumPartitions: 3, ReplicationFactor: 1})
	}
	return observability.CaptureDependency(ctx, "Kafka create topics", observability.SpanTypeKafka, func(spanCtx context.Context) error {
		return conn.CreateTopics(configs...)
	})
}

func (b *Bus) Start(ctx context.Context) {
	go b.outboxLoop(ctx)
	go b.consumerLoop(ctx)
}

func (b *Bus) outboxLoop(ctx context.Context) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-b.stop:
			return
		case <-ticker.C:
			_ = observability.CaptureTransaction(ctx, "user.outbox.publish_batch", "messaging", func(txCtx context.Context) error {
				return b.publishOutbox(txCtx)
			})
		}
	}
}

func (b *Bus) publishOutbox(ctx context.Context) error {
	items, err := b.repo.LockOutboxBatch(ctx, 50)
	if err != nil {
		b.log.Error("kafka.outbox.lock.failed", "failed to lock outbox batch", map[string]any{"dependency": "kafka"}, err)
		return err
	}
	var batchErr error
	for _, item := range items {
		var envelope domain.EventEnvelope
		if err := json.Unmarshal(item.Payload, &envelope); err != nil {
			_ = b.repo.MarkOutboxFailed(ctx, item.ID, err.Error(), 10)
			if batchErr == nil {
				batchErr = err
			}
			continue
		}
		message := kafkago.Message{Topic: item.Topic, Key: []byte(kafkaKey(envelope)), Value: item.Payload, Headers: headers(envelope), Time: time.Now().UTC()}
		if err := observability.CaptureDependency(ctx, "Kafka publish "+item.Topic, observability.SpanTypeKafka, func(spanCtx context.Context) error {
			return b.writer.WriteMessages(spanCtx, message)
		}); err != nil {
			b.log.Error("kafka.publish.failed", "failed to publish outbox event", map[string]any{"event_id": envelope.EventID, "event_type": envelope.EventType, "dependency": "kafka"}, err)
			_ = b.repo.MarkOutboxFailed(ctx, item.ID, err.Error(), 10)
			_ = b.publishDeadLetter(ctx, envelope, err)
			if batchErr == nil {
				batchErr = err
			}
			continue
		}
		_ = b.repo.MarkOutboxSent(ctx, item.ID)
	}
	return batchErr
}

func (b *Bus) publishDeadLetter(ctx context.Context, envelope domain.EventEnvelope, cause error) error {
	if b.writer == nil {
		return cause
	}
	payload := domain.RawJSON(map[string]any{"event": envelope, "error": cause.Error(), "failed_at": time.Now().UTC().Format(time.RFC3339Nano)})
	return observability.CaptureDependency(ctx, "Kafka publish "+b.cfg.KafkaDeadLetterTopic, observability.SpanTypeKafka, func(spanCtx context.Context) error {
		return b.writer.WriteMessages(spanCtx, kafkago.Message{Topic: b.cfg.KafkaDeadLetterTopic, Key: []byte(kafkaKey(envelope)), Value: payload, Headers: headers(envelope), Time: time.Now().UTC()})
	})
}

func (b *Bus) consumerLoop(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-b.stop:
			return
		default:
		}
		var m kafkago.Message
		err := observability.CaptureDependency(ctx, "Kafka consume", observability.SpanTypeKafka, func(spanCtx context.Context) error {
			var fetchErr error
			m, fetchErr = b.reader.FetchMessage(spanCtx)
			return fetchErr
		})
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			b.log.Warn("kafka.consume.failed", "failed to fetch kafka message", map[string]any{"dependency": "kafka", "error": err.Error()})
			time.Sleep(time.Second)
			continue
		}
		if err := observability.CaptureTransaction(ctx, "user.kafka.consume "+m.Topic, "messaging", func(txCtx context.Context) error {
			return b.processMessage(txCtx, m)
		}); err != nil {
			b.log.Error("kafka.message.process.failed", "failed to process kafka message", map[string]any{"topic": m.Topic, "dependency": "kafka"}, err)
		}
	}
}

func (b *Bus) processMessage(ctx context.Context, m kafkago.Message) error {
	var envelope domain.EventEnvelope
	if err := json.Unmarshal(m.Value, &envelope); err != nil {
		_ = observability.CaptureDependency(ctx, "Kafka commit", observability.SpanTypeKafka, func(spanCtx context.Context) error { return b.reader.CommitMessages(spanCtx, m) })
		return err
	}
	if envelope.Service == b.cfg.ServiceName && m.Topic == b.cfg.KafkaEventsTopic {
		return observability.CaptureDependency(ctx, "Kafka commit", observability.SpanTypeKafka, func(spanCtx context.Context) error { return b.reader.CommitMessages(spanCtx, m) })
	}
	if err := b.repo.ProcessInboundEvent(ctx, m.Topic, m.Partition, m.Offset, envelope); err != nil {
		b.log.Error("kafka.inbox.process.failed", "failed to process inbound kafka event", map[string]any{"event_id": envelope.EventID, "event_type": envelope.EventType, "topic": m.Topic, "dependency": "kafka"}, err)
		return err
	}
	return observability.CaptureDependency(ctx, "Kafka commit", observability.SpanTypeKafka, func(spanCtx context.Context) error { return b.reader.CommitMessages(spanCtx, m) })
}

func headers(e domain.EventEnvelope) []kafkago.Header {
	return []kafkago.Header{{Key: "event_id", Value: []byte(e.EventID)}, {Key: "event_type", Value: []byte(e.EventType)}, {Key: "service", Value: []byte(e.Service)}, {Key: "tenant", Value: []byte(e.Tenant)}, {Key: "trace_id", Value: []byte(e.TraceID)}, {Key: "correlation_id", Value: []byte(e.CorrelationID)}}
}

func kafkaKey(e domain.EventEnvelope) string {
	if e.UserID != "" {
		return e.Tenant + ":" + e.UserID
	}
	return e.Tenant + ":" + e.AggregateID
}

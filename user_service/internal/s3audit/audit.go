package s3audit

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"time"

	"user_service/internal/config"
	"user_service/internal/domain"
	"user_service/internal/observability"
	"user_service/internal/platform"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type Writer struct {
	cfg    config.Config
	client *minio.Client
}

func New(ctx context.Context, cfg config.Config) (*Writer, error) {
	u, err := url.Parse(cfg.S3Endpoint)
	if err != nil {
		return nil, err
	}
	secure := u.Scheme == "https"
	endpoint := u.Host
	if endpoint == "" {
		endpoint = strings.TrimPrefix(strings.TrimPrefix(cfg.S3Endpoint, "http://"), "https://")
	}
	client, err := minio.New(endpoint, &minio.Options{Creds: credentials.NewStaticV4(cfg.S3AccessKey, cfg.S3SecretKey, ""), Secure: secure, Region: cfg.S3Region})
	if err != nil {
		return nil, err
	}
	w := &Writer{cfg: cfg, client: client}
	if err := w.Ping(ctx); err != nil {
		return nil, err
	}
	return w, nil
}

func (w *Writer) Ping(ctx context.Context) error {
	if w == nil || w.client == nil {
		return fmt.Errorf("s3 client not initialized")
	}
	var ok bool
	err := observability.CaptureDependency(ctx, "S3 bucket exists", observability.SpanTypeS3, func(spanCtx context.Context) error {
		var existsErr error
		ok, existsErr = w.client.BucketExists(spanCtx, w.cfg.S3Bucket)
		return existsErr
	})
	if err != nil {
		return err
	}
	if !ok {
		return fmt.Errorf("s3 bucket %s does not exist", w.cfg.S3Bucket)
	}
	return nil
}

func (w *Writer) Write(ctx context.Context, event domain.EventEnvelope, meta domain.RequestMeta, targetUserID string) (string, error) {
	if w == nil || w.client == nil {
		return "", fmt.Errorf("s3 client not initialized")
	}
	actor := event.ActorID
	if actor == "" {
		actor = event.UserID
	}
	timestamp := time.Now().UTC()
	key := AuditKey(w.cfg.ServiceName, w.cfg.Environment, event.Tenant, actor, timestamp, event.EventType, event.EventID)
	body := map[string]any{
		"event_id":       event.EventID,
		"event_type":     event.EventType,
		"service":        event.Service,
		"environment":    event.Environment,
		"tenant":         event.Tenant,
		"user_id":        event.UserID,
		"actor_id":       event.ActorID,
		"target_user_id": nullableString(targetUserID),
		"aggregate_type": event.AggregateType,
		"aggregate_id":   event.AggregateID,
		"request_id":     event.RequestID,
		"trace_id":       event.TraceID,
		"correlation_id": event.CorrelationID,
		"client_ip":      meta.ClientIP,
		"user_agent":     meta.UserAgent,
		"timestamp":      timestamp.Format(time.RFC3339Nano),
		"payload":        json.RawMessage(event.Payload),
	}
	b, err := json.MarshalIndent(body, "", "  ")
	if err != nil {
		return "", err
	}
	err = observability.CaptureDependency(ctx, "S3 put audit snapshot", observability.SpanTypeS3, func(spanCtx context.Context) error {
		_, putErr := w.client.PutObject(spanCtx, w.cfg.S3Bucket, key, bytes.NewReader(b), int64(len(b)), minio.PutObjectOptions{ContentType: "application/json"})
		return putErr
	})
	if err != nil {
		return "", err
	}
	return key, nil
}

func AuditKey(service, environment, tenant, actorUserID string, ts time.Time, eventType, eventID string) string {
	return fmt.Sprintf("%s/%s/tenant/%s/users/%s/events/%04d/%02d/%02d/%02d%02d%02d_%s_%s.json", service, environment, tenant, actorUserID, ts.UTC().Year(), ts.UTC().Month(), ts.UTC().Day(), ts.UTC().Hour(), ts.UTC().Minute(), ts.UTC().Second(), platform.EventTypeSlug(eventType), eventID)
}

func nullableString(v string) any {
	if v == "" {
		return nil
	}
	return v
}

package logging

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"
	"time"

	"user_service/internal/config"
)

type MongoSink interface {
	WriteLog(ctx context.Context, doc map[string]any) error
}

type Logger struct {
	cfg  config.Config
	out  io.Writer
	mu   sync.Mutex
	sink MongoSink
	host string
}

func New(cfg config.Config) *Logger {
	host, _ := os.Hostname()
	return &Logger{cfg: cfg, out: os.Stdout, host: host}
}

func (l *Logger) AttachMongoSink(s MongoSink) { l.sink = s }

func (l *Logger) Info(event, message string, fields map[string]any) {
	l.write("INFO", event, message, fields, nil)
}
func (l *Logger) Warn(event, message string, fields map[string]any) {
	l.write("WARN", event, message, fields, nil)
}
func (l *Logger) Error(event, message string, fields map[string]any, err error) {
	l.write("ERROR", event, message, fields, err)
}

func (l *Logger) write(level, event, message string, fields map[string]any, err error) {
	if fields == nil {
		fields = map[string]any{}
	}
	doc := map[string]any{
		"timestamp":         time.Now().UTC().Format(time.RFC3339Nano),
		"level":             level,
		"service":           l.cfg.ServiceName,
		"version":           l.cfg.Version,
		"environment":       l.cfg.Environment,
		"tenant":            l.cfg.Tenant,
		"logger":            stringOr(fields, "logger", "app"),
		"event":             event,
		"message":           message,
		"request_id":        stringOr(fields, "request_id", ""),
		"trace_id":          stringOr(fields, "trace_id", ""),
		"correlation_id":    stringOr(fields, "correlation_id", ""),
		"elastic_trace_id":  firstString(fields, "elastic_trace_id", "trace.id"),
		"elastic_transaction_id": firstString(fields, "elastic_transaction_id", "transaction.id"),
		"elastic_span_id":        firstString(fields, "elastic_span_id", "span.id"),
		"user_id":           stringOr(fields, "user_id", ""),
		"actor_id":          stringOr(fields, "actor_id", ""),
		"method":            stringOr(fields, "method", ""),
		"path":              stringOr(fields, "path", ""),
		"status_code":       intOr(fields, "status_code", 0),
		"duration_ms":       numberOr(fields, "duration_ms", 0),
		"client_ip":         stringOr(fields, "client_ip", ""),
		"user_agent":        stringOr(fields, "user_agent", ""),
		"dependency":        stringOr(fields, "dependency", ""),
		"error_code":        stringOr(fields, "error_code", ""),
		"exception_class":   nil,
		"exception_message": nil,
		"stack_trace":       nil,
		"host":              l.host,
		"extra":             sanitize(fields),
	}
	if err != nil {
		doc["exception_class"] = fmt.Sprintf("%T", err)
		doc["exception_message"] = err.Error()
	}
	stdoutDoc := copyMap(doc)
	stdoutDoc["service.name"] = l.cfg.ServiceName
	stdoutDoc["service.version"] = l.cfg.Version
	stdoutDoc["service.environment"] = l.cfg.Environment
	stdoutDoc["service.node.name"] = l.host
	stdoutDoc["event.dataset"] = fmt.Sprintf("%s.%s", l.cfg.ServiceName, doc["logger"])
	stdoutDoc["trace.id"] = doc["elastic_trace_id"]
	stdoutDoc["transaction.id"] = doc["elastic_transaction_id"]
	stdoutDoc["span.id"] = doc["elastic_span_id"]
	l.mu.Lock()
	enc := json.NewEncoder(l.out)
	enc.SetIndent("", "  ")
	_ = enc.Encode(stdoutDoc)
	l.mu.Unlock()
	if l.sink != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
		defer cancel()
		_ = l.sink.WriteLog(ctx, doc)
	}
}

func firstString(m map[string]any, keys ...string) string {
	for _, key := range keys {
		if v, ok := m[key]; ok && v != nil {
			value := fmt.Sprint(v)
			if value != "" {
				return value
			}
		}
	}
	return ""
}

func copyMap(in map[string]any) map[string]any {
	out := make(map[string]any, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}

func stringOr(m map[string]any, key, fallback string) string {
	if v, ok := m[key]; ok && v != nil {
		return fmt.Sprint(v)
	}
	return fallback
}

func intOr(m map[string]any, key string, fallback int) int {
	if v, ok := m[key]; ok {
		switch t := v.(type) {
		case int:
			return t
		case int64:
			return int(t)
		case float64:
			return int(t)
		}
	}
	return fallback
}

func numberOr(m map[string]any, key string, fallback float64) float64 {
	if v, ok := m[key]; ok {
		switch t := v.(type) {
		case float64:
			return t
		case float32:
			return float64(t)
		case int:
			return float64(t)
		case int64:
			return float64(t)
		}
	}
	return fallback
}

func sanitize(v any) any {
	switch t := v.(type) {
	case map[string]any:
		out := make(map[string]any, len(t))
		for k, v := range t {
			safeKey := strings.ReplaceAll(k, ".", "_")
			lk := strings.ToLower(k)
			if strings.Contains(lk, "password") || strings.Contains(lk, "secret") || strings.Contains(lk, "token") || strings.Contains(lk, "authorization") || strings.Contains(lk, "access_key") || strings.Contains(lk, "secret_key") || strings.Contains(lk, "jwt") {
				out[safeKey] = "[REDACTED]"
				continue
			}
			out[safeKey] = sanitize(v)
		}
		return out
	case []any:
		out := make([]any, len(t))
		for i := range t {
			out[i] = sanitize(t[i])
		}
		return out
	default:
		return t
	}
}

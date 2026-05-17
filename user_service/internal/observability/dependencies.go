package observability

import (
	"context"

	"go.elastic.co/apm/v2"
)

const (
	SpanTypePostgres      = "db.postgresql.query"
	SpanTypeRedis         = "cache.redis"
	SpanTypeKafka         = "messaging.kafka"
	SpanTypeS3            = "storage.s3"
	SpanTypeMongoDB       = "db.mongodb.query"
	SpanTypeElasticsearch = "db.elasticsearch.query"
	SpanTypeAPMServer     = "external.http"
	SpanTypeHTTP          = "external.http"
)

// StartDependencySpan creates an Elastic APM exit span. Kibana APM's
// Dependencies view is populated from exit/dependency spans, not from health
// JSON alone. Use a semantic name plus an Elastic span type/subtype/action such
// as db.postgresql.query, cache.redis, messaging.kafka, or storage.s3.
func StartDependencySpan(ctx context.Context, name, spanType string) (*apm.Span, context.Context) {
	span, next := apm.StartSpanOptions(ctx, name, spanType, apm.SpanOptions{ExitSpan: true})
	return span, next
}

// CaptureDependency wraps a dependency call in an APM span. It intentionally does
// not log arguments, connection strings, credentials, Authorization headers, or
// other sensitive values.
func CaptureDependency(ctx context.Context, name, spanType string, fn func(context.Context) error) error {
	span, spanCtx := StartDependencySpan(ctx, name, spanType)
	if span != nil {
		defer span.End()
	}
	err := fn(spanCtx)
	if span != nil {
		if err != nil {
			span.Outcome = "failure"
		} else {
			span.Outcome = "success"
		}
	}
	if err != nil {
		CaptureError(spanCtx, err)
	}
	return err
}

// CaptureDependencyNoError wraps a non-critical dependency call in an APM span
// without sending the returned error as an exception. Use this for optional
// cache paths where the caller can safely degrade to the source of truth.
func CaptureDependencyNoError(ctx context.Context, name, spanType string, fn func(context.Context) error) error {
	span, spanCtx := StartDependencySpan(ctx, name, spanType)
	if span != nil {
		defer span.End()
	}
	err := fn(spanCtx)
	if span != nil {
		if err != nil {
			span.Outcome = "failure"
		} else {
			span.Outcome = "success"
		}
	}
	return err
}

func CaptureTransaction(ctx context.Context, name, transactionType string, fn func(context.Context) error) error {
	tx := apm.DefaultTracer().StartTransaction(name, transactionType)
	tx.Context.SetLabel("component", transactionType)
	txCtx := apm.ContextWithTransaction(ctx, tx)
	defer tx.End()

	err := fn(txCtx)
	if err != nil {
		tx.Result = "failure"
		tx.Outcome = "failure"
		CaptureError(txCtx, err)
		return err
	}
	tx.Result = "success"
	tx.Outcome = "success"
	return nil
}

func CaptureError(ctx context.Context, err error) {
	if err == nil {
		return
	}
	if captured := apm.CaptureError(ctx, err); captured != nil {
		captured.Send()
	}
}

func TraceFields(ctx context.Context) map[string]any {
	fields := map[string]any{}
	tx := apm.TransactionFromContext(ctx)
	if tx == nil {
		return fields
	}
	traceContext := tx.TraceContext()
	traceID := traceContext.Trace.String()
	transactionID := traceContext.Span.String()
	if traceID != "" {
		fields["elastic_trace_id"] = traceID
		fields["trace.id"] = traceID
	}
	if transactionID != "" {
		fields["elastic_transaction_id"] = transactionID
		fields["transaction.id"] = transactionID
	}
	return fields
}

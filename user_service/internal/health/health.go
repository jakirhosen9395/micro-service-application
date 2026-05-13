package health

import (
	"context"
	"net/http"
	"time"

	"user_service/internal/config"
	"user_service/internal/domain"
	"user_service/internal/observability"

	"go.elastic.co/apm/module/apmhttp/v2"
)

type Pingable interface {
	Ping(ctx context.Context) error
}

type Checker struct {
	cfg        config.Config
	Postgres   Pingable
	Redis      Pingable
	Kafka      Pingable
	S3         Pingable
	MongoDB    Pingable
	HTTPClient *http.Client
}

type Dependency struct {
	Status    string  `json:"status"`
	LatencyMS float64 `json:"latency_ms"`
	ErrorCode string  `json:"error_code,omitempty"`
}

type Response struct {
	Status       string                `json:"status"`
	Service      string                `json:"service"`
	Version      string                `json:"version"`
	Environment  string                `json:"environment"`
	Timestamp    string                `json:"timestamp"`
	Dependencies map[string]Dependency `json:"dependencies"`
}

func New(cfg config.Config, pg Pingable, redis Pingable, kafka Pingable, s3 Pingable, mongo Pingable) *Checker {
	return &Checker{cfg: cfg, Postgres: pg, Redis: redis, Kafka: kafka, S3: s3, MongoDB: mongo, HTTPClient: apmhttp.WrapClient(&http.Client{Timeout: 3 * time.Second})}
}

func (c *Checker) Check(ctx context.Context) (Response, int) {
	deps := map[string]Dependency{
		"jwt":           c.checkJWT(),
		"postgres":      c.checkPing(ctx, c.Postgres, "POSTGRES_UNAVAILABLE"),
		"redis":         c.checkPing(ctx, c.Redis, "REDIS_UNAVAILABLE"),
		"kafka":         c.checkPing(ctx, c.Kafka, "KAFKA_UNAVAILABLE"),
		"s3":            c.checkPing(ctx, c.S3, "S3_UNAVAILABLE"),
		"mongodb":       c.checkPing(ctx, c.MongoDB, "MONGODB_UNAVAILABLE"),
		"apm":           c.checkHTTP(ctx, c.cfg.APMServerURL, "APM_UNAVAILABLE", "Bearer "+c.cfg.APMSecretToken),
		"elasticsearch": c.checkElasticsearch(ctx),
	}
	status := "ok"
	code := http.StatusOK
	for _, dep := range deps {
		if dep.Status != "ok" {
			status = "down"
			code = http.StatusServiceUnavailable
			break
		}
	}
	return Response{Status: status, Service: c.cfg.ServiceName, Version: c.cfg.Version, Environment: c.cfg.Environment, Timestamp: time.Now().UTC().Format(time.RFC3339Nano), Dependencies: deps}, code
}

func (c *Checker) checkJWT() Dependency {
	start := time.Now()
	if c.cfg.JWTSecret == "" || c.cfg.JWTIssuer != "auth" || c.cfg.JWTAudience != "micro-app" || c.cfg.JWTAlgorithm != "HS256" {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: "JWT_CONFIG_INVALID"}
	}
	return Dependency{Status: "ok", LatencyMS: ms(start)}
}

func (c *Checker) checkPing(ctx context.Context, p Pingable, code string) Dependency {
	start := time.Now()
	if p == nil {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: code}
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	if err := p.Ping(ctx); err != nil {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: code}
	}
	return Dependency{Status: "ok", LatencyMS: ms(start)}
}

func (c *Checker) checkHTTP(ctx context.Context, url, code, auth string) Dependency {
	start := time.Now()
	spanName := "APM server health"
	spanType := observability.SpanTypeAPMServer
	if code != "APM_UNAVAILABLE" {
		spanName = "HTTP dependency health"
		spanType = observability.SpanTypeHTTP
	}
	span, spanCtx := observability.StartDependencySpan(ctx, spanName, spanType)
	if span != nil {
		defer span.End()
	}
	if url == "" {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: code}
	}
	req, err := http.NewRequestWithContext(spanCtx, http.MethodGet, url, nil)
	if err != nil {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: code}
	}
	if auth != "Bearer " {
		req.Header.Set("Authorization", auth)
	}
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: code}
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 500 {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: code}
	}
	return Dependency{Status: "ok", LatencyMS: ms(start)}
}

func (c *Checker) checkElasticsearch(ctx context.Context) Dependency {
	start := time.Now()
	span, spanCtx := observability.StartDependencySpan(ctx, "Elasticsearch health", observability.SpanTypeElasticsearch)
	if span != nil {
		defer span.End()
	}
	req, err := http.NewRequestWithContext(spanCtx, http.MethodGet, c.cfg.ElasticsearchURL, nil)
	if err != nil {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: "ELASTICSEARCH_UNAVAILABLE"}
	}
	if c.cfg.ElasticsearchUsername != "" {
		req.SetBasicAuth(c.cfg.ElasticsearchUsername, c.cfg.ElasticsearchPassword)
	}
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: "ELASTICSEARCH_UNAVAILABLE"}
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return Dependency{Status: "down", LatencyMS: ms(start), ErrorCode: "ELASTICSEARCH_UNAVAILABLE"}
	}
	return Dependency{Status: "ok", LatencyMS: ms(start)}
}

func ms(start time.Time) float64 { return float64(time.Since(start).Microseconds()) / 1000.0 }

func PublicHello(cfg config.Config) map[string]any {
	return map[string]any{"status": "ok", "message": cfg.ServiceName + " is running", "service": map[string]any{"name": cfg.ServiceName, "env": cfg.Environment, "version": cfg.Version}}
}

func ReportTypes(formats []string) []domain.ReportType {
	return []domain.ReportType{
		{ReportType: "calculator_history_report", Name: "Calculator history", Description: "Projected calculator history for a user.", Formats: formats, Scopes: []string{"calculator:history:read"}},
		{ReportType: "todo_summary_report", Name: "Todo summary", Description: "Projected todo summary and activity for a user.", Formats: formats, Scopes: []string{"todo:history:read"}},
		{ReportType: "user_activity_report", Name: "User activity", Description: "User profile, preference, access, report, todo, and calculation activity.", Formats: formats, Scopes: []string{"user:activity:read"}},
		{ReportType: "user_dashboard_report", Name: "User dashboard", Description: "Aggregated user dashboard snapshot.", Formats: formats, Scopes: []string{"user:dashboard:read"}},
	}
}

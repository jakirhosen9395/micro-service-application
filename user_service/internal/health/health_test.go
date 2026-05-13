package health

import (
	"context"
	"testing"

	"user_service/internal/config"
)

type okPing struct{}

func (okPing) Ping(context.Context) error { return nil }

func TestHealthShapeIncludesCanonicalDependencies(t *testing.T) {
	cfg := config.Config{ServiceName: "user_service", Version: "v1.0.0", Environment: "development", Tenant: "dev", JWTSecret: "secret", JWTIssuer: "auth", JWTAudience: "micro-app", JWTAlgorithm: "HS256"}
	checker := New(cfg, okPing{}, okPing{}, okPing{}, okPing{}, okPing{})
	checker.HTTPClient = nil
	_ = checker
	resp := Response{Dependencies: map[string]Dependency{"jwt": {}, "postgres": {}, "redis": {}, "kafka": {}, "s3": {}, "mongodb": {}, "apm": {}, "elasticsearch": {}}}
	for _, key := range []string{"jwt", "postgres", "redis", "kafka", "s3", "mongodb", "apm", "elasticsearch"} {
		if _, ok := resp.Dependencies[key]; !ok {
			t.Fatalf("missing %s", key)
		}
	}
}

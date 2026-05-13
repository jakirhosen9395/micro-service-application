package security

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"user_service/internal/config"
)

func TestValidateAuthServiceJWTClaims(t *testing.T) {
	cfg := config.Config{JWTSecret: "secret", JWTIssuer: "auth", JWTAudience: "micro-app", JWTAlgorithm: "HS256", JWTLeeway: 5 * time.Second, Tenant: "dev", SecurityRequireTenantMatch: true}
	now := time.Now().Unix()
	token := sign(t, cfg.JWTSecret, map[string]any{"iss": "auth", "aud": "micro-app", "sub": "user-uuid", "jti": "token-id", "username": "jakir", "email": "jakir@example.com", "role": "user", "admin_status": "not_requested", "tenant": "dev", "iat": now, "nbf": now, "exp": now + 900})
	claims, err := Validate(token, cfg)
	if err != nil {
		t.Fatalf("Validate() error = %v", err)
	}
	if claims.Subject != "user-uuid" || claims.Role != "user" || claims.Tenant != "dev" {
		t.Fatalf("unexpected claims: %+v", claims)
	}
}

func sign(t *testing.T, secret string, payload map[string]any) string {
	t.Helper()
	header, _ := json.Marshal(map[string]any{"alg": "HS256", "typ": "JWT"})
	body, _ := json.Marshal(payload)
	encoded := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(body)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(encoded))
	return strings.Join([]string{encoded, base64.RawURLEncoding.EncodeToString(mac.Sum(nil))}, ".")
}

func TestValidateTenantMismatchIsForbiddenClass(t *testing.T) {
	cfg := config.Config{JWTSecret: "secret", JWTIssuer: "auth", JWTAudience: "micro-app", JWTAlgorithm: "HS256", JWTLeeway: 5 * time.Second, Tenant: "dev", SecurityRequireTenantMatch: true}
	now := time.Now().Unix()
	token := sign(t, cfg.JWTSecret, map[string]any{"iss": "auth", "aud": "micro-app", "sub": "user-uuid", "jti": "token-id", "role": "user", "admin_status": "not_requested", "tenant": "other", "iat": now, "nbf": now, "exp": now + 900})
	_, err := Validate(token, cfg)
	if err != ErrInvalidTenant {
		t.Fatalf("expected ErrInvalidTenant, got %v", err)
	}
}

func TestValidateSuspendedUser(t *testing.T) {
	cfg := config.Config{JWTSecret: "secret", JWTIssuer: "auth", JWTAudience: "micro-app", JWTAlgorithm: "HS256", JWTLeeway: 5 * time.Second, Tenant: "dev", SecurityRequireTenantMatch: true}
	now := time.Now().Unix()
	token := sign(t, cfg.JWTSecret, map[string]any{"iss": "auth", "aud": "micro-app", "sub": "user-uuid", "jti": "token-id", "role": "user", "admin_status": "suspended", "tenant": "dev", "iat": now, "nbf": now, "exp": now + 900})
	_, err := Validate(token, cfg)
	if err != ErrSuspendedUser {
		t.Fatalf("expected ErrSuspendedUser, got %v", err)
	}
}

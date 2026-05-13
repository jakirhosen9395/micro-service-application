package security

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"user_service/internal/config"
	"user_service/internal/domain"
)

var (
	ErrMissingToken       = errors.New("missing bearer token")
	ErrInvalidToken       = errors.New("invalid token")
	ErrExpiredToken       = errors.New("expired token")
	ErrInvalidTenant      = errors.New("tenant mismatch")
	ErrInvalidRole        = errors.New("invalid role")
	ErrInvalidAdminStatus = errors.New("invalid admin_status")
	ErrSuspendedUser      = errors.New("suspended or inactive user")
)

func ValidateBearer(header string, cfg config.Config) (domain.Claims, error) {
	header = strings.TrimSpace(header)
	if header == "" || !strings.HasPrefix(strings.ToLower(header), "bearer ") {
		return domain.Claims{}, ErrMissingToken
	}
	return Validate(strings.TrimSpace(header[7:]), cfg)
}

func Validate(token string, cfg config.Config) (domain.Claims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return domain.Claims{}, ErrInvalidToken
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return domain.Claims{}, ErrInvalidToken
	}
	var header struct {
		Alg string `json:"alg"`
		Typ string `json:"typ"`
	}
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return domain.Claims{}, ErrInvalidToken
	}
	if strings.ToUpper(header.Alg) != cfg.JWTAlgorithm || strings.ToUpper(header.Alg) != "HS256" {
		return domain.Claims{}, ErrInvalidToken
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return domain.Claims{}, ErrInvalidToken
	}
	mac := hmac.New(sha256.New, []byte(cfg.JWTSecret))
	mac.Write([]byte(parts[0] + "." + parts[1]))
	if !hmac.Equal(sig, mac.Sum(nil)) {
		return domain.Claims{}, ErrInvalidToken
	}
	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return domain.Claims{}, ErrInvalidToken
	}
	var raw map[string]any
	if err := json.Unmarshal(payloadBytes, &raw); err != nil {
		return domain.Claims{}, ErrInvalidToken
	}
	claims, err := parseClaims(raw)
	if err != nil {
		return domain.Claims{}, err
	}
	now := time.Now().UTC().Unix()
	leeway := int64(cfg.JWTLeeway.Seconds())
	if claims.ExpiresAt != 0 && now > claims.ExpiresAt+leeway {
		return domain.Claims{}, ErrExpiredToken
	}
	if claims.NotBefore != 0 && now+leeway < claims.NotBefore {
		return domain.Claims{}, ErrInvalidToken
	}
	if claims.IssuedAt != 0 && now+leeway < claims.IssuedAt {
		return domain.Claims{}, ErrInvalidToken
	}
	if claims.Issuer != cfg.JWTIssuer || claims.Audience != cfg.JWTAudience || claims.Subject == "" || claims.JTI == "" {
		return domain.Claims{}, ErrInvalidToken
	}
	if cfg.SecurityRequireTenantMatch && claims.Tenant != cfg.Tenant {
		return domain.Claims{}, ErrInvalidTenant
	}
	if !allowedRole(claims.Role) {
		return domain.Claims{}, ErrInvalidRole
	}
	if !allowedAdminStatus(claims.AdminStatus) {
		return domain.Claims{}, ErrInvalidAdminStatus
	}
	if claims.AdminStatus == "suspended" || (claims.Status != "" && claims.Status != "active") {
		return domain.Claims{}, ErrSuspendedUser
	}
	return claims, nil
}

func parseClaims(raw map[string]any) (domain.Claims, error) {
	claims := domain.Claims{
		Subject:     stringClaim(raw, "sub"),
		JTI:         stringClaim(raw, "jti"),
		Username:    stringClaim(raw, "username"),
		Email:       stringClaim(raw, "email"),
		Role:        stringClaim(raw, "role"),
		AdminStatus: stringClaim(raw, "admin_status"),
		Tenant:      stringClaim(raw, "tenant"),
		Issuer:      stringClaim(raw, "iss"),
		Audience:    audienceClaim(raw["aud"]),
		Status:      stringClaim(raw, "status"),
		IssuedAt:    intClaim(raw, "iat"),
		NotBefore:   intClaim(raw, "nbf"),
		ExpiresAt:   intClaim(raw, "exp"),
	}
	if claims.Role == "" {
		claims.Role = "user"
	}
	if claims.AdminStatus == "" {
		claims.AdminStatus = "not_requested"
	}
	return claims, nil
}

func stringClaim(raw map[string]any, key string) string {
	if v, ok := raw[key]; ok && v != nil {
		return fmt.Sprint(v)
	}
	return ""
}

func audienceClaim(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case []any:
		if len(t) > 0 {
			return fmt.Sprint(t[0])
		}
	}
	return ""
}

func intClaim(raw map[string]any, key string) int64 {
	if v, ok := raw[key]; ok && v != nil {
		switch t := v.(type) {
		case float64:
			return int64(t)
		case int64:
			return t
		case int:
			return int64(t)
		case json.Number:
			n, _ := t.Int64()
			return n
		}
	}
	return 0
}

func allowedRole(role string) bool {
	switch role {
	case "user", "admin", "service", "system":
		return true
	default:
		return false
	}
}

func allowedAdminStatus(status string) bool {
	switch status {
	case "not_requested", "pending", "approved", "rejected", "suspended":
		return true
	default:
		return false
	}
}

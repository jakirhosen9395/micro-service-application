package platform

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"
)

func Now() time.Time { return time.Now().UTC() }

func Timestamp() string { return Now().Format(time.RFC3339Nano) }

func NewID(prefix string) string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
	}
	return fmt.Sprintf("%s-%s-%s-%s-%s-%s", prefix, hex.EncodeToString(b[0:4]), hex.EncodeToString(b[4:6]), hex.EncodeToString(b[6:8]), hex.EncodeToString(b[8:10]), hex.EncodeToString(b[10:16]))
}

func RequestID() string     { return NewID("req") }
func TraceID() string       { return NewID("trace") }
func EventID() string       { return NewID("evt") }
func CorrelationID() string { return NewID("corr") }

func ClientIP(r *http.Request) string {
	for _, h := range []string{"X-Forwarded-For", "X-Real-IP", "CF-Connecting-IP"} {
		if value := strings.TrimSpace(r.Header.Get(h)); value != "" {
			parts := strings.Split(value, ",")
			return strings.TrimSpace(parts[0])
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func JSONTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339Nano)
}

func EventTypeSlug(eventType string) string {
	replacer := strings.NewReplacer(".", "_", "/", "_", " ", "_", ":", "_")
	return strings.Trim(replacer.Replace(strings.ToLower(eventType)), "_")
}

func ContainsScope(actualScope, requiredScope string) bool {
	actualScope = strings.TrimSpace(strings.ToLower(actualScope))
	requiredScope = strings.TrimSpace(strings.ToLower(requiredScope))
	if actualScope == "*" || actualScope == "*:*" || actualScope == requiredScope {
		return true
	}
	parts := strings.Split(requiredScope, ":")
	if len(parts) > 0 && (actualScope == parts[0]+":*" || strings.HasPrefix(requiredScope, actualScope+":")) {
		return true
	}
	return false
}

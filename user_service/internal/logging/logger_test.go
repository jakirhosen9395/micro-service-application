package logging

import "testing"

func TestSanitizeRedactsSecrets(t *testing.T) {
	got := sanitize(map[string]any{"password": "x", "jwt_secret": "y", "safe": "z"}).(map[string]any)
	if got["password"] != "[REDACTED]" || got["jwt_secret"] != "[REDACTED]" || got["safe"] != "z" {
		t.Fatalf("unexpected redaction: %#v", got)
	}
}

package httpapi

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"user_service/internal/observability"
)

type successEnvelope struct {
	Status    string `json:"status"`
	Message   string `json:"message"`
	Data      any    `json:"data"`
	RequestID string `json:"request_id"`
	TraceID   string `json:"trace_id"`
	Timestamp string `json:"timestamp"`
}

type errorEnvelope struct {
	Status    string         `json:"status"`
	Message   string         `json:"message"`
	ErrorCode string         `json:"error_code"`
	Details   map[string]any `json:"details"`
	Path      string         `json:"path"`
	RequestID string         `json:"request_id"`
	TraceID   string         `json:"trace_id"`
	Timestamp string         `json:"timestamp"`
}

func writeSuccess(w http.ResponseWriter, r *http.Request, status int, message string, data any) {
	writeJSON(w, status, successEnvelope{Status: "ok", Message: message, Data: data, RequestID: requestID(r), TraceID: traceID(r), Timestamp: time.Now().UTC().Format(time.RFC3339Nano)})
}

func writeError(w http.ResponseWriter, r *http.Request, status int, code, message string, details map[string]any) {
	if details == nil {
		details = map[string]any{}
	}
	if status >= http.StatusInternalServerError {
		observability.CaptureError(r.Context(), fmt.Errorf("%s: %s", code, message))
	}
	writeJSON(w, status, errorEnvelope{Status: "error", Message: message, ErrorCode: code, Details: details, Path: r.URL.Path, RequestID: requestID(r), TraceID: traceID(r), Timestamp: time.Now().UTC().Format(time.RFC3339Nano)})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(payload)
}

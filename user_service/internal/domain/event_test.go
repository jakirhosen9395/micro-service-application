package domain

import (
	"encoding/json"
	"testing"
)

func TestCanonicalEventEnvelopeCarriesAggregateFields(t *testing.T) {
	e := EventEnvelope{EventID: "evt-1", EventType: "user.profile.updated", EventVersion: "1.0", Service: "user_service", Environment: "development", Tenant: "dev", UserID: "u1", ActorID: "u1", AggregateType: "user_profile", AggregateID: "u1", Payload: RawJSON(map[string]any{"full_name": "A"})}
	b, err := json.Marshal(e)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"event_id", "event_type", "service", "tenant", "aggregate_type", "aggregate_id", "payload"} {
		if _, ok := got[key]; !ok {
			t.Fatalf("missing %s", key)
		}
	}
}

func TestEventEnvelopeAcceptsNumericTimestamp(t *testing.T) {
	payload := []byte(`{"event_id":"evt-1","event_type":"todo.created","event_version":"1.0","service":"todo_list_service","environment":"development","tenant":"dev","timestamp":1763212345.123,"payload":{}}`)
	var event EventEnvelope
	if err := json.Unmarshal(payload, &event); err != nil {
		t.Fatalf("expected numeric timestamp to unmarshal, got %v", err)
	}
	if event.Timestamp == "" {
		t.Fatal("expected timestamp to be normalized")
	}
}

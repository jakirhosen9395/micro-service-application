package rbac

import (
	"testing"

	"user_service/internal/domain"
)

func TestEvaluateAllowsRequesterSameUser(t *testing.T) {
	claims := domain.Claims{Subject: "user-1", Tenant: "dev", Role: "user", AdminStatus: "not_requested"}
	decision := Evaluate(claims, "user-1", "calculator", "calculator:history:read")
	if !decision.Allowed() || decision.Reason != ReasonSameUser {
		t.Fatalf("expected same-user allow, got %#v", decision)
	}
}

func TestEvaluateAllowsApprovedAdminCrossUser(t *testing.T) {
	claims := domain.Claims{Subject: "admin-1", Tenant: "dev", Role: "admin", AdminStatus: "approved"}
	decision := Evaluate(claims, "user-1", "calculator", "calculator:history:read")
	if !decision.Allowed() || decision.Reason != ReasonApprovedAdmin {
		t.Fatalf("expected approved-admin allow, got %#v", decision)
	}
}

func TestEvaluateRequiresGrantForNormalCrossUser(t *testing.T) {
	claims := domain.Claims{Subject: "user-1", Tenant: "dev", Role: "user", AdminStatus: "not_requested"}
	decision := Evaluate(claims, "user-2", "calculator", "calculator:history:read")
	if !decision.NeedsGrant() || decision.Reason != ReasonGrantRequired {
		t.Fatalf("expected grant requirement, got %#v", decision)
	}
}

func TestEvaluateDeniesSuspendedActor(t *testing.T) {
	claims := domain.Claims{Subject: "admin-1", Tenant: "dev", Role: "admin", AdminStatus: "suspended"}
	decision := Evaluate(claims, "user-1", "calculator", "calculator:history:read")
	if !decision.Denied() || decision.Reason != ReasonSuspended {
		t.Fatalf("expected suspended denial, got %#v", decision)
	}
}

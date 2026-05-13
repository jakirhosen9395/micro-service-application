package rbac

import (
	"strings"

	"user_service/internal/domain"
)

const (
	DecisionAllow       = "allow"
	DecisionNeedsGrant  = "needs_grant"
	DecisionDenied      = "deny"
	ReasonSameUser      = "same_user"
	ReasonApprovedAdmin = "approved_admin"
	ReasonServiceRole   = "service_or_system"
	ReasonGrantRequired = "active_grant_required"
	ReasonSuspended     = "suspended_or_inactive_actor"
	ReasonInvalidTarget = "invalid_target"
)

type Decision struct {
	Result     string `json:"result"`
	Reason     string `json:"reason"`
	Scope      string `json:"scope"`
	Resource   string `json:"resource"`
	TargetUser string `json:"target_user_id"`
}

func (d Decision) Allowed() bool    { return d.Result == DecisionAllow }
func (d Decision) NeedsGrant() bool { return d.Result == DecisionNeedsGrant }
func (d Decision) Denied() bool     { return d.Result == DecisionDenied }

func Evaluate(claims domain.Claims, targetUserID, resourceType, requiredScope string) Decision {
	resourceType = strings.ToLower(strings.TrimSpace(resourceType))
	requiredScope = strings.ToLower(strings.TrimSpace(requiredScope))
	targetUserID = strings.TrimSpace(targetUserID)
	base := Decision{Result: DecisionDenied, Reason: ReasonInvalidTarget, Scope: requiredScope, Resource: resourceType, TargetUser: targetUserID}
	if targetUserID == "" || claims.Subject == "" || claims.Tenant == "" {
		return base
	}
	if IsSuspended(claims) {
		base.Reason = ReasonSuspended
		return base
	}
	if targetUserID == claims.Subject {
		base.Result = DecisionAllow
		base.Reason = ReasonSameUser
		return base
	}
	if claims.IsApprovedAdmin() && ScopeMatches("*", requiredScope, true) {
		base.Result = DecisionAllow
		base.Reason = ReasonApprovedAdmin
		return base
	}
	if claims.IsService() && ScopeMatches("*", requiredScope, true) {
		base.Result = DecisionAllow
		base.Reason = ReasonServiceRole
		return base
	}
	base.Result = DecisionNeedsGrant
	base.Reason = ReasonGrantRequired
	return base
}

func IsSuspended(claims domain.Claims) bool {
	if strings.EqualFold(claims.AdminStatus, "suspended") {
		return true
	}
	status := strings.TrimSpace(strings.ToLower(claims.Status))
	return status != "" && status != "active"
}

func ScopeMatches(actualScope, requiredScope string, wildcardAllowed bool) bool {
	actualScope = strings.TrimSpace(strings.ToLower(actualScope))
	requiredScope = strings.TrimSpace(strings.ToLower(requiredScope))
	if requiredScope == "" {
		return true
	}
	if actualScope == requiredScope {
		return true
	}
	if !wildcardAllowed {
		return false
	}
	if actualScope == "*" || actualScope == "*:*" {
		return true
	}
	if strings.HasSuffix(actualScope, ":*") {
		prefix := strings.TrimSuffix(actualScope, ":*")
		return strings.HasPrefix(requiredScope, prefix+":")
	}
	return false
}

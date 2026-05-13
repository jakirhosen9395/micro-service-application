package httpapi

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"user_service/internal/cache"
	"user_service/internal/config"
	"user_service/internal/docs"
	"user_service/internal/domain"
	"user_service/internal/health"
	"user_service/internal/logging"
	"user_service/internal/observability"
	"user_service/internal/persistence"
	"user_service/internal/platform"
	"user_service/internal/rbac"
	"user_service/internal/s3audit"
	"user_service/internal/security"
)

type ctxKey string

const (
	ctxRequestID ctxKey = "request_id"
	ctxTraceID   ctxKey = "trace_id"
	ctxCorrID    ctxKey = "correlation_id"
	ctxClaims    ctxKey = "claims"
)

type Router struct {
	cfg    config.Config
	log    *logging.Logger
	repo   persistence.Repository
	cache  *cache.Client
	audit  *s3audit.Writer
	health *health.Checker
}

func New(cfg config.Config, log *logging.Logger, repo persistence.Repository, cache *cache.Client, audit *s3audit.Writer, health *health.Checker) *Router {
	return &Router{cfg: cfg, log: log, repo: repo, cache: cache, audit: audit, health: health}
}

func (rt *Router) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	requestID := headerOr(r, "X-Request-ID", platform.RequestID())
	traceID := headerOr(r, "X-Trace-ID", platform.TraceID())
	corrID := headerOr(r, "X-Correlation-ID", platform.CorrelationID())
	ctx := context.WithValue(r.Context(), ctxRequestID, requestID)
	ctx = context.WithValue(ctx, ctxTraceID, traceID)
	ctx = context.WithValue(ctx, ctxCorrID, corrID)
	r = r.WithContext(ctx)
	w.Header().Set("X-Request-ID", requestID)
	w.Header().Set("X-Trace-ID", traceID)
	w.Header().Set("X-Correlation-ID", corrID)
	rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
	if rt.cors(rec, r) {
		return
	}
	defer func() {
		if recovered := recover(); recovered != nil {
			err := fmt.Errorf("%v", recovered)
			observability.CaptureError(r.Context(), err)
			fields := observability.TraceFields(r.Context())
			fields["request_id"] = requestID
			fields["trace_id"] = traceID
			fields["path"] = r.URL.Path
			fields["stack_trace"] = string(debug.Stack())
			rt.log.Error("http.unhandled_exception", "unhandled panic", fields, err)
			writeError(rec, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Internal server error", nil)
		}
		if !suppressSuccessLog(r.URL.Path, rec.status) {
			fields := observability.TraceFields(r.Context())
			fields["logger"] = "app.request"
			fields["request_id"] = requestID
			fields["trace_id"] = traceID
			fields["correlation_id"] = corrID
			fields["method"] = r.Method
			fields["path"] = r.URL.Path
			fields["status_code"] = rec.status
			fields["duration_ms"] = float64(time.Since(start).Microseconds()) / 1000.0
			fields["client_ip"] = platform.ClientIP(r)
			fields["user_agent"] = r.UserAgent()
			rt.log.Info("http.request.completed", "request completed", fields)
		}
	}()
	if strings.HasPrefix(r.URL.Path, "/v1/") {
		claims, err := security.ValidateBearer(r.Header.Get("Authorization"), rt.cfg)
		if err != nil {
			status, code, message := authFailure(err)
			rt.log.Warn("auth.jwt.rejected", "jwt validation failed", map[string]any{"request_id": requestID, "trace_id": traceID, "path": r.URL.Path, "error_code": code})
			writeError(rec, r, status, code, message, nil)
			return
		}
		ctx = context.WithValue(r.Context(), ctxClaims, claims)
		r = r.WithContext(ctx)
		_, err = rt.repo.EnsureProfile(r.Context(), claims, rt.defaults())
		if err != nil {
			rt.log.Error("profile.ensure.failed", "failed to ensure profile projection", map[string]any{"request_id": requestID, "trace_id": traceID, "user_id": claims.Subject}, err)
			writeError(rec, r, http.StatusInternalServerError, "PROFILE_INIT_FAILED", "Profile projection could not be initialized", nil)
			return
		}
	}
	rt.route(rec, r)
}

func (rt *Router) route(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/hello":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, r)
			return
		}
		writeJSON(w, http.StatusOK, health.PublicHello(rt.cfg))
	case r.URL.Path == "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, r)
			return
		}
		resp, code := rt.health.Check(r.Context())
		writeJSON(w, code, resp)
	case r.URL.Path == "/docs":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(docs.HTML(rt.cfg)))
	case strings.HasPrefix(r.URL.Path, "/v1/users"):
		rt.users(w, r)
	default:
		notFound(w, r)
	}
}

func (rt *Router) users(w http.ResponseWriter, r *http.Request) {
	segments := pathSegments(r.URL.Path)
	if len(segments) < 2 || segments[0] != "v1" || segments[1] != "users" {
		notFound(w, r)
		return
	}
	if len(segments) == 3 && segments[2] == "me" {
		rt.handleMe(w, r)
		return
	}
	if len(segments) == 4 && segments[2] == "me" && segments[3] == "preferences" {
		rt.handlePreferences(w, r)
		return
	}
	if len(segments) == 4 && segments[2] == "me" && segments[3] == "activity" {
		rt.handleActivity(w, r)
		return
	}
	if len(segments) == 4 && segments[2] == "me" && segments[3] == "dashboard" {
		rt.handleDashboard(w, r)
		return
	}
	if len(segments) == 4 && segments[2] == "me" && (segments[3] == "security-context" || segments[3] == "rbac" || segments[3] == "effective-permissions") {
		rt.handleSecurityContext(w, r, segments[3])
		return
	}
	if len(segments) >= 4 && segments[2] == "me" && segments[3] == "calculations" {
		rt.handleCalculations(w, r, claims(r).Subject, segments[4:])
		return
	}
	if len(segments) >= 4 && segments[2] == "me" && segments[3] == "todos" {
		rt.handleTodos(w, r, claims(r).Subject, segments[4:])
		return
	}
	if len(segments) >= 4 && segments[2] == "me" && segments[3] == "reports" {
		rt.handleReports(w, r, claims(r).Subject, segments[4:])
		return
	}
	if len(segments) >= 3 && segments[2] == "access-requests" {
		rt.handleAccessRequests(w, r, segments[3:])
		return
	}
	if len(segments) == 3 && segments[2] == "access-grants" {
		rt.handleAccessGrants(w, r)
		return
	}
	if len(segments) == 4 && segments[2] == "reports" && segments[3] == "types" {
		rt.handleReportTypes(w, r)
		return
	}
	if len(segments) >= 4 {
		target := segments[2]
		switch segments[3] {
		case "calculations":
			rt.handleCalculations(w, r, target, segments[4:])
			return
		case "todos":
			rt.handleTodos(w, r, target, segments[4:])
			return
		case "reports":
			rt.handleReports(w, r, target, segments[4:])
			return
		}
	}
	notFound(w, r)
}

func (rt *Router) handleMe(w http.ResponseWriter, r *http.Request) {
	cl := claims(r)
	switch r.Method {
	case http.MethodGet:
		key := rt.cfg.RedisKey("profile", cl.Tenant, cl.Subject)
		var cached domain.UserProfile
		if ok, _ := rt.cache.GetJSON(r.Context(), key, &cached); ok {
			writeSuccess(w, r, http.StatusOK, "profile loaded", cached)
			return
		}
		p, err := rt.repo.GetProfile(r.Context(), cl.Tenant, cl.Subject)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		_ = rt.cache.SetJSON(r.Context(), key, p)
		writeSuccess(w, r, http.StatusOK, "profile loaded", p)
	case http.MethodPatch:
		var patch map[string]any
		if !decodeJSON(w, r, &patch) {
			return
		}
		event := rt.event(r, "user.profile.updated", cl.Subject, cl.Subject, "user_profile", cl.Subject, patch)
		p, err := rt.repo.UpdateProfile(r.Context(), cl.Tenant, cl.Subject, allowedPatch(patch, "full_name", "display_name", "bio", "birthdate", "gender", "timezone", "locale", "avatar_url", "phone", "metadata"), event)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		_ = rt.cache.DeletePrefix(r.Context(), rt.cfg.RedisKey("profile", cl.Tenant, cl.Subject))
		_ = rt.cache.DeletePrefix(r.Context(), rt.cfg.RedisKey("dashboard", cl.Tenant, cl.Subject))
		rt.writeAudit(r, event, "")
		writeSuccess(w, r, http.StatusOK, "profile updated", p)
	default:
		methodNotAllowed(w, r)
	}
}

func (rt *Router) handlePreferences(w http.ResponseWriter, r *http.Request) {
	cl := claims(r)
	switch r.Method {
	case http.MethodGet:
		key := rt.cfg.RedisKey("preferences", cl.Tenant, cl.Subject)
		var cached domain.Preferences
		if ok, _ := rt.cache.GetJSON(r.Context(), key, &cached); ok {
			writeSuccess(w, r, http.StatusOK, "preferences loaded", cached)
			return
		}
		p, err := rt.repo.GetPreferences(r.Context(), cl.Tenant, cl.Subject, rt.defaults())
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		_ = rt.cache.SetJSON(r.Context(), key, p)
		writeSuccess(w, r, http.StatusOK, "preferences loaded", p)
	case http.MethodPut:
		var patch map[string]any
		if !decodeJSON(w, r, &patch) {
			return
		}
		event := rt.event(r, "user.preferences.updated", cl.Subject, cl.Subject, "user_preferences", cl.Subject, patch)
		p, err := rt.repo.PutPreferences(r.Context(), cl.Tenant, cl.Subject, allowedPatch(patch, "timezone", "locale", "theme", "notifications_enabled", "notification_settings", "dashboard_settings", "report_settings", "privacy_settings", "access_request_settings", "metadata"), event)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		_ = rt.cache.Delete(r.Context(), rt.cfg.RedisKey("preferences", cl.Tenant, cl.Subject))
		_ = rt.cache.DeletePrefix(r.Context(), rt.cfg.RedisKey("dashboard", cl.Tenant, cl.Subject))
		rt.writeAudit(r, event, "")
		writeSuccess(w, r, http.StatusOK, "preferences updated", p)
	default:
		methodNotAllowed(w, r)
	}
}

func (rt *Router) handleActivity(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, r)
		return
	}
	cl := claims(r)
	p, ok := parsePage(w, r)
	if !ok {
		return
	}
	items, err := rt.repo.ListActivity(r.Context(), cl.Tenant, cl.Subject, p)
	if err != nil {
		rt.repoError(w, r, err)
		return
	}
	writeSuccess(w, r, http.StatusOK, "activity loaded", items)
}

func (rt *Router) handleDashboard(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, r)
		return
	}
	cl := claims(r)
	key := rt.cfg.RedisKey("dashboard", cl.Tenant, cl.Subject)
	var cached domain.Dashboard
	if ok, _ := rt.cache.GetJSON(r.Context(), key, &cached); ok {
		writeSuccess(w, r, http.StatusOK, "dashboard loaded", cached)
		return
	}
	d, err := rt.repo.Dashboard(r.Context(), cl.Tenant, cl.Subject, rt.defaults())
	if err != nil {
		rt.repoError(w, r, err)
		return
	}
	_ = rt.cache.SetJSON(r.Context(), key, d)
	writeSuccess(w, r, http.StatusOK, "dashboard loaded", d)
}

func (rt *Router) handleCalculations(w http.ResponseWriter, r *http.Request, target string, rest []string) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, r)
		return
	}
	cl := claims(r)
	if !rt.authorized(w, r, target, "calculator", "calculator:history:read") {
		return
	}
	if len(rest) == 0 {
		p, ok := parsePage(w, r)
		if !ok {
			return
		}
		key := rt.cfg.RedisKey("calculations", cl.Tenant, target, strconv.Itoa(p.Limit), strconv.Itoa(p.Offset))
		var cached []domain.CalculationProjection
		if ok, _ := rt.cache.GetJSON(r.Context(), key, &cached); ok {
			writeSuccess(w, r, http.StatusOK, "calculations loaded", cached)
			return
		}
		items, err := rt.repo.ListCalculations(r.Context(), cl.Tenant, target, p)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		_ = rt.cache.SetJSON(r.Context(), key, items)
		writeSuccess(w, r, http.StatusOK, "calculations loaded", items)
		return
	}
	if len(rest) == 1 {
		item, err := rt.repo.GetCalculation(r.Context(), cl.Tenant, target, rest[0])
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		writeSuccess(w, r, http.StatusOK, "calculation loaded", item)
		return
	}
	notFound(w, r)
}

func (rt *Router) handleTodos(w http.ResponseWriter, r *http.Request, target string, rest []string) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, r)
		return
	}
	if !rt.authorized(w, r, target, "todo", "todo:history:read") {
		return
	}
	cl := claims(r)
	if len(rest) == 0 {
		p, ok := parsePage(w, r)
		if !ok {
			return
		}
		items, err := rt.repo.ListTodos(r.Context(), cl.Tenant, target, p)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		writeSuccess(w, r, http.StatusOK, "todos loaded", items)
		return
	}
	if len(rest) == 1 && rest[0] == "summary" {
		summary, err := rt.repo.TodoSummary(r.Context(), cl.Tenant, target)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		writeSuccess(w, r, http.StatusOK, "todo summary loaded", summary)
		return
	}
	if len(rest) == 1 && rest[0] == "activity" {
		p, ok := parsePage(w, r)
		if !ok {
			return
		}
		items, err := rt.repo.ListTodoActivity(r.Context(), cl.Tenant, target, p)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		writeSuccess(w, r, http.StatusOK, "todo activity loaded", items)
		return
	}
	if len(rest) == 1 {
		item, err := rt.repo.GetTodo(r.Context(), cl.Tenant, target, rest[0])
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		writeSuccess(w, r, http.StatusOK, "todo loaded", item)
		return
	}
	notFound(w, r)
}

func (rt *Router) handleAccessRequests(w http.ResponseWriter, r *http.Request, rest []string) {
	cl := claims(r)
	switch {
	case len(rest) == 0 && r.Method == http.MethodPost:
		var input struct {
			TargetUserID string `json:"target_user_id"`
			ResourceType string `json:"resource_type"`
			Scope        string `json:"scope"`
			Reason       string `json:"reason"`
			ExpiresAt    string `json:"expires_at"`
		}
		if !decodeJSON(w, r, &input) {
			return
		}
		input.ResourceType = strings.ToLower(strings.TrimSpace(input.ResourceType))
		if input.TargetUserID == "" || input.ResourceType == "" || input.Scope == "" || input.Reason == "" {
			writeError(w, r, http.StatusBadRequest, "VALIDATION_ERROR", "target_user_id, resource_type, scope, and reason are required", nil)
			return
		}
		expires := parseExpires(input.ExpiresAt, rt.cfg.AccessRequestDefaultTTLDays)
		max := time.Now().UTC().Add(time.Duration(rt.cfg.AccessRequestMaxTTLDays) * 24 * time.Hour)
		if expires.After(max) {
			writeError(w, r, http.StatusBadRequest, "ACCESS_REQUEST_TTL_EXCEEDED", "expires_at exceeds maximum TTL", nil)
			return
		}
		request := domain.AccessRequest{Tenant: cl.Tenant, RequestID: platform.NewID("ar"), RequesterUserID: cl.Subject, TargetUserID: input.TargetUserID, ResourceType: input.ResourceType, Scope: input.Scope, Reason: input.Reason, Status: domain.StatusPending, ExpiresAt: expires, Metadata: domain.EmptyObject()}
		event := rt.event(r, "access.requested", input.TargetUserID, cl.Subject, "access_request", request.RequestID, map[string]any{"request_id": request.RequestID, "requester_user_id": cl.Subject, "target_user_id": input.TargetUserID, "resource_type": input.ResourceType, "scope": input.Scope, "reason": input.Reason, "status": request.Status, "expires_at": expires.Format(time.RFC3339)})
		out, err := rt.repo.CreateAccessRequest(r.Context(), request, event)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		rt.writeAudit(r, event, input.TargetUserID)
		writeSuccess(w, r, http.StatusCreated, "access request created", out)
	case len(rest) == 0 && r.Method == http.MethodGet:
		p, ok := parsePage(w, r)
		if !ok {
			return
		}
		items, err := rt.repo.ListAccessRequests(r.Context(), cl.Tenant, cl.Subject, p)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		writeSuccess(w, r, http.StatusOK, "access requests loaded", items)
	case len(rest) == 1 && r.Method == http.MethodGet:
		item, err := rt.repo.GetAccessRequest(r.Context(), cl.Tenant, cl.Subject, rest[0])
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		writeSuccess(w, r, http.StatusOK, "access request loaded", item)
	case len(rest) == 2 && rest[1] == "cancel" && r.Method == http.MethodPost:
		current, err := rt.repo.GetAccessRequestByID(r.Context(), cl.Tenant, rest[0])
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		if current.Status != domain.StatusPending {
			writeError(w, r, http.StatusConflict, "ACCESS_REQUEST_NOT_PENDING", "Only pending access requests can be cancelled", nil)
			return
		}
		if current.RequesterUserID != cl.Subject {
			decision := rbac.Evaluate(cl, current.TargetUserID, current.ResourceType, current.Scope)
			if !decision.Allowed() {
				writeError(w, r, http.StatusForbidden, "FORBIDDEN", "Only the requester, approved admin, or service role can cancel this access request", map[string]any{"reason": decision.Reason})
				return
			}
		}
		event := rt.event(r, "access.request.cancelled", current.TargetUserID, cl.Subject, "access_request", rest[0], map[string]any{"request_id": rest[0], "requester_user_id": current.RequesterUserID, "cancelled_by": cl.Subject, "target_user_id": current.TargetUserID, "resource_type": current.ResourceType, "scope": current.Scope, "status": domain.StatusCancelled})
		item, err := rt.repo.CancelAccessRequestByID(r.Context(), cl.Tenant, rest[0], event)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		rt.writeAudit(r, event, item.TargetUserID)
		writeSuccess(w, r, http.StatusOK, "access request cancelled", item)
	default:
		if isKnownAccessRequestPath(rest) {
			methodNotAllowed(w, r)
		} else {
			notFound(w, r)
		}
	}
}

func (rt *Router) handleAccessGrants(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, r)
		return
	}
	cl := claims(r)
	p, ok := parsePage(w, r)
	if !ok {
		return
	}
	items, err := rt.repo.ListVisibleGrants(r.Context(), cl.Tenant, cl, p)
	if err != nil {
		rt.repoError(w, r, err)
		return
	}
	writeSuccess(w, r, http.StatusOK, "access grants loaded", items)
}

func (rt *Router) handleReportTypes(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, r)
		return
	}
	writeSuccess(w, r, http.StatusOK, "report types loaded", health.ReportTypes(rt.cfg.ReportAllowedFormats))
}

func (rt *Router) handleReports(w http.ResponseWriter, r *http.Request, target string, rest []string) {
	cl := claims(r)
	switch {
	case len(rest) == 0 && r.Method == http.MethodPost:
		var input struct {
			ReportType string         `json:"report_type"`
			Format     string         `json:"format"`
			DateFrom   string         `json:"date_from"`
			DateTo     string         `json:"date_to"`
			Filters    map[string]any `json:"filters"`
			Options    map[string]any `json:"options"`
		}
		if !decodeJSON(w, r, &input) {
			return
		}
		if input.ReportType == "" {
			writeError(w, r, http.StatusBadRequest, "VALIDATION_ERROR", "report_type is required", nil)
			return
		}
		format := strings.ToLower(strings.TrimSpace(input.Format))
		if format == "" {
			format = rt.cfg.ReportDefaultFormat
		}
		if !rt.cfg.AllowedReportFormat(format) {
			writeError(w, r, http.StatusBadRequest, "UNSUPPORTED_REPORT_FORMAT", "unsupported report format", nil)
			return
		}
		if target != cl.Subject && !rt.authorized(w, r, target, reportResource(input.ReportType), reportScope(input.ReportType)) {
			return
		}
		report := domain.ReportRequest{Tenant: cl.Tenant, ReportID: platform.NewID("rpt"), RequesterUserID: cl.Subject, TargetUserID: target, ReportType: input.ReportType, Format: format, DateFrom: parseDatePtr(input.DateFrom), DateTo: parseDatePtr(input.DateTo), Filters: domain.RawJSON(nonNilMap(input.Filters)), Options: domain.RawJSON(nonNilMap(input.Options)), Status: domain.StatusQueued}
		event := rt.event(r, "user.report.requested", target, cl.Subject, "report_request", report.ReportID, map[string]any{"report_id": report.ReportID, "requester_user_id": cl.Subject, "target_user_id": target, "report_type": report.ReportType, "format": report.Format, "date_from": input.DateFrom, "date_to": input.DateTo, "filters": nonNilMap(input.Filters), "options": nonNilMap(input.Options), "status": report.Status})
		out, err := rt.repo.CreateReportRequest(r.Context(), report, event)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		rt.writeAudit(r, event, target)
		writeSuccess(w, r, http.StatusCreated, "report request created", out)
	case len(rest) == 0 && r.Method == http.MethodGet:
		if target != cl.Subject && !rt.authorized(w, r, target, "report", "report:read") {
			return
		}
		requesterID := cl.Subject
		if target != cl.Subject {
			requesterID = ""
		}
		p, ok := parsePage(w, r)
		if !ok {
			return
		}
		items, err := rt.repo.ListReportRequests(r.Context(), cl.Tenant, requesterID, target, p)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		writeSuccess(w, r, http.StatusOK, "report requests loaded", items)
	case len(rest) == 1 && r.Method == http.MethodGet:
		if target != cl.Subject && !rt.authorized(w, r, target, "report", "report:read") {
			return
		}
		requesterID := cl.Subject
		if target != cl.Subject {
			requesterID = ""
		}
		item, err := rt.repo.GetReportRequest(r.Context(), cl.Tenant, requesterID, target, rest[0])
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		writeSuccess(w, r, http.StatusOK, "report request loaded", item)
	case len(rest) == 2 && (rest[1] == "metadata" || rest[1] == "progress") && r.Method == http.MethodGet:
		if target != cl.Subject && !rt.authorized(w, r, target, "report", "report:metadata:read") {
			return
		}
		requesterID := cl.Subject
		if target != cl.Subject {
			requesterID = ""
		}
		item, err := rt.repo.GetReportRequest(r.Context(), cl.Tenant, requesterID, target, rest[0])
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		if rest[1] == "metadata" {
			writeSuccess(w, r, http.StatusOK, "report metadata loaded", map[string]any{"report_id": item.ReportID, "status": item.Status, "format": item.Format, "file_name": item.FileName, "s3_object_key": item.S3ObjectKey, "download_url": item.DownloadURL, "expires_at": item.ExpiresAt})
		} else {
			writeSuccess(w, r, http.StatusOK, "report progress loaded", map[string]any{"report_id": item.ReportID, "status": item.Status, "progress": map[string]any{"stage": item.Status}})
		}
	case len(rest) == 2 && rest[1] == "cancel" && r.Method == http.MethodPost:
		if target != cl.Subject && !rt.authorized(w, r, target, "report", "report:cancel") {
			return
		}
		requesterID := cl.Subject
		if target != cl.Subject {
			requesterID = ""
		}
		current, err := rt.repo.GetReportRequest(r.Context(), cl.Tenant, requesterID, target, rest[0])
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		if strings.EqualFold(current.Status, "COMPLETED") || strings.EqualFold(current.Status, "FAILED") || strings.EqualFold(current.Status, domain.StatusCancelled) {
			writeError(w, r, http.StatusConflict, "REPORT_NOT_CANCELLABLE", "Report request cannot be cancelled in its current state", nil)
			return
		}
		event := rt.event(r, "user.report.cancelled", target, cl.Subject, "report_request", rest[0], map[string]any{"report_id": rest[0], "requester_user_id": cl.Subject, "target_user_id": target, "status": domain.StatusCancelled})
		item, err := rt.repo.CancelReportRequest(r.Context(), cl.Tenant, requesterID, target, rest[0], event)
		if err != nil {
			rt.repoError(w, r, err)
			return
		}
		rt.writeAudit(r, event, target)
		writeSuccess(w, r, http.StatusOK, "report request cancelled", item)
	default:
		if len(rest) <= 2 {
			methodNotAllowed(w, r)
		} else {
			notFound(w, r)
		}
	}
}

func (rt *Router) authorized(w http.ResponseWriter, r *http.Request, target, resourceType, requiredScope string) bool {
	cl := claims(r)
	decision := rbac.Evaluate(cl, target, resourceType, requiredScope)
	if decision.Allowed() {
		return true
	}
	if decision.Denied() {
		rt.log.Warn("authorization.denied", "access denied by RBAC/ABAC policy", map[string]any{"request_id": requestID(r), "trace_id": traceID(r), "user_id": cl.Subject, "target_user_id": target, "resource_type": resourceType, "scope": requiredScope, "reason": decision.Reason, "error_code": "FORBIDDEN"})
		writeError(w, r, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions", nil)
		return false
	}
	ok, err := rt.repo.HasActiveGrant(r.Context(), cl.Tenant, cl.Subject, target, resourceType, requiredScope, time.Now().UTC())
	if err != nil {
		rt.log.Error("authorization.grant_check.failed", "failed to check access grant", map[string]any{"request_id": requestID(r), "trace_id": traceID(r), "user_id": cl.Subject, "target_user_id": target}, err)
		writeError(w, r, http.StatusInternalServerError, "AUTHORIZATION_CHECK_FAILED", "Authorization check failed", nil)
		return false
	}
	if !ok {
		rt.log.Warn("authorization.denied", "cross-user access denied", map[string]any{"request_id": requestID(r), "trace_id": traceID(r), "user_id": cl.Subject, "target_user_id": target, "resource_type": resourceType, "scope": requiredScope, "reason": "active_grant_missing", "error_code": "FORBIDDEN"})
		writeError(w, r, http.StatusForbidden, "FORBIDDEN", "Insufficient permissions", nil)
		return false
	}
	return true
}

func (rt *Router) handleSecurityContext(w http.ResponseWriter, r *http.Request, view string) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, r)
		return
	}
	cl := claims(r)
	data := map[string]any{
		"subject":           cl.Subject,
		"tenant":            cl.Tenant,
		"role":              cl.Role,
		"admin_status":      cl.AdminStatus,
		"status":            cl.Status,
		"approved_admin":    cl.IsApprovedAdmin(),
		"service_or_system": cl.IsService(),
		"suspended":         rbac.IsSuspended(cl),
		"same_user_access":  true,
		"cross_user_access": "approved_admin, service/system, or active grant",
		"wildcard_scope":    "admin/service/system only",
		"effective_scopes":  []string{"profile:read", "profile:update", "preferences:read", "preferences:update", "dashboard:read", "activity:read", "calculator:history:read", "calculator:record:read", "todo:read", "todo:summary:read", "todo:activity:read", "todo:history:read", "report:type:read", "report:create", "report:read", "report:cancel", "report:metadata:read", "report:progress:read", "access_request:create", "access_request:read", "access_request:cancel", "access_grant:read", "rbac:read"},
	}
	writeSuccess(w, r, http.StatusOK, view+" loaded", data)
}

func authFailure(err error) (int, string, string) {
	if errors.Is(err, security.ErrInvalidTenant) || errors.Is(err, security.ErrSuspendedUser) {
		return http.StatusForbidden, "FORBIDDEN", "Insufficient permissions"
	}
	return http.StatusUnauthorized, "UNAUTHORIZED", "Authentication required"
}

func (rt *Router) repoError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, persistence.ErrNotFound), errors.Is(err, sql.ErrNoRows):
		writeError(w, r, http.StatusNotFound, "NOT_FOUND", "Resource not found", nil)
	default:
		rt.log.Error("repository.error", "repository operation failed", map[string]any{"request_id": requestID(r), "trace_id": traceID(r), "path": r.URL.Path}, err)
		writeError(w, r, http.StatusInternalServerError, "PERSISTENCE_ERROR", "Persistence operation failed", nil)
	}
}

func (rt *Router) event(r *http.Request, eventType, userID, actorID, aggregateType, aggregateID string, payload any) domain.EventEnvelope {
	cl := claims(r)
	return domain.EventEnvelope{EventID: platform.EventID(), EventType: eventType, EventVersion: "1.0", Service: rt.cfg.ServiceName, Environment: rt.cfg.Environment, Tenant: cl.Tenant, Timestamp: time.Now().UTC().Format(time.RFC3339Nano), RequestID: requestID(r), TraceID: traceID(r), CorrelationID: corrID(r), UserID: userID, ActorID: actorID, AggregateType: aggregateType, AggregateID: aggregateID, Payload: domain.RawJSON(payload)}
}

func (rt *Router) writeAudit(r *http.Request, event domain.EventEnvelope, targetUserID string) {
	if rt.audit == nil {
		return
	}
	meta := domain.RequestMeta{RequestID: requestID(r), TraceID: traceID(r), CorrelationID: corrID(r), ClientIP: platform.ClientIP(r), UserAgent: r.UserAgent()}
	if _, err := rt.audit.Write(r.Context(), event, meta, targetUserID); err != nil {
		rt.log.Error("s3.audit.write_failed", "failed to write S3 audit snapshot", map[string]any{"request_id": requestID(r), "trace_id": traceID(r), "event_id": event.EventID, "event_type": event.EventType, "dependency": "s3"}, err)
	}
}

func (rt *Router) defaults() persistence.ProfileDefaults {
	return persistence.ProfileDefaults{Timezone: rt.cfg.DefaultTimezone, Locale: rt.cfg.DefaultLocale, Theme: rt.cfg.DefaultTheme}
}

func (rt *Router) cors(w http.ResponseWriter, r *http.Request) bool {
	origin := strings.TrimRight(strings.TrimSpace(r.Header.Get("Origin")), "/")
	if origin != "" && rt.allowedOrigin(origin) {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Vary", "Origin")
		w.Header().Set("Access-Control-Allow-Methods", strings.Join(rt.cfg.CORSAllowedMethods, ", "))
		w.Header().Set("Access-Control-Allow-Headers", strings.Join(rt.cfg.CORSAllowedHeaders, ", "))
		w.Header().Set("Access-Control-Expose-Headers", "X-Request-ID, X-Trace-ID, X-Correlation-ID")
		if rt.cfg.CORSAllowCredentials {
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		}
		w.Header().Set("Access-Control-Max-Age", strconv.Itoa(rt.cfg.CORSMaxAgeSeconds))
	}
	if r.Method != http.MethodOptions {
		return false
	}
	if origin != "" && !rt.allowedOrigin(origin) {
		writeError(w, r, http.StatusForbidden, "CORS_ORIGIN_DENIED", "CORS origin is not allowed", nil)
		return true
	}
	w.WriteHeader(http.StatusNoContent)
	return true
}

func (rt *Router) allowedOrigin(origin string) bool {
	for _, allowed := range rt.cfg.CORSAllowedOrigins {
		allowed = strings.TrimRight(strings.TrimSpace(allowed), "/")
		if allowed == "*" || strings.EqualFold(allowed, origin) {
			return true
		}
	}
	return false
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) { s.status = code; s.ResponseWriter.WriteHeader(code) }

func decodeJSON(w http.ResponseWriter, r *http.Request, dest any) bool {
	defer r.Body.Close()
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dest); err != nil {
		writeError(w, r, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid JSON request body", map[string]any{"error": err.Error()})
		return false
	}
	return true
}

func notFound(w http.ResponseWriter, r *http.Request) {
	writeError(w, r, http.StatusNotFound, "NOT_FOUND", "Resource not found", nil)
}

func methodNotAllowed(w http.ResponseWriter, r *http.Request) {
	writeError(w, r, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "Method not allowed", nil)
}
func requestID(r *http.Request) string { return ctxString(r, ctxRequestID) }
func traceID(r *http.Request) string   { return ctxString(r, ctxTraceID) }
func corrID(r *http.Request) string    { return ctxString(r, ctxCorrID) }
func ctxString(r *http.Request, key ctxKey) string {
	if v, ok := r.Context().Value(key).(string); ok {
		return v
	}
	return ""
}
func claims(r *http.Request) domain.Claims {
	if v, ok := r.Context().Value(ctxClaims).(domain.Claims); ok {
		return v
	}
	return domain.Claims{}
}
func headerOr(r *http.Request, key, fallback string) string {
	if v := strings.TrimSpace(r.Header.Get(key)); v != "" {
		return v
	}
	return fallback
}
func suppressSuccessLog(path string, status int) bool {
	return status < 400 && (path == "/hello" || path == "/health" || path == "/docs")
}
func pathSegments(path string) []string {
	trimmed := strings.Trim(path, "/")
	if trimmed == "" {
		return nil
	}
	return strings.Split(trimmed, "/")
}
func parsePage(w http.ResponseWriter, r *http.Request) (persistence.Page, bool) {
	q := r.URL.Query()
	limit := 50
	offset := 0
	if raw := strings.TrimSpace(q.Get("limit")); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > 100 {
			writeError(w, r, http.StatusBadRequest, "INVALID_QUERY_PARAMETER", "limit must be an integer between 1 and 100", map[string]any{"parameter": "limit"})
			return persistence.Page{}, false
		}
		limit = n
	}
	if raw := strings.TrimSpace(q.Get("offset")); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 0 {
			writeError(w, r, http.StatusBadRequest, "INVALID_QUERY_PARAMETER", "offset must be an integer greater than or equal to 0", map[string]any{"parameter": "offset"})
			return persistence.Page{}, false
		}
		offset = n
	}
	return persistence.NormalizePage(limit, offset), true
}

func allowedPatch(patch map[string]any, allowed ...string) map[string]any {
	set := map[string]bool{}
	for _, k := range allowed {
		set[k] = true
	}
	out := map[string]any{}
	for k, v := range patch {
		if set[k] {
			out[k] = v
		}
	}
	return out
}

func parseExpires(value string, defaultDays int) time.Time {
	if value != "" {
		if t, err := time.Parse(time.RFC3339, value); err == nil {
			return t.UTC()
		}
	}
	return time.Now().UTC().Add(time.Duration(defaultDays) * 24 * time.Hour)
}

func parseDatePtr(value string) *time.Time {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	if t, err := time.Parse("2006-01-02", value); err == nil {
		utc := t.UTC()
		return &utc
	}
	if t, err := time.Parse(time.RFC3339, value); err == nil {
		utc := t.UTC()
		return &utc
	}
	return nil
}

func nonNilMap(m map[string]any) map[string]any {
	if m == nil {
		return map[string]any{}
	}
	return m
}
func reportResource(reportType string) string {
	if strings.Contains(reportType, "calculator") {
		return "calculator"
	}
	if strings.Contains(reportType, "todo") {
		return "todo"
	}
	return "report"
}
func reportScope(reportType string) string {
	if strings.Contains(reportType, "calculator") {
		return "calculator:history:read"
	}
	if strings.Contains(reportType, "todo") {
		return "todo:history:read"
	}
	return "report:read"
}
func isKnownAccessRequestPath(rest []string) bool { return len(rest) <= 2 }

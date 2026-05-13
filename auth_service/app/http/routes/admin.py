from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from app.domain.schemas import AdminDecisionRequest
from app.http.responses import success_envelope
from app.http.routes.auth import err_example, ok_example, USER_EXAMPLE, UNAUTHORIZED_RESPONSE, FORBIDDEN_RESPONSE, VALIDATION_RESPONSE
from app.security.dependencies import approved_admin_claims

router = APIRouter(prefix="/v1/admin", tags=["admin"])


@router.get(
    "/requests",
    summary="List admin registration requests",
    description="Requires an approved admin token. Lists pending, approved, rejected, and suspended admin registration records. Returns 403 if the caller is not an approved admin.",
    response_description="List of admin registration requests.",
    responses={
        200: {"description": "Admin requests loaded", "content": {"application/json": {"example": ok_example("admin requests loaded", [{**USER_EXAMPLE, "role": "admin", "admin_status": "pending"}])}}},
        401: UNAUTHORIZED_RESPONSE,
        403: FORBIDDEN_RESPONSE,
    },
)
async def list_admin_requests(claims: Annotated[dict, Depends(approved_admin_claims)], request: Request):
    data = await request.app.state.auth_service.list_admin_requests()
    return success_envelope("admin requests loaded", data, request)


@router.post(
    "/requests/{user_id}/decision",
    summary="Approve or reject admin registration request",
    description="Requires an approved admin token. Decision must be `approve` or `reject`. Approval changes the user's admin_status to `approved`; rejection changes it to `rejected`. The service emits admin decision events for downstream consumers through Kafka.",
    response_description="Admin request decision result.",
    responses={
        200: {"description": "Admin request decision recorded", "content": {"application/json": {"example": ok_example("admin request decision recorded", {"user": {**USER_EXAMPLE, "role": "admin", "admin_status": "approved"}, "decision": "approve"})}}},
        401: UNAUTHORIZED_RESPONSE,
        403: FORBIDDEN_RESPONSE,
        404: {"description": "Pending admin request not found", "content": {"application/json": {"example": err_example("/v1/admin/requests/usr_example/decision", "Pending admin request not found", "ADMIN_REQUEST_NOT_FOUND")}}},
        422: VALIDATION_RESPONSE,
    },
)
async def decide_admin_request(user_id: str, payload: AdminDecisionRequest, claims: Annotated[dict, Depends(approved_admin_claims)], request: Request):
    data = await request.app.state.auth_service.decide_admin_request(user_id, payload, claims, request)
    return success_envelope("admin request decision recorded", data, request)

from __future__ import annotations

from fastapi import APIRouter, Request

from app.http.docs import swagger_ui_html
from app.http.responses import PrettyJSONResponse

router = APIRouter()


@router.get("/hello", response_class=PrettyJSONResponse, tags=["system"])
async def hello(request: Request):
    settings = request.app.state.settings
    return {
        "status": "ok",
        "message": f"{settings.service_name} is running",
        "service": {"name": settings.service_name, "env": settings.environment, "version": settings.version},
    }


@router.get("/health", response_class=PrettyJSONResponse, tags=["system"])
async def health(request: Request):
    status_code, payload = await request.app.state.health_service.health()
    return PrettyJSONResponse(payload, status_code=status_code)


@router.get("/docs", include_in_schema=False)
async def docs(request: Request):
    return swagger_ui_html(request.app)

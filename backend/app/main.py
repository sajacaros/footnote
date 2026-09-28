from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, Response

from . import setup_code, storage
from .config import get_settings
from .db import SessionLocal
from .gzip_request import GzipRequestMiddleware
from .routers import admin, auth, photos, sessions

_WEB = Path(__file__).parent / "web"
_ADMIN_PAGE = (_WEB / "admin.html").read_text(encoding="utf-8")
_RESET_PAGE = (_WEB / "reset.html").read_text(encoding="utf-8")
_POLICY_JS = (_WEB / "password-policy.js").read_text(encoding="utf-8")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await storage.ensure_bucket()
    async with SessionLocal() as db:
        if not await auth.admin_exists(db):
            setup_code.issue()
    yield


app = FastAPI(title="Footnote Walk API", version="0.1.0", lifespan=lifespan)
app.add_middleware(GzipRequestMiddleware, max_bytes=get_settings().max_request_bytes)
app.include_router(auth.router)
app.include_router(admin.router)
app.include_router(sessions.router)
app.include_router(photos.router)


@app.get("/", include_in_schema=False)
async def admin_page() -> HTMLResponse:
    """관리자가 없으면 셋업, 있으면 로그인 → 가입 승인 화면(한 페이지에서 분기)."""
    return HTMLResponse(_ADMIN_PAGE, headers={"Cache-Control": "no-store"})


@app.get("/reset", include_in_schema=False)
async def reset_page() -> HTMLResponse:
    """비밀번호 재설정. 토큰은 주소의 # 뒤에 있어 서버 로그와 Referer에 남지 않는다."""
    return HTMLResponse(
        _RESET_PAGE,
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )


@app.get("/password-policy.js", include_in_schema=False)
async def password_policy_js() -> Response:
    return Response(
        _POLICY_JS,
        media_type="text/javascript; charset=utf-8",
        headers={"Cache-Control": "no-cache"},
    )


@app.get("/healthz", tags=["ops"])
async def healthz() -> dict[str, str]:
    return {"status": "ok"}

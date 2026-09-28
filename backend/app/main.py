import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, Response

from . import purge, setup_code, storage
from .config import get_settings
from .db import SessionLocal
from .gzip_request import GzipRequestMiddleware
from .routers import admin, auth, photos, sessions

_WEB = Path(__file__).parent / "web"
_APP_PAGE = (_WEB / "app.html").read_text(encoding="utf-8")
_ICON = (_WEB / "icon.svg").read_text(encoding="utf-8")
_RESET_PAGE = (_WEB / "reset.html").read_text(encoding="utf-8")
_POLICY_JS = (_WEB / "password-policy.js").read_text(encoding="utf-8")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await storage.ensure_bucket()
    async with SessionLocal() as db:
        if not await auth.admin_exists(db):
            setup_code.issue()
    purger = asyncio.create_task(purge.run_forever())
    yield
    purger.cancel()


app = FastAPI(title="Footnote Walk API", version="0.1.0", lifespan=lifespan)
app.add_middleware(GzipRequestMiddleware, max_bytes=get_settings().max_request_bytes)
app.include_router(auth.router)
app.include_router(admin.router)
app.include_router(sessions.router)
app.include_router(photos.router)


@app.get("/", include_in_schema=False)
async def app_page() -> HTMLResponse:
    """앱에서 올린 산책을 보는 웹 페이지. 관리자에게는 가입 관리 메뉴가 더 보인다.

    관리자가 없으면 첫 관리자를 만드는 셋업 화면이 먼저 나온다(한 페이지에서 분기).
    """
    return HTMLResponse(_APP_PAGE, headers={"Cache-Control": "no-store"})


@app.get("/icon.svg", include_in_schema=False)
async def icon() -> Response:
    return Response(
        _ICON,
        media_type="image/svg+xml",
        headers={"Cache-Control": "public, max-age=86400"},
    )


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

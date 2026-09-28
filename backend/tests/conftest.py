"""실제 PostgreSQL(TimescaleDB)과 SeaweedFS를 대상으로 하는 통합 테스트.

먼저 `docker compose up -d db storage`로 서비스를 띄워 둔다.
테스트 전용 DB(footnote_test)를 쓴다. 버킷은 앱 키의 권한 범위라 개발용과 같지만,
오브젝트 키가 테스트마다 새로 만든 사용자 id 아래에 생겨서 겹치지 않는다.
"""

import os
import subprocess
import sys
import uuid

import asyncpg
import pytest

ADMIN_DSN = os.environ.get(
    "TEST_ADMIN_DSN", "postgresql://footnote:footnote@localhost:15433/footnote"
)
TEST_DB = "footnote_test"

os.environ["DATABASE_URL"] = (
    f"postgresql+asyncpg://footnote:footnote@localhost:15433/{TEST_DB}"
)
os.environ["SETUP_CODE"] = "TEST-SETUP-CODE"
os.environ.setdefault("S3_ENDPOINT", "http://localhost:8333")
os.environ.setdefault("S3_PUBLIC_ENDPOINT", "http://localhost:8333")

from httpx import ASGITransport, AsyncClient  # noqa: E402

from app.main import app, lifespan  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
async def database():
    admin = await asyncpg.connect(ADMIN_DSN)
    await admin.execute(f"DROP DATABASE IF EXISTS {TEST_DB} WITH (FORCE)")
    await admin.execute(f"CREATE DATABASE {TEST_DB}")
    await admin.close()
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        check=True,
        env=os.environ.copy(),
    )
    yield


@pytest.fixture(scope="session")
async def client(database):
    async with lifespan(app):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            yield client


@pytest.fixture(scope="session")
async def admin(client) -> dict:
    """셋업 API로 첫 관리자를 만든다. 세션 전체에서 한 번만 만들어진다."""
    response = await client.post(
        "/v1/setup",
        json={
            "setup_code": "test-setup-code",
            "email": "admin@example.com",
            "password": "Guard#9051river",
            "display_name": "관리자",
        },
    )
    assert response.status_code == 201, response.text
    body = response.json()
    body["headers"] = {"Authorization": f"Bearer {body['access_token']}"}
    return body


async def apply(client: AsyncClient) -> dict:
    """가입 신청만 한다(승인 대기 상태)."""
    email = f"walker-{uuid.uuid4().hex[:8]}@example.com"
    response = await client.post(
        "/v1/auth/signup",
        json={"email": email, "password": "Walk-2026!trail", "display_name": "산책러"},
    )
    assert response.status_code == 202, response.text
    return {"email": email, "id": response.json()["user"]["id"]}


async def login(client: AsyncClient, email: str, password: str = "Walk-2026!trail"):
    return await client.post("/v1/auth/login", json={"email": email, "password": password})


async def signup(client: AsyncClient, admin: dict) -> dict:
    """가입 신청 → 관리자 승인 → 로그인까지 마친 사용자."""
    account = await apply(client)
    approved = await client.post(
        f"/v1/admin/users/{account['id']}/approve", headers=admin["headers"]
    )
    assert approved.status_code == 200, approved.text
    response = await login(client, account["email"])
    assert response.status_code == 200, response.text
    body = response.json()
    body["email"] = account["email"]
    body["headers"] = {"Authorization": f"Bearer {body['access_token']}"}
    return body

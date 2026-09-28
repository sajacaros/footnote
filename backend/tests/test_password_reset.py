from datetime import UTC, datetime, timedelta

import asyncpg

from .conftest import TEST_DB, login, signup


async def _link(client, admin, user_id) -> str:
    response = await client.post(
        f"/v1/admin/users/{user_id}/reset-link", headers=admin["headers"]
    )
    assert response.status_code == 200, response.text
    return response.json()["token"]


async def test_reset_link_flow(client, admin):
    account = await signup(client, admin)
    token = await _link(client, admin, account["user"]["id"])

    check = await client.post("/v1/auth/reset-password/check", json={"token": token})
    assert check.status_code == 200
    info = check.json()
    assert info["display_name"] == "산책러"
    assert "*" in info["email_hint"] and info["email_hint"].endswith("@example.com")

    reset = await client.post(
        "/v1/auth/reset-password", json={"token": token, "new_password": "Reset@5173lane"}
    )
    assert reset.status_code == 204

    # 한 번 쓴 링크는 다시 쓸 수 없다.
    again = await client.post(
        "/v1/auth/reset-password", json={"token": token, "new_password": "Other&6391hill"}
    )
    assert again.status_code == 400
    assert again.json()["detail"]["code"] == "invalid_reset_link"

    assert (await login(client, account["email"])).status_code == 401
    assert (await login(client, account["email"], "Reset@5173lane")).status_code == 200
    # 재설정 전에 받은 refresh 토큰은 폐기됐다.
    old_refresh = await client.post(
        "/v1/auth/refresh", json={"refresh_token": account["refresh_token"]}
    )
    assert old_refresh.status_code == 401


async def test_new_link_invalidates_previous(client, admin):
    account = await signup(client, admin)
    first = await _link(client, admin, account["user"]["id"])
    second = await _link(client, admin, account["user"]["id"])

    stale = await client.post("/v1/auth/reset-password/check", json={"token": first})
    assert stale.status_code == 400
    fresh = await client.post("/v1/auth/reset-password/check", json={"token": second})
    assert fresh.status_code == 200


async def test_expired_link_is_rejected(client, admin):
    account = await signup(client, admin)
    token = await _link(client, admin, account["user"]["id"])
    conn = await asyncpg.connect(f"postgresql://footnote:footnote@localhost:15433/{TEST_DB}")
    try:
        await conn.execute(
            "UPDATE password_reset_tokens SET expires_at = $1 WHERE user_id = $2::uuid",
            datetime.now(UTC) - timedelta(minutes=1),
            account["user"]["id"],
        )
    finally:
        await conn.close()
    response = await client.post(
        "/v1/auth/reset-password", json={"token": token, "new_password": "Reset@5173lane"}
    )
    assert response.status_code == 400


async def test_only_admin_can_create_links(client, admin):
    account = await signup(client, admin)
    other = await signup(client, admin)
    response = await client.post(
        f"/v1/admin/users/{other['user']['id']}/reset-link", headers=account["headers"]
    )
    assert response.status_code == 403

    bogus = await client.post(
        "/v1/auth/reset-password/check", json={"token": "x" * 43}
    )
    assert bogus.status_code == 400


async def test_reset_page_is_served(client):
    page = await client.get("/reset")
    assert page.status_code == 200
    assert page.headers["referrer-policy"] == "no-referrer"

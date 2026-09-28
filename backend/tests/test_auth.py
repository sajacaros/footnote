from .conftest import login, signup


async def test_signup_login_me(client, admin):
    account = await signup(client, admin)

    me = await client.get("/v1/me", headers=account["headers"])
    assert me.status_code == 200
    assert me.json()["email"] == account["email"]

    login = await client.post(
        "/v1/auth/login",
        json={"email": account["email"].upper(), "password": "Walk-2026!trail"},
    )
    assert login.status_code == 200


async def test_duplicate_signup_and_wrong_password(client, admin):
    account = await signup(client, admin)
    again = await client.post(
        "/v1/auth/signup",
        json={"email": account["email"], "password": "Other&6391hill", "display_name": "x"},
    )
    assert again.status_code == 409

    wrong = await client.post(
        "/v1/auth/login", json={"email": account["email"], "password": "wrong-pass"}
    )
    assert wrong.status_code == 401


async def test_requires_token(client, admin):
    assert (await client.get("/v1/me")).status_code == 401
    bad = await client.get("/v1/me", headers={"Authorization": "Bearer nope"})
    assert bad.status_code == 401


async def test_refresh_rotates_and_rejects_reuse(client, admin):
    account = await signup(client, admin)
    first = await client.post(
        "/v1/auth/refresh", json={"refresh_token": account["refresh_token"]}
    )
    assert first.status_code == 200
    reused = await client.post(
        "/v1/auth/refresh", json={"refresh_token": account["refresh_token"]}
    )
    assert reused.status_code == 401

    # 액세스 토큰을 refresh 자리에 넣어도 거부한다.
    wrong_type = await client.post(
        "/v1/auth/refresh", json={"refresh_token": account["access_token"]}
    )
    assert wrong_type.status_code == 401

    await client.post("/v1/auth/logout", json={"refresh_token": first.json()["refresh_token"]})
    after_logout = await client.post(
        "/v1/auth/refresh", json={"refresh_token": first.json()["refresh_token"]}
    )
    assert after_logout.status_code == 401


async def test_setup_is_one_time(client, admin):
    status = await client.get("/v1/setup/status")
    assert status.json() == {"needs_setup": False}
    again = await client.post(
        "/v1/setup",
        json={
            "setup_code": "TEST-SETUP-CODE",
            "email": "second-admin@example.com",
            "password": "Guard#9051river",
            "display_name": "x",
        },
    )
    assert again.status_code == 409
    assert admin["user"]["is_admin"] is True


async def test_pending_user_cannot_log_in_until_approved(client, admin):
    from .conftest import apply, login

    account = await apply(client)
    pending = await login(client, account["email"])
    assert pending.status_code == 403
    assert pending.json()["detail"]["code"] == "pending_approval"

    # 비밀번호가 틀리면 승인 상태를 알려 주지 않는다.
    wrong = await login(client, account["email"], "wrong-password")
    assert wrong.status_code == 401

    listed = await client.get("/v1/admin/users?status=pending", headers=admin["headers"])
    assert account["id"] in [user["id"] for user in listed.json()]

    await client.post(f"/v1/admin/users/{account['id']}/approve", headers=admin["headers"])
    assert (await login(client, account["email"])).status_code == 200


async def test_rejecting_user_revokes_access(client, admin):
    account = await signup(client, admin)
    user_id = account["user"]["id"]

    rejected = await client.post(f"/v1/admin/users/{user_id}/reject", headers=admin["headers"])
    assert rejected.json()["status"] == "rejected"

    # 이미 받은 액세스 토큰과 refresh 토큰 모두 막힌다.
    me = await client.get("/v1/me", headers=account["headers"])
    assert me.status_code == 403
    assert me.json()["detail"]["code"] == "account_rejected"
    refreshed = await client.post(
        "/v1/auth/refresh", json={"refresh_token": account["refresh_token"]}
    )
    assert refreshed.status_code == 401


async def test_admin_api_requires_admin(client, admin):
    account = await signup(client, admin)
    response = await client.get("/v1/admin/users", headers=account["headers"])
    assert response.status_code == 403
    self_reject = await client.post(
        f"/v1/admin/users/{admin['user']['id']}/reject", headers=admin["headers"]
    )
    assert self_reject.status_code == 400


async def test_web_page_is_served(client):
    page = await client.get("/")
    assert page.status_code == 200
    assert "풋노트" in page.text
    icon = await client.get("/icon.svg")
    assert icon.headers["content-type"].startswith("image/svg+xml")


async def test_change_password_logs_out_other_devices(client, admin):
    import asyncio

    account = await signup(client, admin)
    other_device = await login(client, account["email"])
    other = other_device.json()

    wrong = await client.post(
        "/v1/me/password",
        json={"current_password": "not-it", "new_password": "Fresh#8274path"},
        headers=account["headers"],
    )
    assert wrong.status_code == 400

    # 새 토큰의 iat가 변경 시각(초 단위 내림) 이후가 되도록 초 경계를 넘긴다.
    await asyncio.sleep(1.1)
    changed = await client.post(
        "/v1/me/password",
        json={"current_password": "Walk-2026!trail", "new_password": "Fresh#8274path"},
        headers=account["headers"],
    )
    assert changed.status_code == 200, changed.text
    fresh = {"Authorization": f"Bearer {changed.json()['access_token']}"}
    assert (await client.get("/v1/me", headers=fresh)).status_code == 200

    # 다른 기기: 액세스 토큰과 refresh 토큰 모두 막힌다.
    stale = {"Authorization": f"Bearer {other['access_token']}"}
    assert (await client.get("/v1/me", headers=stale)).status_code == 401
    refreshed = await client.post(
        "/v1/auth/refresh", json={"refresh_token": other["refresh_token"]}
    )
    assert refreshed.status_code == 401

    assert (await login(client, account["email"])).status_code == 401
    assert (await login(client, account["email"], "Fresh#8274path")).status_code == 200

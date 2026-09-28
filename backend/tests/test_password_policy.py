import pytest

from app.password_policy import violations

from .conftest import apply


@pytest.mark.parametrize(
    ("password", "expected"),
    [
        ("Walk-2026!trail", []),
        ("Ab1!", ["length"]),
        ("walk-trail!!x", ["digit"]),
        ("Walk20261trail", ["special"]),
        ("2026-0913!!85", ["letter"]),
        ("Walk 2026!trail", ["no_space"]),
        ("Waaalk-2026!tr", ["no_repeat"]),
        ("Walk-1234!trail", ["no_sequence"]),
        ("Walk-9876!trail", ["no_sequence"]),
        ("Qwer-2026!trail", ["no_sequence"]),
        ("Password-2026!", ["no_common"]),
    ],
)
def test_rules(password, expected):
    assert violations(password) == expected


def test_email_local_part_is_rejected():
    assert "no_email" in violations("walker99-Trail!", "walker99@example.com")
    # 너무 짧은 아이디는 우연히 겹칠 수 있어 검사하지 않는다.
    assert "no_email" not in violations("Walk-2026!trail", "ab@example.com")


async def test_weak_password_lists_every_problem(client):
    response = await client.post(
        "/v1/auth/signup",
        json={"email": "weakling@example.com", "password": "abc", "display_name": "x"},
    )
    assert response.status_code == 400
    detail = response.json()["detail"]
    assert detail["code"] == "weak_password"
    codes = [problem["code"] for problem in detail["problems"]]
    assert codes == ["length", "digit", "special"]
    assert "10자 이상" in detail["message"]


async def test_change_password_enforces_policy(client, admin):
    from .conftest import signup

    account = await signup(client, admin)
    response = await client.post(
        "/v1/me/password",
        json={"current_password": "Walk-2026!trail", "new_password": "short1!"},
        headers=account["headers"],
    )
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "weak_password"


async def test_apply_still_works_with_strong_password(client, admin):
    account = await apply(client)
    assert account["email"].endswith("@example.com")

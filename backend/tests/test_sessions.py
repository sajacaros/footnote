import gzip
import json
import uuid
from datetime import UTC, datetime, timedelta

from .conftest import signup

START = datetime(2026, 9, 28, 8, 0, tzinfo=UTC)


def _points(start_seq: int, count: int) -> list[dict]:
    return [
        {
            "seq": seq,
            "recorded_at": (START + timedelta(seconds=2 * seq)).isoformat(),
            # 서울시청 근처에서 북쪽으로 약 1.1m씩 이동
            "lat": 37.5665 + seq * 0.00001,
            "lng": 126.9780,
            "accuracy": 5.0,
        }
        for seq in range(start_seq, start_seq + count)
    ]


async def _create_session(client, headers) -> str:
    session_id = str(uuid.uuid4())
    response = await client.post(
        "/v1/sessions",
        json={"id": session_id, "title": "아침 산책", "started_at": START.isoformat()},
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return session_id


async def test_bulk_points_are_idempotent_and_finish_computes_route(client, admin):
    account = await signup(client, admin)
    headers = account["headers"]
    session_id = await _create_session(client, headers)

    # 같은 id로 다시 만들어도 같은 기록이 돌아온다.
    again = await client.post(
        "/v1/sessions",
        json={"id": session_id, "title": "다른 제목", "started_at": START.isoformat()},
        headers=headers,
    )
    assert again.json()["title"] == "아침 산책"

    first = await client.post(
        f"/v1/sessions/{session_id}/points:batch",
        json={"points": _points(0, 150)},
        headers=headers,
    )
    assert first.json() == {"received": 150, "last_acked_seq": 149}

    # 재전송(겹치는 구간 포함)해도 중복되지 않는다. gzip 본문도 받는다.
    body = gzip.compress(json.dumps({"points": _points(100, 100)}).encode())
    second = await client.post(
        f"/v1/sessions/{session_id}/points:batch",
        content=body,
        headers={**headers, "Content-Type": "application/json", "Content-Encoding": "gzip"},
    )
    assert second.status_code == 200, second.text
    assert second.json()["last_acked_seq"] == 199

    finish = await client.post(
        f"/v1/sessions/{session_id}/finish",
        json={"ended_at": (START + timedelta(minutes=7)).isoformat(), "last_seq": 199},
        headers=headers,
    )
    assert finish.status_code == 200, finish.text
    session = finish.json()
    assert session["point_count"] == 200
    # 199구간 × 약 1.11m
    assert 215 < session["distance_m"] < 230

    detail = await client.get(f"/v1/sessions/{session_id}", headers=headers)
    assert len(detail.json()["points"]) == 200


async def test_finish_reports_gap(client, admin):
    account = await signup(client, admin)
    headers = account["headers"]
    session_id = await _create_session(client, headers)

    await client.post(
        f"/v1/sessions/{session_id}/points:batch",
        json={"points": _points(0, 10) + _points(20, 10)},
        headers=headers,
    )
    finish = await client.post(
        f"/v1/sessions/{session_id}/finish",
        json={"ended_at": START.isoformat(), "last_seq": 29},
        headers=headers,
    )
    assert finish.status_code == 409
    assert finish.json()["detail"]["last_acked_seq"] == 9


async def test_steps_can_be_set_and_updated(client, admin):
    account = await signup(client, admin)
    headers = account["headers"]
    session_id = await _create_session(client, headers)

    created = await client.get(f"/v1/sessions/{session_id}", headers=headers)
    assert created.json()["steps"] is None

    # 만보기 앱이 늦게 기록하면 앱이 더 큰 값으로 다시 보낸다.
    for steps in (1200, 1350):
        response = await client.patch(
            f"/v1/sessions/{session_id}", json={"steps": steps}, headers=headers
        )
        assert response.status_code == 200, response.text
        assert response.json()["steps"] == steps

    negative = await client.patch(
        f"/v1/sessions/{session_id}", json={"steps": -1}, headers=headers
    )
    assert negative.status_code == 422


async def test_naive_datetime_is_rejected(client, admin):
    account = await signup(client, admin)
    response = await client.post(
        "/v1/sessions",
        json={"id": str(uuid.uuid4()), "title": "x", "started_at": "2026-09-28T08:00:00"},
        headers=account["headers"],
    )
    assert response.status_code == 422


async def test_other_users_cannot_see_session(client, admin):
    owner = await signup(client, admin)
    other = await signup(client, admin)
    session_id = await _create_session(client, owner["headers"])

    assert (await client.get(f"/v1/sessions/{session_id}", headers=other["headers"])).status_code == 404
    listed = await client.get("/v1/sessions", headers=other["headers"])
    assert listed.json() == []

    hijack = await client.post(
        "/v1/sessions",
        json={"id": session_id, "title": "x", "started_at": START.isoformat()},
        headers=other["headers"],
    )
    assert hijack.status_code == 409


async def test_deleting_user_removes_points(client, admin):
    """사용자를 지우면 세션과 함께 포인트도 지워진다(FK CASCADE)."""
    import asyncpg

    from .conftest import TEST_DB

    account = await signup(client, admin)
    session_id = await _create_session(client, account["headers"])
    await client.post(
        f"/v1/sessions/{session_id}/points:batch",
        json={"points": _points(0, 5)},
        headers=account["headers"],
    )
    conn = await asyncpg.connect(f"postgresql://footnote:footnote@localhost:15433/{TEST_DB}")
    try:
        await conn.execute("DELETE FROM users WHERE email = $1", account["email"])
        left = await conn.fetchval(
            "SELECT count(*) FROM track_points WHERE session_id = $1", uuid.UUID(session_id)
        )
    finally:
        await conn.close()
    assert left == 0


async def test_overview_gives_simplified_route(client, admin):
    account = await signup(client, admin)
    headers = account["headers"]
    session_id = await _create_session(client, headers)
    await client.post(
        f"/v1/sessions/{session_id}/points:batch",
        json={"points": _points(0, 50)},
        headers=headers,
    )
    await client.post(
        f"/v1/sessions/{session_id}/finish",
        json={"ended_at": (START + timedelta(minutes=2)).isoformat(), "last_seq": 49},
        headers=headers,
    )
    # 경로가 없는(포인트가 모자란) 세션도 목록에 나온다.
    await _create_session(client, headers)

    response = await client.get("/v1/sessions/overview", headers=headers)
    assert response.status_code == 200, response.text
    items = response.json()
    assert len(items) == 2
    walked = next(item for item in items if item["id"] == session_id)
    # 직선이라 양 끝점만 남는다.
    assert walked["route"] == [[126.978, 37.5665], [126.978, 37.5665 + 49 * 0.00001]]
    assert walked["photo_count"] == 0
    assert walked["thumb_url"] is None
    other = next(item for item in items if item["id"] != session_id)
    assert other["route"] == []

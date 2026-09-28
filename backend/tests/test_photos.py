"""SeaweedFS presigned PUT/GET을 실제로 왕복하는 테스트."""

import hashlib
import uuid
from datetime import UTC, datetime

import httpx

from .conftest import signup

START = datetime(2026, 9, 28, 8, 0, tzinfo=UTC)
DISPLAY = b"\xff\xd8\xff\xe0" + b"display-bytes" * 1000
THUMB = b"\xff\xd8\xff\xe0" + b"thumb" * 100


async def _session(client, headers) -> str:
    session_id = str(uuid.uuid4())
    await client.post(
        "/v1/sessions",
        json={"id": session_id, "title": "사진 산책", "started_at": START.isoformat()},
        headers=headers,
    )
    return session_id


def _photo_body(session_id: str) -> dict:
    return {
        "id": str(uuid.uuid4()),
        "session_id": session_id,
        "taken_at": START.isoformat(),
        "lat": 37.5665,
        "lng": 126.978,
        "sha256": hashlib.sha256(DISPLAY).hexdigest(),
        "size_bytes": len(DISPLAY),
        "content_type": "image/jpeg",
    }


async def test_presigned_upload_complete_and_download(client, admin):
    account = await signup(client, admin)
    headers = account["headers"]
    session_id = await _session(client, headers)
    body = _photo_body(session_id)

    created = await client.post("/v1/photos", json=body, headers=headers)
    assert created.status_code == 201, created.text
    uploads = created.json()["uploads"]
    assert set(uploads) == {"display", "thumb"}

    # 업로드 전에 complete하면 거부한다.
    early = await client.post(f"/v1/photos/{body['id']}/complete", headers=headers)
    assert early.status_code == 409

    async with httpx.AsyncClient() as storage:
        for variant, data in (("display", DISPLAY), ("thumb", THUMB)):
            target = uploads[variant]
            put = await storage.put(target["url"], content=data, headers=target["headers"])
            assert put.status_code == 200, put.text

        done = await client.post(f"/v1/photos/{body['id']}/complete", headers=headers)
        assert done.status_code == 200, done.text
        photo = done.json()
        assert photo["status"] == "ready"

        downloaded = await storage.get(photo["urls"]["display"])
        assert downloaded.status_code == 200
        assert downloaded.content == DISPLAY

        # 서명 없이 직접 접근하면 막힌다.
        unsigned = await storage.get(photo["urls"]["display"].split("?")[0])
        assert unsigned.status_code == 403

    detail = await client.get(f"/v1/sessions/{session_id}", headers=headers)
    assert detail.json()["photos"][0]["status"] == "ready"


async def test_content_type_mismatch_is_rejected_by_storage(client, admin):
    account = await signup(client, admin)
    headers = account["headers"]
    body = _photo_body(await _session(client, headers))
    created = await client.post("/v1/photos", json=body, headers=headers)
    target = created.json()["uploads"]["display"]

    async with httpx.AsyncClient() as storage:
        put = await storage.put(
            target["url"], content=DISPLAY, headers={"Content-Type": "image/png"}
        )
    assert put.status_code == 403


async def test_size_mismatch_blocks_complete(client, admin):
    account = await signup(client, admin)
    headers = account["headers"]
    body = _photo_body(await _session(client, headers))
    uploads = (await client.post("/v1/photos", json=body, headers=headers)).json()["uploads"]

    async with httpx.AsyncClient() as storage:
        await storage.put(uploads["display"]["url"], content=DISPLAY[:100], headers=uploads["display"]["headers"])
        await storage.put(uploads["thumb"]["url"], content=THUMB, headers=uploads["thumb"]["headers"])

    done = await client.post(f"/v1/photos/{body['id']}/complete", headers=headers)
    assert done.status_code == 409


async def test_photo_requires_own_session(client, admin):
    owner = await signup(client, admin)
    other = await signup(client, admin)
    body = _photo_body(await _session(client, owner["headers"]))
    response = await client.post("/v1/photos", json=body, headers=other["headers"])
    assert response.status_code == 404


async def test_recreate_pending_photo_updates_size(client, admin):
    """재시도하며 다시 압축해 크기가 바뀌어도 complete가 통과해야 한다."""
    account = await signup(client, admin)
    headers = account["headers"]
    body = _photo_body(await _session(client, headers))
    await client.post("/v1/photos", json=body, headers=headers)

    smaller = DISPLAY[:5000]
    retry = {**body, "size_bytes": len(smaller), "sha256": hashlib.sha256(smaller).hexdigest()}
    uploads = (await client.post("/v1/photos", json=retry, headers=headers)).json()["uploads"]
    async with httpx.AsyncClient() as storage:
        await storage.put(uploads["display"]["url"], content=smaller, headers=uploads["display"]["headers"])
        await storage.put(uploads["thumb"]["url"], content=THUMB, headers=uploads["thumb"]["headers"])

    done = await client.post(f"/v1/photos/{body['id']}/complete", headers=headers)
    assert done.status_code == 200, done.text
    assert done.json()["size_bytes"] == len(smaller)


async def test_deleted_session_hides_photos_then_purges_after_retention(client, admin):
    from datetime import timedelta

    from sqlalchemy import select

    from app import storage as app_storage
    from app.db import SessionLocal
    from app.models import TrackPoint, WalkPhoto, WalkSession
    from app.purge import purge_deleted

    account = await signup(client, admin)
    headers = account["headers"]
    session_id = await _session(client, headers)
    await client.post(
        f"/v1/sessions/{session_id}/points:batch",
        json={
            "points": [
                {"seq": 0, "recorded_at": START.isoformat(), "lat": 37.5665, "lng": 126.978}
            ]
        },
        headers=headers,
    )
    body = _photo_body(session_id)
    created = (await client.post("/v1/photos", json=body, headers=headers)).json()
    async with httpx.AsyncClient() as storage:
        for variant, data in (("display", DISPLAY), ("thumb", THUMB)):
            target = created["uploads"][variant]
            await storage.put(target["url"], content=data, headers=target["headers"])
    await client.post(f"/v1/photos/{body['id']}/complete", headers=headers)

    deleted = await client.delete(f"/v1/sessions/{session_id}", headers=headers)
    assert deleted.status_code == 204
    # 지운 세션의 사진은 id를 알아도 받을 수 없다.
    photo = await client.get(f"/v1/photos/{body['id']}", headers=headers)
    assert photo.status_code == 404

    key = app_storage.photo_key(
        uuid.UUID(account["user"]["id"]), uuid.UUID(body["id"]), "display", "image/jpeg"
    )
    photo_id = uuid.UUID(body["id"])
    sid = uuid.UUID(session_id)

    async with SessionLocal() as db:
        # 보관 기간 안에는 복구할 수 있게 남겨 둔다.
        await purge_deleted(db, now=datetime.now(UTC) + timedelta(days=29))
        assert await db.get(WalkSession, sid) is not None
        assert await app_storage.object_size(key) == len(DISPLAY)

        await purge_deleted(db, now=datetime.now(UTC) + timedelta(days=31))
        db.expire_all()
        assert await db.get(WalkSession, sid) is None
        assert await db.get(WalkPhoto, photo_id) is None
        points = await db.scalars(
            select(TrackPoint).where(TrackPoint.session_id == sid)
        )
        assert list(points) == []
    assert await app_storage.object_size(key) is None

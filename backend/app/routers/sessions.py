import json
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import func, select, text, update
from sqlalchemy.dialects.postgresql import insert

from .. import storage
from ..deps import CurrentUser, DbSession
from ..models import TrackPoint, WalkPhoto, WalkSession
from ..schemas import (
    PointBatch,
    PointBatchResult,
    PointOut,
    SessionCreate,
    SessionDetail,
    SessionFinish,
    SessionOut,
    SessionOverview,
    SessionUpdate,
)
from .photos import photo_keys, photo_out

router = APIRouter(prefix="/v1/sessions", tags=["sessions"])

# 0부터 빠짐없이 이어진 마지막 seq. 0이 없거나 포인트가 없으면 -1.
_LAST_CONTIGUOUS_SEQ = text(
    """
    SELECT CASE WHEN min(seq) <> 0 THEN -1 ELSE (
        SELECT s.seq FROM (
            SELECT seq, lead(seq) OVER (ORDER BY seq) AS next_seq
            FROM track_points WHERE session_id = :session_id
        ) s
        WHERE s.next_seq IS NULL OR s.next_seq <> s.seq + 1
        ORDER BY s.seq LIMIT 1
    ) END
    FROM track_points WHERE session_id = :session_id
    """
)


async def _owned_session(db: DbSession, user: CurrentUser, session_id: uuid.UUID) -> WalkSession:
    session = await db.get(WalkSession, session_id)
    if session is None or session.user_id != user.id or session.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "산책 기록을 찾을 수 없습니다.")
    return session


async def _last_acked_seq(db: DbSession, session_id: uuid.UUID) -> int:
    value = await db.scalar(_LAST_CONTIGUOUS_SEQ, {"session_id": session_id})
    return -1 if value is None else value


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_session(body: SessionCreate, db: DbSession, user: CurrentUser) -> SessionOut:
    """같은 id로 다시 보내면 기존 기록을 그대로 돌려준다(멱등)."""
    await db.execute(
        insert(WalkSession)
        .values(
            id=body.id,
            user_id=user.id,
            title=body.title,
            note=body.note,
            started_at=body.started_at,
            point_count=0,
        )
        .on_conflict_do_nothing(index_elements=["id"])
    )
    await db.commit()
    session = await db.get(WalkSession, body.id, populate_existing=True)
    if session is None or session.user_id != user.id:
        raise HTTPException(status.HTTP_409_CONFLICT, "사용할 수 없는 id입니다.")
    return SessionOut.model_validate(session)


@router.get("")
async def list_sessions(db: DbSession, user: CurrentUser) -> list[SessionOut]:
    rows = await db.scalars(
        select(WalkSession)
        .where(WalkSession.user_id == user.id, WalkSession.deleted_at.is_(None))
        .order_by(WalkSession.started_at.desc())
    )
    return [SessionOut.model_validate(row) for row in rows]


@router.get("/overview")
async def list_overview(db: DbSession, user: CurrentUser) -> list[SessionOverview]:
    """목록 화면용 요약. 카드에 경로 모양을 그릴 만큼만 줄인 좌표와 대표 사진 썸네일."""
    rows = (
        await db.execute(
            select(
                WalkSession,
                # 약 5m 이하의 굴곡은 버린다. 카드 크기에서는 차이가 보이지 않는다.
                func.ST_AsGeoJSON(func.ST_Simplify(WalkSession.route, 0.00005)),
            )
            .where(WalkSession.user_id == user.id, WalkSession.deleted_at.is_(None))
            .order_by(WalkSession.started_at.desc())
        )
    ).all()
    session_ids = [session.id for session, _ in rows]
    photos: dict[uuid.UUID, list[WalkPhoto]] = {}
    if session_ids:
        for photo in await db.scalars(
            select(WalkPhoto)
            .where(
                WalkPhoto.session_id.in_(session_ids),
                WalkPhoto.deleted_at.is_(None),
                WalkPhoto.status == "ready",
            )
            .order_by(WalkPhoto.taken_at)
        ):
            photos.setdefault(photo.session_id, []).append(photo)

    result = []
    for session, geojson in rows:
        session_photos = photos.get(session.id, [])
        featured = next(
            (p for p in session_photos if p.id == session.featured_photo_id),
            session_photos[0] if session_photos else None,
        )
        thumb_url = None
        if featured is not None:
            thumb_url = await storage.presign_get(photo_keys(featured)["thumb"])
        result.append(
            SessionOverview(
                **SessionOut.model_validate(session).model_dump(),
                route=json.loads(geojson)["coordinates"] if geojson else [],
                photo_count=len(session_photos),
                thumb_url=thumb_url,
            )
        )
    return result


@router.get("/{session_id}")
async def get_session(session_id: uuid.UUID, db: DbSession, user: CurrentUser) -> SessionDetail:
    session = await _owned_session(db, user, session_id)
    points = await db.scalars(
        select(TrackPoint).where(TrackPoint.session_id == session_id).order_by(TrackPoint.seq)
    )
    photos = await db.scalars(
        select(WalkPhoto)
        .where(WalkPhoto.session_id == session_id, WalkPhoto.deleted_at.is_(None))
        .order_by(WalkPhoto.taken_at)
    )
    return SessionDetail(
        **SessionOut.model_validate(session).model_dump(),
        points=[PointOut.model_validate(point) for point in points],
        photos=[await photo_out(photo) for photo in photos],
    )


@router.patch("/{session_id}")
async def update_session(
    session_id: uuid.UUID, body: SessionUpdate, db: DbSession, user: CurrentUser
) -> SessionOut:
    session = await _owned_session(db, user, session_id)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(session, field, value)
    await db.commit()
    await db.refresh(session)
    return SessionOut.model_validate(session)


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(session_id: uuid.UUID, db: DbSession, user: CurrentUser) -> None:
    """보관 기간(기본 30일) 동안은 숨겨만 두고, 그 뒤 purge가 파일까지 지운다."""
    session = await _owned_session(db, user, session_id)
    now = datetime.now(UTC)
    session.deleted_at = now
    # 사진도 함께 숨긴다. 그러지 않으면 사진 id로 계속 받을 수 있다.
    await db.execute(
        update(WalkPhoto)
        .where(WalkPhoto.session_id == session_id, WalkPhoto.deleted_at.is_(None))
        .values(deleted_at=now)
    )
    await db.commit()


@router.post("/{session_id}/points:batch")
async def add_points(
    session_id: uuid.UUID, body: PointBatch, db: DbSession, user: CurrentUser
) -> PointBatchResult:
    """(session_id, seq, recorded_at)가 같은 포인트는 무시하므로 재전송해도 중복되지 않는다."""
    await _owned_session(db, user, session_id)
    await db.execute(
        insert(TrackPoint)
        .values([{"session_id": session_id, **point.model_dump()} for point in body.points])
        .on_conflict_do_nothing()
    )
    await db.commit()
    return PointBatchResult(
        received=len(body.points),
        last_acked_seq=await _last_acked_seq(db, session_id),
    )


@router.post("/{session_id}/finish")
async def finish_session(
    session_id: uuid.UUID, body: SessionFinish, db: DbSession, user: CurrentUser
) -> SessionOut:
    session = await _owned_session(db, user, session_id)
    acked = await _last_acked_seq(db, session_id)
    if acked != body.last_seq:
        # 빠진 구간이 있다. 앱은 last_acked_seq 다음부터 다시 보내면 된다.
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {"message": "포인트가 모두 도착하지 않았습니다.", "last_acked_seq": acked},
        )

    if body.last_seq >= 1:
        await db.execute(
            text(
                """
                UPDATE walk_sessions SET route = r.line,
                    distance_m = ST_Length(r.line::geography)
                FROM (SELECT ST_MakeLine(
                        ST_SetSRID(ST_MakePoint(lng, lat), 4326) ORDER BY seq) AS line
                      FROM track_points WHERE session_id = :session_id) r
                WHERE id = :session_id
                """
            ),
            {"session_id": session_id},
        )
    else:
        session.distance_m = 0.0
    session.ended_at = body.ended_at
    session.point_count = body.last_seq + 1
    await db.commit()
    await db.refresh(session)
    return SessionOut.model_validate(session)

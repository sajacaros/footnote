"""삭제한 기록을 보관 기간이 지나면 실제로 지운다.

앱에서 지운 산책은 서버에서 deleted_at만 찍혀 보관 기간 동안 복구할 수 있다.
그 뒤에는 세션·GPS 포인트·사진 행과 스토리지의 사진 파일을 모두 지운다.
"""

import asyncio
import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import storage
from .config import get_settings
from .db import SessionLocal
from .models import WalkPhoto, WalkSession

logger = logging.getLogger("uvicorn.error")

_INTERVAL = timedelta(hours=6)


def _photo_keys(photo: WalkPhoto) -> list[str]:
    return [
        storage.photo_key(photo.user_id, photo.id, variant, photo.content_type)
        for variant in storage.VARIANTS
    ]


async def purge_deleted(db: AsyncSession, now: datetime | None = None) -> dict[str, int]:
    """보관 기간이 지난 세션과 사진을 지우고, 지운 개수를 돌려준다."""
    cutoff = (now or datetime.now(UTC)) - timedelta(days=get_settings().deleted_retention_days)

    session_ids = list(
        await db.scalars(
            select(WalkSession.id).where(
                WalkSession.deleted_at.is_not(None), WalkSession.deleted_at < cutoff
            )
        )
    )
    # 지운 세션의 사진 전부와, 세션은 살아 있고 사진만 지운 것.
    photos = list(
        await db.scalars(
            select(WalkPhoto).where(
                WalkPhoto.session_id.in_(session_ids)
                | (WalkPhoto.deleted_at.is_not(None) & (WalkPhoto.deleted_at < cutoff))
            )
        )
    )

    # 파일을 먼저 지운다. 중간에 실패해도 행이 남아 있어 다음 번에 다시 지운다.
    keys = [key for photo in photos for key in _photo_keys(photo)]
    for start in range(0, len(keys), 1000):
        await storage.delete_objects(keys[start : start + 1000])

    if photos:
        await db.execute(delete(WalkPhoto).where(WalkPhoto.id.in_([p.id for p in photos])))
    if session_ids:
        # track_points는 FK CASCADE로 함께 지워진다.
        await db.execute(delete(WalkSession).where(WalkSession.id.in_(session_ids)))
    await db.commit()
    return {"sessions": len(session_ids), "photos": len(photos)}


async def run_forever() -> None:
    """서버가 떠 있는 동안 주기적으로 돈다. 인스턴스가 하나라 겹치지 않는다."""
    while True:
        try:
            async with SessionLocal() as db:
                result = await purge_deleted(db)
            if result["sessions"] or result["photos"]:
                logger.info("purged deleted records: %s", result)
        except Exception:
            logger.exception("purge failed")
        await asyncio.sleep(_INTERVAL.total_seconds())

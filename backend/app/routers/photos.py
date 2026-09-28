import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, status
from sqlalchemy.dialects.postgresql import insert

from .. import storage
from ..deps import CurrentUser, DbSession
from ..models import WalkPhoto, WalkSession
from ..schemas import PhotoCreate, PhotoCreateResult, PhotoOut, UploadTarget

router = APIRouter(prefix="/v1/photos", tags=["photos"])


def _keys(photo: WalkPhoto) -> dict[str, str]:
    return {
        variant: storage.photo_key(photo.user_id, photo.id, variant, photo.content_type)
        for variant in storage.VARIANTS
    }


async def photo_out(photo: WalkPhoto) -> PhotoOut:
    out = PhotoOut.model_validate(photo)
    if photo.status == "ready":
        out.urls = {
            variant: await storage.presign_get(key) for variant, key in _keys(photo).items()
        }
    return out


async def _owned_photo(db: DbSession, user: CurrentUser, photo_id: uuid.UUID) -> WalkPhoto:
    photo = await db.get(WalkPhoto, photo_id)
    if photo is None or photo.user_id != user.id or photo.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "사진을 찾을 수 없습니다.")
    return photo


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_photo(body: PhotoCreate, db: DbSession, user: CurrentUser) -> PhotoCreateResult:
    """메타데이터를 만들고 display/thumb 업로드용 presigned PUT URL을 준다.

    같은 id로 다시 부르면 URL만 새로 발급한다(업로드 재시도용).
    """
    session = await db.get(WalkSession, body.session_id)
    if session is None or session.user_id != user.id or session.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "산책 기록을 찾을 수 없습니다.")

    # 업로드 전(pending)에 다시 부르면 파일 정보를 새 값으로 바꾼다.
    # 앱이 재시도하면서 사진을 다시 압축하면 크기와 해시가 달라질 수 있기 때문이다.
    stmt = insert(WalkPhoto).values(user_id=user.id, status="pending", **body.model_dump())
    await db.execute(
        stmt.on_conflict_do_update(
            index_elements=["id"],
            set_={
                "sha256": stmt.excluded.sha256,
                "size_bytes": stmt.excluded.size_bytes,
                "content_type": stmt.excluded.content_type,
            },
            where=(WalkPhoto.status == "pending") & (WalkPhoto.user_id == user.id),
        )
    )
    await db.commit()
    photo = await db.get(WalkPhoto, body.id, populate_existing=True)
    if photo is None or photo.user_id != user.id:
        raise HTTPException(status.HTTP_409_CONFLICT, "사용할 수 없는 id입니다.")

    uploads: dict[str, UploadTarget] = {}
    if photo.status != "ready":
        for variant, key in _keys(photo).items():
            uploads[variant] = UploadTarget(
                url=await storage.presign_put(key, photo.content_type),
                headers={"Content-Type": photo.content_type},
            )
    return PhotoCreateResult(photo=await photo_out(photo), uploads=uploads)


@router.post("/{photo_id}/complete")
async def complete_photo(photo_id: uuid.UUID, db: DbSession, user: CurrentUser) -> PhotoOut:
    """앱이 업로드를 마쳤다고 알리면 스토리지에 실제로 있는지 확인하고 ready로 바꾼다."""
    photo = await _owned_photo(db, user, photo_id)
    if photo.status != "ready":
        keys = _keys(photo)
        missing = [
            variant for variant, key in keys.items() if await storage.object_size(key) is None
        ]
        if missing:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                {"message": "업로드되지 않은 파일이 있습니다.", "missing": missing},
            )
        display_size = await storage.object_size(keys["display"])
        if display_size != photo.size_bytes:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                {"message": "업로드된 파일 크기가 다릅니다.", "size_bytes": display_size},
            )
        photo.status = "ready"
        photo.completed_at = datetime.now(UTC)
        await db.commit()
        await db.refresh(photo)
    return await photo_out(photo)


@router.get("/{photo_id}")
async def get_photo(photo_id: uuid.UUID, db: DbSession, user: CurrentUser) -> PhotoOut:
    return await photo_out(await _owned_photo(db, user, photo_id))


@router.delete("/{photo_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_photo(photo_id: uuid.UUID, db: DbSession, user: CurrentUser) -> None:
    photo = await _owned_photo(db, user, photo_id)
    photo.deleted_at = datetime.now(UTC)
    await db.commit()
    await storage.delete_objects(list(_keys(photo).values()))

import uuid
from datetime import UTC, datetime
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select, update

from .. import password_reset
from ..deps import AdminUser, DbSession
from ..models import RefreshToken, User
from ..schemas import AdminUserOut, ResetLink

router = APIRouter(prefix="/v1/admin", tags=["admin"])


@router.get("/users")
async def list_users(
    db: DbSession,
    admin: AdminUser,
    status_filter: Annotated[
        Literal["pending", "active", "rejected"] | None, Query(alias="status")
    ] = None,
) -> list[AdminUserOut]:
    query = select(User).order_by(User.created_at.desc())
    if status_filter is not None:
        query = query.where(User.status == status_filter)
    return [AdminUserOut.model_validate(user) for user in await db.scalars(query)]


async def _target(db: DbSession, admin: AdminUser, user_id: uuid.UUID) -> User:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "사용자를 찾을 수 없습니다.")
    if user.id == admin.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "자기 계정은 바꿀 수 없습니다.")
    return user


@router.post("/users/{user_id}/approve")
async def approve(user_id: uuid.UUID, db: DbSession, admin: AdminUser) -> AdminUserOut:
    user = await _target(db, admin, user_id)
    user.status = "active"
    user.approved_at = datetime.now(UTC)
    user.approved_by = admin.id
    await db.commit()
    await db.refresh(user)
    return AdminUserOut.model_validate(user)


@router.post("/users/{user_id}/reject")
async def reject(user_id: uuid.UUID, db: DbSession, admin: AdminUser) -> AdminUserOut:
    """거절하면 이미 발급된 refresh 토큰도 폐기한다. 액세스 토큰은 요청마다 상태를 확인해 막는다."""
    user = await _target(db, admin, user_id)
    if user.is_admin:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "관리자 계정은 거절할 수 없습니다.")
    now = datetime.now(UTC)
    user.status = "rejected"
    user.approved_at = None
    user.approved_by = None
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now)
    )
    await db.commit()
    await db.refresh(user)
    return AdminUserOut.model_validate(user)


@router.post("/users/{user_id}/reset-link")
async def create_reset_link(user_id: uuid.UUID, db: DbSession, admin: AdminUser) -> ResetLink:
    """관리자가 사용자에게 직접 전달할 재설정 링크의 토큰을 만든다. 이전 링크는 무효가 된다."""
    user = await _target(db, admin, user_id)
    if user.status != "active":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "사용 중인 계정만 재설정할 수 있습니다.")
    token, expires_at = await password_reset.issue(db, user, admin.id)
    return ResetLink(token=token, expires_at=expires_at)

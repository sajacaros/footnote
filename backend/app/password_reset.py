"""관리자가 만들어 전달하는 비밀번호 재설정 링크.

링크는 30분 동안 한 번만 쓸 수 있고, 새로 만들면 이전 링크는 무효가 된다.
"""

import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from .models import PasswordResetToken, User

VALID_FOR = timedelta(minutes=30)


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


async def issue(db: AsyncSession, user: User, admin_id: uuid.UUID) -> tuple[str, datetime]:
    now = datetime.now(UTC)
    await db.execute(
        update(PasswordResetToken)
        .where(PasswordResetToken.user_id == user.id, PasswordResetToken.used_at.is_(None))
        .values(used_at=now)
    )
    token = secrets.token_urlsafe(32)
    expires_at = now + VALID_FOR
    db.add(
        PasswordResetToken(
            user_id=user.id,
            token_hash=_hash(token),
            expires_at=expires_at,
            created_by=admin_id,
        )
    )
    await db.commit()
    return token, expires_at


async def find_valid(db: AsyncSession, token: str) -> tuple[PasswordResetToken, User]:
    invalid = HTTPException(
        status.HTTP_400_BAD_REQUEST,
        {"code": "invalid_reset_link", "message": "만료됐거나 이미 사용한 링크입니다. 관리자에게 새 링크를 요청해 주세요."},
    )
    row = await db.scalar(
        select(PasswordResetToken).where(PasswordResetToken.token_hash == _hash(token))
    )
    if row is None or row.used_at is not None or row.expires_at <= datetime.now(UTC):
        raise invalid
    user = await db.get(User, row.user_id)
    if user is None or user.status != "active":
        raise invalid
    return row, user


def email_hint(email: str) -> str:
    local, _, domain = email.partition("@")
    visible = local[:2] if len(local) > 2 else local[:1]
    return f"{visible}{'*' * max(len(local) - len(visible), 1)}@{domain}"

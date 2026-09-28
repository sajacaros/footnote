import uuid
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .models import User
from .security import decode_token

_bearer = HTTPBearer(auto_error=False)

DbSession = Annotated[AsyncSession, Depends(get_db)]


async def get_current_user(
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="인증이 필요합니다.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None:
        raise unauthorized
    try:
        payload = decode_token(credentials.credentials, "access")
        user_id = uuid.UUID(payload["sub"])
    except (jwt.InvalidTokenError, ValueError):
        raise unauthorized from None

    user = await db.get(User, user_id)
    if user is None:
        raise unauthorized
    # 비밀번호를 바꾸기 전에 발급된 토큰이면 거부한다. iat는 초 단위라 내림해서 비교한다.
    changed = user.password_changed_at
    if changed is not None and payload.get("iat", 0) < int(changed.timestamp()):
        raise unauthorized
    # 토큰을 받은 뒤 거절·보류된 계정도 막는다.
    if user.status != "active":
        raise inactive_error(user)
    return user


def inactive_error(user: User) -> HTTPException:
    """앱이 code로 화면을 나눌 수 있게 사유를 구분해 준다."""
    if user.status == "pending":
        detail = {"code": "pending_approval", "message": "관리자 승인을 기다리고 있습니다."}
    else:
        detail = {"code": "account_rejected", "message": "가입이 승인되지 않은 계정입니다."}
    return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


CurrentUser = Annotated[User, Depends(get_current_user)]


async def get_admin_user(user: CurrentUser) -> User:
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="관리자만 쓸 수 있습니다.")
    return user


AdminUser = Annotated[User, Depends(get_admin_user)]

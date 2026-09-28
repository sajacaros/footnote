import uuid
from datetime import UTC, datetime

import jwt
from fastapi import APIRouter, HTTPException, status
from sqlalchemy import exists, select, text, update

from .. import password_policy, password_reset, setup_code
from ..config import get_settings
from ..deps import CurrentUser, DbSession, inactive_error
from ..models import RefreshToken, User
from ..schemas import (
    ChangePasswordRequest,
    LoginRequest,
    RefreshRequest,
    ResetPasswordRequest,
    ResetTokenInfo,
    ResetTokenRequest,
    SetupRequest,
    SetupStatus,
    SignupRequest,
    SignupResult,
    TokenResponse,
    UserOut,
)
from ..security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)

router = APIRouter(prefix="/v1", tags=["auth"])

# 셋업 요청이 동시에 두 번 들어와도 관리자가 하나만 생기게 하는 advisory lock 키.
_SETUP_LOCK_KEY = 0x464F4F54  # "FOOT"


async def _issue_tokens(db: DbSession, user: User) -> TokenResponse:
    refresh, jti, expires_at = create_refresh_token(user.id)
    db.add(RefreshToken(jti=jti, user_id=user.id, expires_at=expires_at))
    await db.commit()
    return TokenResponse(
        access_token=create_access_token(user.id),
        refresh_token=refresh,
        expires_in=get_settings().access_token_minutes * 60,
        user=UserOut.model_validate(user),
    )


async def admin_exists(db: DbSession) -> bool:
    return bool(await db.scalar(select(exists().where(User.is_admin.is_(True)))))


async def _email_taken(db: DbSession, email: str) -> bool:
    return bool(await db.scalar(select(exists().where(User.email == email))))


@router.get("/setup/status")
async def setup_status(db: DbSession) -> SetupStatus:
    return SetupStatus(needs_setup=not await admin_exists(db))


@router.post("/setup", status_code=status.HTTP_201_CREATED)
async def setup(body: SetupRequest, db: DbSession) -> TokenResponse:
    """관리자가 없을 때 한 번만 쓸 수 있다. 만든 계정이 첫 관리자가 된다."""
    await db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": _SETUP_LOCK_KEY})
    if await admin_exists(db):
        raise HTTPException(status.HTTP_409_CONFLICT, "이미 셋업이 끝났습니다.")
    if not setup_code.matches(body.setup_code):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "셋업 코드가 올바르지 않습니다.")

    email = body.email.lower()
    password_policy.enforce(body.password, email)
    if await _email_taken(db, email):
        raise HTTPException(status.HTTP_409_CONFLICT, "이미 가입된 이메일입니다.")
    now = datetime.now(UTC)
    user = User(
        email=email,
        password_hash=hash_password(body.password),
        display_name=body.display_name.strip(),
        status="active",
        is_admin=True,
        approved_at=now,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)
    tokens = await _issue_tokens(db, user)
    setup_code.clear()
    return tokens


@router.post("/auth/signup", status_code=status.HTTP_202_ACCEPTED)
async def signup(body: SignupRequest, db: DbSession) -> SignupResult:
    """가입 신청만 받는다. 관리자가 승인해야 로그인할 수 있으므로 토큰은 주지 않는다."""
    email = body.email.lower()
    password_policy.enforce(body.password, email)
    if await _email_taken(db, email):
        raise HTTPException(status.HTTP_409_CONFLICT, "이미 가입된 이메일입니다.")
    user = User(
        email=email,
        password_hash=hash_password(body.password),
        display_name=body.display_name.strip(),
        status="pending",
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return SignupResult(
        user=UserOut.model_validate(user),
        message="가입 신청이 접수됐습니다. 관리자가 승인하면 로그인할 수 있습니다.",
    )


@router.post("/auth/login")
async def login(body: LoginRequest, db: DbSession) -> TokenResponse:
    user = await db.scalar(select(User).where(User.email == body.email.lower()))
    if user is None or not verify_password(user.password_hash, body.password):
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, "이메일 또는 비밀번호가 올바르지 않습니다."
        )
    # 비밀번호가 맞을 때만 승인 상태를 알려 준다. 가입 여부가 새지 않게 하기 위해서다.
    if user.status != "active":
        raise inactive_error(user)
    return await _issue_tokens(db, user)


@router.post("/auth/refresh")
async def refresh(body: RefreshRequest, db: DbSession) -> TokenResponse:
    """refresh 토큰은 한 번만 쓸 수 있다. 쓰면 폐기하고 새 토큰 쌍을 준다."""
    invalid = HTTPException(status.HTTP_401_UNAUTHORIZED, "다시 로그인해 주세요.")
    try:
        payload = decode_token(body.refresh_token, "refresh")
        jti = uuid.UUID(payload["jti"])
    except (jwt.InvalidTokenError, KeyError, ValueError):
        raise invalid from None

    now = datetime.now(UTC)
    # 폐기되지 않은 토큰만 원자적으로 폐기해서, 같은 토큰을 동시에 두 번 써도 한 번만 성공한다.
    user_id = await db.scalar(
        update(RefreshToken)
        .where(
            RefreshToken.jti == jti,
            RefreshToken.revoked_at.is_(None),
            RefreshToken.expires_at > now,
        )
        .values(revoked_at=now)
        .returning(RefreshToken.user_id)
    )
    if user_id is None:
        raise invalid
    user = await db.get(User, user_id)
    if user is None:
        raise invalid
    if user.status != "active":
        await db.commit()
        raise inactive_error(user)
    return await _issue_tokens(db, user)


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshRequest, db: DbSession) -> None:
    try:
        payload = decode_token(body.refresh_token, "refresh")
        jti = uuid.UUID(payload["jti"])
    except (jwt.InvalidTokenError, KeyError, ValueError):
        return
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.jti == jti, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )
    await db.commit()


@router.post("/auth/reset-password/check")
async def check_reset_link(body: ResetTokenRequest, db: DbSession) -> ResetTokenInfo:
    """재설정 페이지가 처음 열릴 때 링크가 유효한지, 누구의 계정인지 보여 주려고 부른다."""
    row, user = await password_reset.find_valid(db, body.token)
    return ResetTokenInfo(
        display_name=user.display_name,
        email_hint=password_reset.email_hint(user.email),
        expires_at=row.expires_at,
    )


@router.post("/auth/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_password(body: ResetPasswordRequest, db: DbSession) -> None:
    """링크로 비밀번호를 바꾼다. 링크를 쓰고, 모든 기기에서 로그아웃시킨다."""
    row, user = await password_reset.find_valid(db, body.token)
    password_policy.enforce(body.new_password, user.email)
    now = datetime.now(UTC)
    row.used_at = now
    await _set_password(db, user, body.new_password, now)
    await db.commit()


async def _set_password(db: DbSession, user: User, password: str, now: datetime) -> None:
    user.password_hash = hash_password(password)
    user.password_changed_at = now
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now)
    )


@router.post("/me/password")
async def change_password(
    body: ChangePasswordRequest, db: DbSession, user: CurrentUser
) -> TokenResponse:
    """비밀번호를 바꾸고 모든 기기의 로그인을 끊는다. 요청한 기기에는 새 토큰을 준다."""
    if not verify_password(user.password_hash, body.current_password):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "현재 비밀번호가 올바르지 않습니다.")
    if body.new_password == body.current_password:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "지금과 다른 비밀번호로 정해 주세요.")
    password_policy.enforce(body.new_password, user.email)

    await _set_password(db, user, body.new_password, datetime.now(UTC))
    return await _issue_tokens(db, user)


@router.get("/me")
async def me(user: CurrentUser) -> UserOut:
    return UserOut.model_validate(user)

import uuid
from datetime import datetime
from typing import Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, EmailStr, Field


class SignupRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)
    display_name: str = Field(min_length=1, max_length=100)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=1, max_length=128)


class ResetLink(BaseModel):
    # 관리자 페이지가 자기 주소(origin)를 붙여 링크를 만든다.
    token: str
    expires_at: datetime


class ResetTokenRequest(BaseModel):
    token: str = Field(min_length=20, max_length=100)


class ResetTokenInfo(BaseModel):
    display_name: str
    # 링크를 연 사람에게 전체 주소를 보여 주지 않는다.
    email_hint: str
    expires_at: datetime


class ResetPasswordRequest(ResetTokenRequest):
    new_password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    display_name: str
    status: str
    is_admin: bool
    created_at: datetime


class AdminUserOut(UserOut):
    approved_at: datetime | None


class SignupResult(BaseModel):
    user: UserOut
    message: str


class SetupStatus(BaseModel):
    needs_setup: bool


class SetupRequest(SignupRequest):
    setup_code: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    user: UserOut


# 시각은 모두 오프셋이 있는 값만 받는다. 앱의 로컬 시각이 시간대 없이 넘어오는 것을 막기 위해서다.


class SessionCreate(BaseModel):
    id: uuid.UUID
    title: str = Field(min_length=1, max_length=200)
    note: str | None = None
    started_at: AwareDatetime


class SessionUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    note: str | None = None
    featured_photo_id: uuid.UUID | None = None
    steps: int | None = Field(default=None, ge=0)


class PointIn(BaseModel):
    seq: int = Field(ge=0)
    recorded_at: AwareDatetime
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    elevation: float | None = None
    accuracy: float | None = None
    speed: float | None = None


class PointBatch(BaseModel):
    points: list[PointIn] = Field(min_length=1, max_length=5000)


class PointBatchResult(BaseModel):
    received: int
    # 0부터 빠짐없이 저장된 마지막 seq. 하나도 없으면 -1.
    last_acked_seq: int


class SessionFinish(BaseModel):
    ended_at: AwareDatetime
    # 앱이 보낸 마지막 seq. 포인트가 없으면 -1.
    last_seq: int = Field(ge=-1)


class PointOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    seq: int
    recorded_at: datetime
    lat: float
    lng: float
    elevation: float | None
    accuracy: float | None
    speed: float | None


class PhotoCreate(BaseModel):
    id: uuid.UUID
    session_id: uuid.UUID
    taken_at: AwareDatetime
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    caption: str | None = None
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    # display 이미지 크기. complete 때 스토리지의 실제 크기와 비교한다.
    size_bytes: int = Field(gt=0, le=20 * 1024 * 1024)
    content_type: Literal["image/jpeg", "image/webp"]


class PhotoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    session_id: uuid.UUID
    taken_at: datetime
    lat: float
    lng: float
    caption: str | None
    sha256: str
    size_bytes: int
    content_type: str
    status: str
    # status가 ready일 때만 채운다. presigned GET이라 요청마다 값이 바뀐다.
    urls: dict[str, str] | None = None


class UploadTarget(BaseModel):
    url: str
    method: Literal["PUT"] = "PUT"
    # 서명에 포함된 헤더. 앱이 똑같이 보내야 403이 나지 않는다.
    headers: dict[str, str]


class PhotoCreateResult(BaseModel):
    photo: PhotoOut
    # 이미 업로드가 끝난 사진이면 비어 있다.
    uploads: dict[str, UploadTarget]


class SessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    note: str | None
    started_at: datetime
    ended_at: datetime | None
    featured_photo_id: uuid.UUID | None
    distance_m: float | None
    point_count: int
    steps: int | None
    updated_at: datetime


class SessionDetail(SessionOut):
    points: list[PointOut]
    photos: list[PhotoOut]

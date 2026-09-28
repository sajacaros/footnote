import uuid

import aioboto3
from botocore.config import Config
from botocore.exceptions import ClientError

from .config import get_settings

_session = aioboto3.Session()
# SeaweedFS는 path-style 주소가 가장 무난하다.
_config = Config(signature_version="s3v4", s3={"addressing_style": "path"})

VARIANTS = ("display", "thumb")
_EXTENSIONS = {"image/jpeg": "jpg", "image/webp": "webp"}


def photo_key(user_id: uuid.UUID, photo_id: uuid.UUID, variant: str, content_type: str) -> str:
    return f"u/{user_id}/p/{photo_id}/{variant}.{_EXTENSIONS[content_type]}"


def _client(endpoint: str):
    settings = get_settings()
    return _session.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=settings.s3_access_key,
        aws_secret_access_key=settings.s3_secret_key,
        region_name=settings.s3_region,
        config=_config,
    )


def internal_client():
    """백엔드 ↔ 스토리지 직접 통신용."""
    return _client(get_settings().s3_endpoint)


def signing_client():
    """presigned URL 서명용. 폰이 접속하는 외부 주소로 서명해야 Host가 맞는다."""
    return _client(get_settings().s3_public_endpoint)


async def ensure_bucket() -> None:
    bucket = get_settings().s3_bucket
    async with internal_client() as s3:
        try:
            await s3.head_bucket(Bucket=bucket)
        except ClientError:
            await s3.create_bucket(Bucket=bucket)


async def presign_put(key: str, content_type: str) -> str:
    settings = get_settings()
    async with signing_client() as s3:
        return await s3.generate_presigned_url(
            "put_object",
            Params={"Bucket": settings.s3_bucket, "Key": key, "ContentType": content_type},
            ExpiresIn=settings.presign_seconds,
        )


async def presign_get(key: str) -> str:
    settings = get_settings()
    async with signing_client() as s3:
        return await s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.s3_bucket, "Key": key},
            ExpiresIn=settings.presign_seconds,
        )


async def object_size(key: str) -> int | None:
    """객체가 없으면 None."""
    async with internal_client() as s3:
        try:
            head = await s3.head_object(Bucket=get_settings().s3_bucket, Key=key)
        except ClientError as error:
            if error.response.get("Error", {}).get("Code") in ("404", "NoSuchKey", "NotFound"):
                return None
            raise
        return head["ContentLength"]


async def delete_objects(keys: list[str]) -> None:
    if not keys:
        return
    async with internal_client() as s3:
        await s3.delete_objects(
            Bucket=get_settings().s3_bucket,
            Delete={"Objects": [{"Key": key} for key in keys], "Quiet": True},
        )

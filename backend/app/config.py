from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://footnote:footnote@localhost:15433/footnote"

    jwt_secret: str = "dev-only-insecure-jwt-secret-change-me"
    access_token_minutes: int = 30
    refresh_token_days: int = 30

    # 백엔드가 SeaweedFS와 직접 통신할 때 쓰는 주소(도커 내부망).
    s3_endpoint: str = "http://localhost:8333"
    # presigned URL에 서명할 주소. 폰이 실제로 접속하는 외부 주소여야 한다.
    s3_public_endpoint: str = "http://localhost:8333"
    s3_access_key: str = "footnote"
    s3_secret_key: str = "footnote-secret"
    s3_bucket: str = "footnote"
    s3_region: str = "us-east-1"
    presign_seconds: int = 900

    # gzip 요청 본문을 풀었을 때 허용하는 최대 크기.
    max_request_bytes: int = 20 * 1024 * 1024

    @field_validator("jwt_secret")
    @classmethod
    def _long_enough(cls, value: str) -> str:
        # HS256 키는 32바이트 이상이어야 한다(RFC 7518 3.2).
        if len(value.encode()) < 32:
            raise ValueError("JWT_SECRET must be at least 32 bytes")
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()

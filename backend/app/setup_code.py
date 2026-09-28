"""첫 관리자 셋업용 일회용 코드.

관리자가 없는 상태에서 서버가 뜨면 코드를 만들어 로그에만 찍는다. 공개된 주소에서
셋업 페이지를 먼저 연 제3자가 관리자를 가로채지 못하게 하려는 장치다.
"""

import logging
import os
import secrets

logger = logging.getLogger("uvicorn.error")

_code: str | None = None


def issue() -> None:
    global _code
    _code = os.environ.get("SETUP_CODE") or "-".join(
        secrets.token_hex(3).upper() for _ in range(3)
    )
    logger.warning("=" * 60)
    logger.warning("관리자 계정이 없습니다. 셋업 페이지에서 아래 코드를 입력하세요.")
    logger.warning("SETUP CODE: %s", _code)
    logger.warning("=" * 60)


def matches(candidate: str) -> bool:
    if _code is None:
        return False
    return secrets.compare_digest(candidate.strip().upper(), _code.upper())


def clear() -> None:
    global _code
    _code = None

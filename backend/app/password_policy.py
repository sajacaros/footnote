"""비밀번호 규칙. 가입·셋업·변경·재설정에 똑같이 적용한다.

화면(app/web/password-policy.js, lib/services/password_policy.dart)도 같은 규칙으로
입력하는 동안 체크리스트를 보여 준다. 규칙을 바꾸면 세 곳을 함께 고친다.
"""

import re

from fastapi import HTTPException, status

MIN_LENGTH = 10
MAX_LENGTH = 64

# 키보드 배열과 숫자열. 이 안에서 4자리 이상 이어지면 연속 문자로 본다(역순 포함).
_SEQUENCES = ("abcdefghijklmnopqrstuvwxyz", "0123456789", "qwertyuiop", "asdfghjkl", "zxcvbnm")
_SEQUENCE_RUN = 4

# 소문자로 바꿨을 때 이 단어가 들어 있으면 거부한다.
COMMON_WORDS = (
    "password", "passw0rd", "qwerty", "iloveyou", "admin", "welcome", "letmein",
    "footnote", "sunshine", "princess", "dragon", "monkey", "master", "login",
)

RULES = {
    "length": f"{MIN_LENGTH}자 이상 {MAX_LENGTH}자 이하",
    "letter": "영문 포함",
    "digit": "숫자 포함",
    "special": "특수문자 포함 (예: ! @ # $ %)",
    "no_space": "공백 없음",
    "no_repeat": "같은 문자 3번 이상 연속 금지 (예: aaa, 111)",
    "no_sequence": "연속된 문자 4자리 이상 금지 (예: 1234, abcd, qwer)",
    "no_email": "이메일 아이디 포함 금지",
    "no_common": "쉽게 추측되는 단어 금지 (예: password, qwerty)",
}


def _has_sequence(password: str) -> bool:
    lowered = password.lower()
    for sequence in _SEQUENCES:
        for text in (sequence, sequence[::-1]):
            for start in range(len(text) - _SEQUENCE_RUN + 1):
                if text[start : start + _SEQUENCE_RUN] in lowered:
                    return True
    return False


def violations(password: str, email: str | None = None) -> list[str]:
    """지키지 못한 규칙의 코드 목록. 비어 있으면 통과."""
    failed = []
    if not MIN_LENGTH <= len(password) <= MAX_LENGTH:
        failed.append("length")
    if not re.search(r"[A-Za-z]", password):
        failed.append("letter")
    if not re.search(r"[0-9]", password):
        failed.append("digit")
    if not re.search(r"[^A-Za-z0-9\s]", password):
        failed.append("special")
    if re.search(r"\s", password):
        failed.append("no_space")
    if re.search(r"(.)\1\1", password):
        failed.append("no_repeat")
    if _has_sequence(password):
        failed.append("no_sequence")
    if email:
        local = email.split("@", 1)[0].lower()
        if len(local) >= 3 and local in password.lower():
            failed.append("no_email")
    if any(word in password.lower() for word in COMMON_WORDS):
        failed.append("no_common")
    return failed


def enforce(password: str, email: str | None = None) -> None:
    """규칙을 어기면 어떤 규칙인지 목록과 함께 400을 던진다."""
    failed = violations(password, email)
    if failed:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            {
                "code": "weak_password",
                "message": "비밀번호가 규칙에 맞지 않습니다: " + ", ".join(RULES[code] for code in failed),
                "problems": [{"code": code, "message": RULES[code]} for code in failed],
            },
        )

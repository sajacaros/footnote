# Footnote Walk 백엔드

앱의 산책 기록·GPS·사진을 보관하는 서버입니다.

- **API**: FastAPI, JWT(액세스 30분 / refresh 30일, 한 번 쓰면 교체)
- **DB**: PostgreSQL + TimescaleDB(GPS 포인트 hypertable) + PostGIS(경로·거리 계산)
- **사진**: SeaweedFS(S3 호환). 앱이 presigned URL로 직접 올리고 받습니다.
- **가입**: 관리자 승인제. 처음 웹(`/`)을 열면 셋업 페이지에서 첫 관리자를 만듭니다.

## 로컬 개발

```bash
cp .env.example .env
docker compose up -d db storage      # DB와 SeaweedFS
uv sync
uv run alembic upgrade head
uv run uvicorn app.main:app --reload
uv run pytest                         # 실제 DB·SeaweedFS를 쓰는 통합 테스트
```

첫 관리자 셋업 코드는 서버 로그의 `SETUP CODE` 줄에 찍힙니다.

## 배포 (docker compose)

```bash
cp deploy/deploy.env.example deploy/deploy.env   # 서버 주소·계정 입력(커밋하지 않음)
./deploy/deploy.sh
```

- 서버의 `.env`(DB 비밀번호, JWT 키, S3 키)는 첫 배포 때 서버 안에서 무작위로 만들어지고 밖으로 나오지 않습니다.
- 컨테이너는 `127.0.0.1`에만 열립니다. 외부 HTTPS는 호스트 nginx가 받습니다. `deploy/footnote.nginx.conf`의 `__PUBLIC_HOST__`를 도메인으로 바꿔 설치하세요(8443 → API, 8444 → S3).
- presigned URL은 서명에 Host(포트 포함)가 들어가므로 S3 쪽 프록시는 `$http_host`를 그대로 넘겨야 합니다.

## 주요 API

| 경로 | 설명 |
|---|---|
| `POST /v1/auth/signup` · `login` · `refresh` · `logout` | 가입 신청(승인 대기), 로그인, 토큰 갱신 |
| `POST /v1/me/password` | 비밀번호 변경(다른 기기 로그아웃) |
| `POST /v1/auth/reset-password` | 관리자가 만든 재설정 링크로 비밀번호 재설정 |
| `POST /v1/sessions` · `…/points:batch` · `…/finish` | 산책 생성(멱등), GPS 벌크 전송(gzip), 종료·거리 계산 |
| `POST /v1/photos` · `…/complete` | 사진 등록 → presigned PUT → 업로드 확인 |
| `/v1/admin/users…` | 가입 승인·거절, 재설정 링크 발급 |

전체 명세는 서버의 `/docs`에서 볼 수 있습니다.

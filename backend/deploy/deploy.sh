#!/usr/bin/env bash
# 개발 서버에 백엔드를 docker compose로 배포한다.
#   cp deploy/deploy.env.example deploy/deploy.env   # 한 번만, 값 채우기
#   ./deploy/deploy.sh
# 서버의 .env는 처음 한 번 서버 안에서 비밀값을 생성하고, 이후에는 그대로 둔다.
set -euo pipefail

cd "$(dirname "$0")/.."
# 서버 주소·계정은 저장소에 넣지 않는다.
if [ -f deploy/deploy.env ]; then
  # shellcheck disable=SC1091
  . deploy/deploy.env
fi
: "${DEPLOY_HOST:?deploy/deploy.env에 DEPLOY_HOST를 넣어 주세요}"
: "${DEPLOY_USER:?deploy/deploy.env에 DEPLOY_USER를 넣어 주세요}"
: "${PUBLIC_HOST:?deploy/deploy.env에 PUBLIC_HOST를 넣어 주세요}"
HOST="$DEPLOY_HOST"
PORT="${DEPLOY_PORT:-22}"
USER_NAME="$DEPLOY_USER"
KEY="${DEPLOY_KEY:-$HOME/.ssh/id_ed25519}"
REMOTE_DIR="${DEPLOY_DIR:-/var/local/footnote}"

SSH=(ssh -p "$PORT" -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes "$USER_NAME@$HOST")
echo "==> 소스 전송"
rsync -az --delete \
  -e "ssh -p $PORT -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes" \
  --exclude .venv --exclude .env --exclude deploy/deploy.env \
  --exclude .pytest_cache --exclude __pycache__ \
  ./ "$USER_NAME@$HOST:$REMOTE_DIR/"

echo "==> 서버 .env 확인"
"${SSH[@]}" "cd $REMOTE_DIR && if [ ! -f .env ]; then
  umask 077
  cat > .env <<ENV
POSTGRES_PASSWORD=\$(openssl rand -hex 24)
JWT_SECRET=\$(openssl rand -hex 32)
S3_ACCESS_KEY=footnote-\$(openssl rand -hex 6)
S3_SECRET_KEY=\$(openssl rand -hex 24)
S3_BUCKET=footnote
S3_PUBLIC_ENDPOINT=https://$PUBLIC_HOST:8444
API_BIND=127.0.0.1
API_PORT=8210
S3_BIND=127.0.0.1
S3_PORT=8211
DB_PORT=15434
ENV
  echo '   새 .env 생성'
else
  echo '   기존 .env 유지'
fi"

echo "==> 컨테이너 빌드·기동"
"${SSH[@]}" "cd $REMOTE_DIR && docker compose --profile api up -d --build --remove-orphans"

echo "==> 상태 확인"
for _ in $(seq 1 30); do
  if "${SSH[@]}" "curl -fsS http://127.0.0.1:8210/healthz" >/dev/null 2>&1; then
    "${SSH[@]}" "cd $REMOTE_DIR && docker compose ps --format '{{.Service}}\t{{.Status}}'"
    echo "배포 완료: https://$PUBLIC_HOST:8443/healthz (nginx 설정 적용 후)"
    exit 0
  fi
  sleep 2
done
echo "API가 응답하지 않습니다. 로그:" >&2
"${SSH[@]}" "cd $REMOTE_DIR && docker compose logs --tail 50 api" >&2
exit 1

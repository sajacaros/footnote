#!/bin/sh
# 환경변수로 받은 앱 전용 키로 S3 설정을 만들고 단일 프로세스로 SeaweedFS를 띄운다.
set -eu
mkdir -p /etc/seaweedfs
cat > /etc/seaweedfs/s3.json <<JSON
{
  "identities": [
    {
      "name": "footnote-api",
      "credentials": [{ "accessKey": "${S3_ACCESS_KEY}", "secretKey": "${S3_SECRET_KEY}" }],
      "actions": ["Admin:${S3_BUCKET}", "Read:${S3_BUCKET}", "Write:${S3_BUCKET}", "List:${S3_BUCKET}", "Tagging:${S3_BUCKET}"]
    }
  ]
}
JSON
exec weed server \
  -dir=/data \
  -ip.bind=0.0.0.0 \
  -master.defaultReplication=000 \
  -master.volumeSizeLimitMB=1024 \
  -volume.max=0 \
  -filer \
  -s3 -s3.port=8333 -s3.config=/etc/seaweedfs/s3.json

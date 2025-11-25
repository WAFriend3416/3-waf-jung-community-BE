#!/bin/bash
set -e

AWS_REGION="ap-northeast-2"
ENV_FILE=".env"

# Parameter Store에서 값 가져오기
get_param() {
    aws ssm get-parameter --name "$1" --with-decryption \
        --query 'Parameter.Value' --output text --region "$AWS_REGION"
}

echo "=== Parameter Store에서 환경변수 로드 ==="

# .env 파일 생성
cat > $ENV_FILE << EOF
DB_URL=$(get_param "/community/week10/DB_URL")
DB_USERNAME=$(get_param "/community/week10/DB_USERNAME")
DB_PASSWORD=$(get_param "/community/week10/DB_PASSWORD")
JWT_SECRET=$(get_param "/community/JWT_SECRET")
AWS_S3_BUCKET=$(get_param "/community/AWS_S3_BUCKET")
AWS_REGION=$(get_param "/community/AWS_REGION")
FRONTEND_URL=$(get_param "/community/FRONTEND_URL")
REGISTRY=${1:-registry.ktb-waf.cloud}
IMAGE_NAME=${2:-community-be}
IMAGE_TAG=${3:-latest}
EOF

echo ".env 파일 생성 완료"

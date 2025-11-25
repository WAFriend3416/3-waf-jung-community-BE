#!/bin/bash
# ========================================
# Backend 애플리케이션 배포 스크립트 (Docker 버전)
# 환경: Ubuntu 22.04 LTS, Docker 24+
# 용도: ECR Pull → Parameter Store 로드 → Docker Run
# ========================================

set -e  # 오류 발생 시 즉시 중단

echo "=========================================="
echo "Backend Docker Deployment"
echo "=========================================="

# ========================================
# 1. 환경 변수 설정
# ========================================
CONTAINER_NAME="community-backend"
ECR_REGISTRY="123456789012.dkr.ecr.ap-northeast-2.amazonaws.com"
IMAGE_NAME="community-backend"
IMAGE_TAG="latest"
FULL_IMAGE="$ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"

echo ""
echo "[1/5] 환경 변수 설정 완료"
echo "  - Image: $FULL_IMAGE"

# ========================================
# 2. 기존 컨테이너 중지 및 제거
# ========================================
echo ""
echo "[2/5] 기존 컨테이너 중지 중..."
if docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
    echo "  ✅ 기존 컨테이너 제거 완료"
else
    echo "  ⚠️  실행 중인 컨테이너 없음 (최초 배포)"
fi

# ========================================
# 3. ECR 로그인 및 이미지 Pull
# ========================================
echo ""
echo "[3/5] ECR 이미지 다운로드 중..."

# ECR 로그인 (IAM 역할 자동 인증)
aws ecr get-login-password --region ap-northeast-2 | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

# 이미지 Pull
docker pull $FULL_IMAGE

echo "  ✅ 이미지 다운로드 완료"
docker images | grep $IMAGE_NAME

# ========================================
# 4. Parameter Store에서 환경 변수 로드
# ========================================
echo ""
echo "[4/5] Parameter Store에서 환경 변수 로드 중..."

# 환경 변수 로드 (동일한 7개 변수)
DB_URL=$(aws ssm get-parameter \
    --name /community/DB_URL \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)

DB_USERNAME=$(aws ssm get-parameter \
    --name /community/DB_USERNAME \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)

DB_PASSWORD=$(aws ssm get-parameter \
    --name /community/DB_PASSWORD \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)

JWT_SECRET=$(aws ssm get-parameter \
    --name /community/JWT_SECRET \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)

AWS_S3_BUCKET=$(aws ssm get-parameter \
    --name /community/AWS_S3_BUCKET \
    --query 'Parameter.Value' \
    --output text)

AWS_REGION=$(aws ssm get-parameter \
    --name /community/AWS_REGION \
    --query 'Parameter.Value' \
    --output text)

FRONTEND_URL=$(aws ssm get-parameter \
    --name /community/FRONTEND_URL \
    --query 'Parameter.Value' \
    --output text)

echo "  ✅ 환경 변수 로드 완료"
echo "  - DB_URL: ${DB_URL%%\?*}..."
echo "  - AWS_S3_BUCKET: $AWS_S3_BUCKET"
echo "  - AWS_REGION: $AWS_REGION"

# ========================================
# 5. Docker 컨테이너 실행
# ========================================
echo ""
echo "[5/5] Docker 컨테이너 시작 중..."

docker run -d \
    --name $CONTAINER_NAME \
    --restart unless-stopped \
    -p 8080:8080 \
    -e DB_URL="$DB_URL" \
    -e DB_USERNAME="$DB_USERNAME" \
    -e DB_PASSWORD="$DB_PASSWORD" \
    -e JWT_SECRET="$JWT_SECRET" \
    -e AWS_S3_BUCKET="$AWS_S3_BUCKET" \
    -e AWS_REGION="$AWS_REGION" \
    -e FRONTEND_URL="$FRONTEND_URL" \
    -e JAVA_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC" \
    $FULL_IMAGE

# 컨테이너 시작 대기
echo "  애플리케이션 시작 대기 중..."
sleep 5

# 헬스 체크
MAX_RETRY=12
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRY ]; do
    if curl -f -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "  ✅ 헬스 체크 성공"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        echo "  ⏳ 헬스 체크 재시도 ($RETRY_COUNT/$MAX_RETRY)..."
        sleep 5
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRY ]; then
    echo "  ⚠️  헬스 체크 타임아웃"
    docker logs $CONTAINER_NAME --tail 50
    exit 1
fi

# ========================================
# 배포 완료
# ========================================
echo ""
echo "=========================================="
echo "✅ Backend Docker 배포 완료"
echo "=========================================="
echo ""
echo "컨테이너 상태:"
docker ps -f name=$CONTAINER_NAME
echo ""
echo "유용한 명령어:"
echo "  - 로그 확인: docker logs -f $CONTAINER_NAME"
echo "  - 컨테이너 재시작: docker restart $CONTAINER_NAME"
echo "  - 컨테이너 중지: docker stop $CONTAINER_NAME"
echo "  - 컨테이너 내부 접속: docker exec -it $CONTAINER_NAME sh"
echo "  - 헬스 체크: curl http://localhost:8080/health"
echo "=========================================="

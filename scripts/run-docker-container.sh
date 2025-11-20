#!/bin/bash

################################################################################
# Docker 컨테이너 실행 스크립트
# 용도: AWS Parameter Store에서 환경 변수 로드 후 Docker 컨테이너 실행
# 사용: ./scripts/run-docker-container.sh <이미지명>
# 예시: ./scripts/run-docker-container.sh ktb-community-be:latest
# 요구사항: EC2 IAM 역할 (SSM, S3 권한 필요)
################################################################################

set -e  # 에러 발생 시 스크립트 중지

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 인자 확인
if [ $# -eq 0 ]; then
    echo -e "${RED}에러: Docker 이미지명을 지정해주세요.${NC}"
    echo ""
    echo "사용법:"
    echo "  ./scripts/run-docker-container.sh <이미지명>"
    echo ""
    echo "예시:"
    echo "  ./scripts/run-docker-container.sh ktb-community-be:latest"
    echo "  ./scripts/run-docker-container.sh ktb-community-be:v1.0.0"
    echo ""
    exit 1
fi

# 설정
CONTAINER_NAME="community-backend"
IMAGE_NAME="$1"  # 첫 번째 인자를 이미지명으로 사용
CONTAINER_PORT=8080
HOST_PORT=8080
MEMORY_LIMIT="1g"
AWS_REGION="ap-northeast-2"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Docker 컨테이너 실행 시작${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

################################################################################
# 1. 사전 검증
################################################################################

echo -e "${YELLOW}[1/6] 사전 검증${NC}"

# Docker 설치 확인
if ! command -v docker &> /dev/null; then
    echo -e "${RED}에러: Docker가 설치되어 있지 않습니다.${NC}"
    exit 1
fi
echo "  ✓ Docker 설치됨"

# AWS CLI 설치 확인
if ! command -v aws &> /dev/null; then
    echo -e "${RED}에러: AWS CLI가 설치되어 있지 않습니다.${NC}"
    exit 1
fi
echo "  ✓ AWS CLI 설치됨"

# IAM 역할 확인
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}에러: AWS 인증에 실패했습니다.${NC}"
    echo "  EC2 IAM 역할이 연결되어 있는지 확인하세요."
    exit 1
fi
echo "  ✓ AWS 인증 성공"

# Docker 이미지 존재 확인
if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$IMAGE_NAME$"; then
    echo -e "${RED}에러: Docker 이미지를 찾을 수 없습니다: $IMAGE_NAME${NC}"
    echo ""
    echo "다음 명령어로 이미지를 빌드하세요:"
    echo "  ./scripts/build-docker-image.sh"
    echo ""
    echo "또는 이미지를 로드하세요:"
    echo "  docker load < ktb-community-be.tar.gz"
    exit 1
fi
echo "  ✓ Docker 이미지 존재: $IMAGE_NAME"
echo ""

################################################################################
# 2. AWS Parameter Store에서 환경 변수 로드
################################################################################

echo -e "${YELLOW}[2/6] AWS Parameter Store에서 환경 변수 로드${NC}"

# Parameter 이름 목록
PARAM_NAMES=(
    "/community/week10/DB_URL"
    "/community/week10/DB_USERNAME"
    "/community/week10/DB_PASSWORD"
    "/community/JWT_SECRET"
    "/community/AWS_S3_BUCKET"
    "/community/AWS_REGION"
    "/community/FRONTEND_URL"
)

# 환경 변수 로드 함수
load_parameter() {
    local param_name=$1
    local var_name=$(echo "$param_name" | sed 's/\/community\/week10\///' | sed 's/\/community\///')

    echo -n "  로드 중: $param_name ... "

    local param_value=$(aws ssm get-parameter \
        --name "$param_name" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text \
        --region "$AWS_REGION" 2>&1)

    if [ $? -eq 0 ] && [ -n "$param_value" ]; then
        export "$var_name"="$param_value"
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}    에러: Parameter Store에서 값을 가져올 수 없습니다.${NC}"
        echo "    Parameter: $param_name"
        echo "    응답: $param_value"
        return 1
    fi
}

# 모든 파라미터 로드
FAILED_PARAMS=()
for param in "${PARAM_NAMES[@]}"; do
    if ! load_parameter "$param"; then
        FAILED_PARAMS+=("$param")
    fi
done

# 로드 실패 파라미터 확인
if [ ${#FAILED_PARAMS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Parameter 로드 실패!${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "실패한 Parameter 목록:"
    for param in "${FAILED_PARAMS[@]}"; do
        echo "  - $param"
    done
    echo ""
    echo "해결 방법:"
    echo "  1. AWS Console에서 Parameter Store에 값이 등록되어 있는지 확인"
    echo "  2. EC2 IAM 역할에 ssm:GetParameter 권한이 있는지 확인"
    echo "  3. SecureString 타입인 경우 kms:Decrypt 권한 확인"
    echo ""
    exit 1
fi

echo ""
echo -e "${GREEN}모든 환경 변수 로드 완료 (7개)${NC}"
echo ""

################################################################################
# 3. 기존 컨테이너 확인 및 중지
################################################################################

echo -e "${YELLOW}[3/6] 기존 컨테이너 확인${NC}"

if docker ps -a | grep -q "$CONTAINER_NAME"; then
    echo "  기존 컨테이너 발견: $CONTAINER_NAME"

    if docker ps | grep -q "$CONTAINER_NAME"; then
        echo "  컨테이너 중지 중..."
        docker stop "$CONTAINER_NAME"
    fi

    echo "  컨테이너 삭제 중..."
    docker rm "$CONTAINER_NAME"
    echo -e "  ${GREEN}✓ 기존 컨테이너 정리 완료${NC}"
else
    echo "  기존 컨테이너 없음"
fi
echo ""

################################################################################
# 4. Docker 컨테이너 실행
################################################################################

echo -e "${YELLOW}[4/6] Docker 컨테이너 실행${NC}"
echo "  이미지: $IMAGE_NAME"
echo "  컨테이너: $CONTAINER_NAME"
echo "  포트: $HOST_PORT:$CONTAINER_PORT"
echo "  메모리 제한: $MEMORY_LIMIT"
echo ""

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "$HOST_PORT:$CONTAINER_PORT" \
    --memory="$MEMORY_LIMIT" \
    --memory-swap="$MEMORY_LIMIT" \
    -e DB_URL="$DB_URL" \
    -e DB_USERNAME="$DB_USERNAME" \
    -e DB_PASSWORD="$DB_PASSWORD" \
    -e JWT_SECRET="$JWT_SECRET" \
    -e AWS_S3_BUCKET="$AWS_S3_BUCKET" \
    -e AWS_REGION="$AWS_REGION" \
    -e FRONTEND_URL="$FRONTEND_URL" \
    "$IMAGE_NAME"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 컨테이너 시작 성공${NC}"
else
    echo -e "${RED}✗ 컨테이너 시작 실패${NC}"
    echo ""
    echo "로그 확인:"
    echo "  docker logs $CONTAINER_NAME"
    exit 1
fi
echo ""

################################################################################
# 5. 헬스 체크
################################################################################

echo -e "${YELLOW}[5/6] 헬스 체크 (최대 60초 대기)${NC}"

MAX_ATTEMPTS=60
ATTEMPT=0
HEALTH_URL="http://localhost:$HOST_PORT/health"

echo -n "  Spring Boot 시작 대기 중"

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s -f "$HEALTH_URL" > /dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}✓ 헬스 체크 성공 (${ATTEMPT}초)${NC}"

        # 헬스 체크 응답 출력
        HEALTH_RESPONSE=$(curl -s "$HEALTH_URL")
        echo "  응답: $HEALTH_RESPONSE"
        break
    fi

    echo -n "."
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo ""
    echo -e "${RED}✗ 헬스 체크 실패 (60초 타임아웃)${NC}"
    echo ""
    echo "컨테이너 로그:"
    docker logs --tail 30 "$CONTAINER_NAME"
    echo ""
    echo "컨테이너가 시작되지 않았습니다."
    echo "위 로그를 확인하고 문제를 해결하세요."
    exit 1
fi
echo ""

################################################################################
# 6. 배포 완료
################################################################################

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}배포 완료! ✅${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 컨테이너 정보 출력
echo "컨테이너 상태:"
docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "유용한 명령어:"
echo "  - 로그 확인: docker logs -f $CONTAINER_NAME"
echo "  - 컨테이너 중지: ./scripts/stop-docker-container.sh"
echo "  - 컨테이너 재시작: ./scripts/restart-docker-container.sh"
echo "  - 헬스 체크: curl http://localhost:$HOST_PORT/health"
echo ""

echo "API 테스트:"
echo "  curl http://localhost:$HOST_PORT/health"
echo ""

echo -e "${BLUE}축하합니다! 백엔드 서버가 성공적으로 시작되었습니다. 🚀${NC}"
echo ""

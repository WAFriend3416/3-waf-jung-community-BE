#!/bin/bash

################################################################################
# Docker 이미지 빌드 스크립트
# 용도: Dockerfile로 로컬 이미지 빌드
# 사용: ./scripts/build-docker-image.sh
################################################################################

set -e  # 에러 발생 시 스크립트 중지

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 설정
IMAGE_NAME="ktb-community-be"
IMAGE_TAG="latest"
DOCKERFILE="Dockerfile"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Docker 이미지 빌드 시작${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 프로젝트 루트 디렉토리로 이동
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${YELLOW}[1/4] 현재 디렉토리 확인${NC}"
echo "  위치: $PROJECT_ROOT"
echo ""

# Dockerfile 존재 확인
if [ ! -f "$DOCKERFILE" ]; then
    echo -e "${RED}에러: Dockerfile을 찾을 수 없습니다.${NC}"
    exit 1
fi

echo -e "${YELLOW}[2/4] Dockerfile 확인${NC}"
echo "  파일: $DOCKERFILE"
echo "  타입: Multi-Stage Build (Builder + Runtime)"
echo ""

# 기존 이미지 확인
if docker images | grep -q "$IMAGE_NAME.*$IMAGE_TAG"; then
    echo -e "${YELLOW}[3/4] 기존 이미지 발견${NC}"
    docker images "$IMAGE_NAME:$IMAGE_TAG"
    echo ""
    read -p "기존 이미지를 삭제하고 재빌드하시겠습니까? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "  기존 이미지 삭제 중..."
        docker rmi "$IMAGE_NAME:$IMAGE_TAG" || true
    fi
else
    echo -e "${YELLOW}[3/4] 기존 이미지 없음${NC}"
    echo "  새 이미지를 빌드합니다."
fi
echo ""

# Docker 빌드
echo -e "${YELLOW}[4/4] Docker 이미지 빌드 중...${NC}"
echo "  플랫폼: linux/amd64 (EC2 호환)"
echo "  명령어: docker buildx build --platform linux/amd64 -t $IMAGE_NAME:$IMAGE_TAG --load ."
echo ""

# buildx 사용 가능 확인
if ! docker buildx version &> /dev/null; then
    echo -e "${RED}에러: docker buildx를 사용할 수 없습니다.${NC}"
    echo "Docker Desktop을 최신 버전으로 업데이트하세요."
    exit 1
fi

# 빌드 시작 시간 기록
BUILD_START=$(date +%s)

# Docker 빌드 실행 (linux/amd64 플랫폼 지정)
if docker buildx build --platform linux/amd64 -t "$IMAGE_NAME:$IMAGE_TAG" --load .; then
    BUILD_END=$(date +%s)
    BUILD_TIME=$((BUILD_END - BUILD_START))

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}빌드 성공! ✅${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "빌드 시간: ${BUILD_TIME}초"
    echo ""

    # 이미지 정보 출력
    echo "생성된 이미지:"
    docker images "$IMAGE_NAME:$IMAGE_TAG"
    echo ""

    # 이미지 크기 출력
    IMAGE_SIZE=$(docker images "$IMAGE_NAME:$IMAGE_TAG" --format "{{.Size}}")
    echo -e "이미지 크기: ${GREEN}$IMAGE_SIZE${NC}"
    echo ""

    # 다음 단계 안내
    echo "다음 단계:"
    echo "  1. EC2에서 컨테이너 실행: ./scripts/run-docker-container.sh"
    echo "  2. 로컬에서 테스트 실행:"
    echo "     docker run --rm -p 8080:8080 \\"
    echo "       -e DB_URL=... -e JWT_SECRET=... \\"
    echo "       $IMAGE_NAME:$IMAGE_TAG"
    echo ""
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}빌드 실패! ❌${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "에러 로그를 확인하고 문제를 해결한 후 다시 시도하세요."
    exit 1
fi

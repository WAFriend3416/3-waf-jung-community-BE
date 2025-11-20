#!/bin/bash

################################################################################
# Docker 컨테이너 중지 스크립트
# 용도: 실행 중인 컨테이너를 중지하고 삭제
# 사용: ./scripts/stop-docker-container.sh
################################################################################

set -e  # 에러 발생 시 스크립트 중지

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 설정
CONTAINER_NAME="community-backend"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Docker 컨테이너 중지${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Docker 설치 확인
if ! command -v docker &> /dev/null; then
    echo -e "${RED}에러: Docker가 설치되어 있지 않습니다.${NC}"
    exit 1
fi

# 컨테이너 존재 확인
if ! docker ps -a | grep -q "$CONTAINER_NAME"; then
    echo -e "${YELLOW}컨테이너를 찾을 수 없습니다: $CONTAINER_NAME${NC}"
    echo ""
    echo "실행 중인 컨테이너 목록:"
    docker ps -a
    exit 0
fi

echo "컨테이너 발견: $CONTAINER_NAME"
echo ""

# 실행 중인지 확인
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo "컨테이너 중지 중..."
    docker stop "$CONTAINER_NAME"
    echo -e "${GREEN}✓ 컨테이너 중지 완료${NC}"
else
    echo -e "${YELLOW}컨테이너가 이미 중지되어 있습니다.${NC}"
fi

# 컨테이너 삭제
echo "컨테이너 삭제 중..."
docker rm "$CONTAINER_NAME"
echo -e "${GREEN}✓ 컨테이너 삭제 완료${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}중지 완료! ✅${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "현재 실행 중인 컨테이너:"
docker ps
echo ""

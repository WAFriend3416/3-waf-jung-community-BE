#!/bin/bash

################################################################################
# Docker 컨테이너 재시작 스크립트
# 용도: 컨테이너를 중지하고 다시 시작 (편의 스크립트)
# 사용: ./scripts/restart-docker-container.sh <이미지명>
# 예시: ./scripts/restart-docker-container.sh ktb-community-be:latest
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
    echo "  ./scripts/restart-docker-container.sh <이미지명>"
    echo ""
    echo "예시:"
    echo "  ./scripts/restart-docker-container.sh ktb-community-be:latest"
    echo ""
    exit 1
fi

# 스크립트 디렉토리 찾기
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Docker 컨테이너 재시작${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 중지 스크립트 실행
echo -e "${YELLOW}Step 1: 기존 컨테이너 중지${NC}"
echo ""
"$SCRIPT_DIR/stop-docker-container.sh"

echo ""
echo -e "${YELLOW}Step 2: 새 컨테이너 시작${NC}"
echo ""
"$SCRIPT_DIR/run-docker-container.sh" "$1"

echo ""
echo -e "${BLUE}재시작 완료! 🚀${NC}"
echo ""

#!/bin/bash

# 통합 서버 시작 스크립트
# 1. 프론트엔드 서버 시작 (백그라운드)
# 2. 백엔드 변경사항 확인 후 필요시 빌드
# 3. 백엔드 서버 시작

set -e  # 에러 발생 시 스크립트 중단

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 프로젝트 경로 설정
BACKEND_DIR="/home/ubuntu/IdeaProjects/community"
FRONTEND_DIR="/home/ubuntu/fe/waf-3-community-fe"
# JAR 파일 자동 탐색 (가장 최근 수정된 .jar 파일)
JAR_FILE=$(find "$BACKEND_DIR/build/libs" -name "*.jar" -type f ! -name "*-plain.jar" 2>/dev/null | head -n 1)
ENV_FILE="$BACKEND_DIR/.env"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   통합 서버 시작 스크립트${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ============================================
# 1. 프론트엔드 서버 시작
# ============================================
echo -e "${GREEN}[1/3] 프론트엔드 서버 시작 중...${NC}"

if [ ! -d "$FRONTEND_DIR" ]; then
    echo -e "${RED}❌ 프론트엔드 디렉토리를 찾을 수 없습니다: $FRONTEND_DIR${NC}"
    exit 1
fi

cd "$FRONTEND_DIR"

# 이미 실행 중인 프론트엔드 프로세스 확인 및 종료
FRONTEND_PID=$(lsof -ti:3000 2>/dev/null || true)
START_FRONTEND=false

if [ -n "$FRONTEND_PID" ]; then
    echo -e "${YELLOW}⚠️  포트 3000이 이미 사용 중입니다 (PID: $FRONTEND_PID)${NC}"
    echo -e "${YELLOW}   기존 프로세스를 종료하고 재시작하시겠습니까? (y/n)${NC}"
    read -r KILL_FRONTEND
    if [ "$KILL_FRONTEND" = "y" ]; then
        kill -9 "$FRONTEND_PID"
        echo -e "${GREEN}✅ 기존 프로세스 종료 완료${NC}"
        sleep 2
        START_FRONTEND=true
    else
        echo -e "${YELLOW}⚠️  기존 프론트엔드 프로세스를 유지합니다${NC}"
    fi
else
    START_FRONTEND=true
fi

# 프론트엔드 시작 (새 프로세스 또는 종료 후)
if [ "$START_FRONTEND" = true ]; then
    # EC2 Public IP 조회 (프론트엔드 → 백엔드 통신)
    echo -e "${BLUE}🔍 프론트엔드용 EC2 Public IP 조회 중...${NC}"
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
    if [ -n "$TOKEN" ]; then
        FE_PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    else
        FE_PUBLIC_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    fi
    
    # 프론트엔드 환경변수 설정
    LAMBDA_API_URL="https://ul62gy8gxi.execute-api.ap-northeast-2.amazonaws.com/dev"

    # 프론트엔드 백그라운드 실행 (Public IP + Lambda API URL 사용)
    echo -e "${BLUE}🚀 npm start 실행 중...${NC}"
    if [ -n "$FE_PUBLIC_IP" ]; then
        echo -e "${GREEN}   EC2_PUBLIC_IP=$FE_PUBLIC_IP 설정됨${NC}"
        echo -e "${GREEN}   LAMBDA_API_URL=$LAMBDA_API_URL 설정됨${NC}"
        nohup env EC2_PUBLIC_IP="$FE_PUBLIC_IP" LAMBDA_API_URL="$LAMBDA_API_URL" npm start > "$FRONTEND_DIR/frontend.log" 2>&1 &
    else
        echo -e "${YELLOW}   ⚠️ Public IP 조회 실패, localhost 사용${NC}"
        echo -e "${GREEN}   LAMBDA_API_URL=$LAMBDA_API_URL 설정됨${NC}"
        nohup env LAMBDA_API_URL="$LAMBDA_API_URL" npm start > "$FRONTEND_DIR/frontend.log" 2>&1 &
    fi
    FRONTEND_PID=$!
    echo -e "${GREEN}✅ 프론트엔드 서버 시작됨 (PID: $FRONTEND_PID)${NC}"
    echo -e "${BLUE}   로그: $FRONTEND_DIR/frontend.log${NC}"
    
    # 프론트엔드 서버 준비 대기 (최대 30초)
    echo -e "${BLUE}   서버 준비 대기 중...${NC}"
    for i in {1..30}; do
        if curl -s http://localhost:3000 > /dev/null 2>&1; then
            echo -e "${GREEN}✅ 프론트엔드 서버 준비 완료 (${i}초)${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${YELLOW}⚠️  프론트엔드 서버 응답 대기 시간 초과 (계속 진행)${NC}"
        fi
        sleep 1
    done
fi

echo ""

# ============================================
# 2. 백엔드 빌드 확인
# ============================================
echo -e "${GREEN}[2/3] 백엔드 빌드 상태 확인 중...${NC}"

cd "$BACKEND_DIR"

NEED_BUILD=false

# JAR 파일 존재 여부 확인
if [ ! -f "$JAR_FILE" ]; then
    echo -e "${YELLOW}⚠️  JAR 파일이 없습니다. 빌드가 필요합니다.${NC}"
    NEED_BUILD=true
else
    echo -e "${GREEN}✅ JAR 파일 확인: $JAR_FILE${NC}"
fi

# 빌드 실행
if [ "$NEED_BUILD" = true ]; then
    echo -e "${BLUE}🔨 Gradle 빌드 시작...${NC}"
    ./gradlew clean build
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 빌드 성공${NC}"
    else
        echo -e "${RED}❌ 빌드 실패${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ 변경사항 없음. 기존 JAR 파일 사용${NC}"
fi

echo ""

# ============================================
# 3. 백엔드 환경변수 설정 및 서버 시작
# ============================================
echo -e "${GREEN}[3/3] 백엔드 서버 시작 중...${NC}"

# .env 파일 로드
if [ -f "$ENV_FILE" ]; then
    echo -e "${BLUE}📄 .env 파일 로드 중...${NC}"
    set -a
    source "$ENV_FILE"
    set +a
else
    echo -e "${YELLOW}⚠️  .env 파일이 없습니다. 기본값을 사용합니다.${NC}"
fi

# EC2 IP 주소 조회 (IMDSv2 지원)
echo -e "${BLUE}🔍 EC2 IP 주소 조회 중...${NC}"
# IMDSv2: 토큰 발급 후 메타데이터 조회
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
if [ -n "$TOKEN" ]; then
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "")
else
    # IMDSv1 fallback
    PUBLIC_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    PRIVATE_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "")
fi

if [ -n "$PUBLIC_IP" ]; then
    echo -e "${GREEN}✅ 퍼블릭 IP: $PUBLIC_IP${NC}"
    export FRONTEND_URL="http://${PUBLIC_IP}:3000"
else
    echo -e "${YELLOW}⚠️  퍼블릭 IP 조회 실패. localhost 사용${NC}"
    export FRONTEND_URL="http://localhost:3000"
fi

if [ -n "$PRIVATE_IP" ]; then
    echo -e "${GREEN}✅ 프라이빗 IP: $PRIVATE_IP${NC}"
    export EC2_PRIVATE_IP="$PRIVATE_IP"
else
    echo -e "${YELLOW}⚠️  프라이빗 IP 조회 실패${NC}"
fi

# 환경변수 확인
echo ""
echo -e "${BLUE}🔧 환경변수 확인:${NC}"
echo -e "   DB_URL: ${DB_URL:-${RED}NOT_SET${NC}}"
echo -e "   JWT_SECRET: ${JWT_SECRET:+${GREEN}SET${NC}}${JWT_SECRET:-${RED}NOT_SET${NC}}"
echo -e "   AWS_S3_BUCKET: ${AWS_S3_BUCKET:-${RED}NOT_SET${NC}}"
echo -e "   FRONTEND_URL: ${GREEN}${FRONTEND_URL}${NC}"
echo -e "   EC2_PRIVATE_IP: ${GREEN}${EC2_PRIVATE_IP:-${YELLOW}NOT_SET${NC}}${NC}"
echo ""

# 필수 환경변수 확인
if [ -z "$DB_URL" ] || [ -z "$JWT_SECRET" ]; then
    echo -e "${RED}❌ 필수 환경변수가 설정되지 않았습니다${NC}"
    echo -e "${YELLOW}   .env 파일을 확인하거나 환경변수를 설정해주세요${NC}"
    exit 1
fi

# 이미 실행 중인 백엔드 프로세스 확인
BACKEND_PID=$(lsof -ti:8080 2>/dev/null || true)
if [ -n "$BACKEND_PID" ]; then
    echo -e "${YELLOW}⚠️  포트 8080이 이미 사용 중입니다 (PID: $BACKEND_PID)${NC}"
    echo -e "${YELLOW}   기존 프로세스를 종료하고 재시작하시겠습니까? (y/n)${NC}"
    read -r KILL_BACKEND
    if [ "$KILL_BACKEND" = "y" ]; then
        kill -9 "$BACKEND_PID"
        echo -e "${GREEN}✅ 기존 프로세스 종료 완료${NC}"
        sleep 2
    else
        echo -e "${RED}❌ 백엔드 서버를 시작할 수 없습니다${NC}"
        exit 1
    fi
fi

# 백엔드 서버 실행
echo -e "${BLUE}🚀 Spring Boot 서버 시작...${NC}"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}   서버 접속 정보${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}   프론트엔드: http://localhost:3000${NC}"
if [ -n "$PUBLIC_IP" ]; then
    echo -e "${GREEN}             http://${PUBLIC_IP}:3000${NC}"
fi
echo -e "${GREEN}   백엔드:     http://localhost:8080${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# JVM 메모리 옵션 (t2.micro 957MB RAM)
# -Xms128m: 초기 힙 메모리 (빠른 시작)
# -Xmx256m: 최대 힙 메모리 (메모리 폭발 방지)
# -XX:MaxMetaspaceSize=128m: 클래스 메타데이터 메모리 제한
# -XX:+UseG1GC: G1 가비지 컬렉터 (저메모리 환경 최적화)
JVM_OPTS="-Xms128m -Xmx256m -XX:MaxMetaspaceSize=128m -XX:+UseG1GC"

java $JVM_OPTS -jar "$JAR_FILE"

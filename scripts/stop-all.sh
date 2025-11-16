#!/bin/bash

# 통합 서버 종료 스크립트
# 프론트엔드(포트 3000) + 백엔드(포트 8080) 프로세스 종료

set -e  # 에러 발생 시 스크립트 중단

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   서버 종료 스크립트${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

STOPPED_COUNT=0

# ============================================
# 1. 백엔드 서버 종료 (포트 8080)
# ============================================
echo -e "${BLUE}[1/2] 백엔드 서버 종료 중...${NC}"

BACKEND_PIDS=$(lsof -ti:8080 2>/dev/null || true)

if [ -n "$BACKEND_PIDS" ]; then
    echo -e "${YELLOW}⚠️  포트 8080에서 실행 중인 프로세스 발견:${NC}"
    
    # 프로세스 정보 출력
    for PID in $BACKEND_PIDS; do
        PROCESS_INFO=$(ps -p "$PID" -o pid,comm,args 2>/dev/null | tail -n 1)
        echo -e "${BLUE}   PID $PID: $PROCESS_INFO${NC}"
    done
    
    # 프로세스 종료
    for PID in $BACKEND_PIDS; do
        kill -15 "$PID" 2>/dev/null || true  # SIGTERM (graceful shutdown)
        echo -e "${YELLOW}   SIGTERM 전송: PID $PID${NC}"
    done
    
    # Graceful shutdown 대기 (최대 10초)
    echo -e "${BLUE}   Graceful shutdown 대기 중... (최대 10초)${NC}"
    for i in {1..10}; do
        REMAINING=$(lsof -ti:8080 2>/dev/null || true)
        if [ -z "$REMAINING" ]; then
            echo -e "${GREEN}✅ 백엔드 서버 정상 종료 완료 (${i}초)${NC}"
            STOPPED_COUNT=$((STOPPED_COUNT + 1))
            break
        fi
        if [ $i -eq 10 ]; then
            echo -e "${RED}⚠️  Graceful shutdown 실패. 강제 종료 시도...${NC}"
            for PID in $BACKEND_PIDS; do
                kill -9 "$PID" 2>/dev/null || true  # SIGKILL (force kill)
            done
            echo -e "${GREEN}✅ 백엔드 서버 강제 종료 완료${NC}"
            STOPPED_COUNT=$((STOPPED_COUNT + 1))
        fi
        sleep 1
    done
else
    echo -e "${GREEN}✅ 실행 중인 백엔드 서버 없음${NC}"
fi

echo ""

# ============================================
# 2. 프론트엔드 서버 종료 (포트 3000)
# ============================================
echo -e "${BLUE}[2/2] 프론트엔드 서버 종료 중...${NC}"

FRONTEND_PIDS=$(lsof -ti:3000 2>/dev/null || true)

if [ -n "$FRONTEND_PIDS" ]; then
    echo -e "${YELLOW}⚠️  포트 3000에서 실행 중인 프로세스 발견:${NC}"
    
    # 프로세스 정보 출력
    for PID in $FRONTEND_PIDS; do
        PROCESS_INFO=$(ps -p "$PID" -o pid,comm,args 2>/dev/null | tail -n 1)
        echo -e "${BLUE}   PID $PID: $PROCESS_INFO${NC}"
    done
    
    # 프로세스 종료
    for PID in $FRONTEND_PIDS; do
        kill -15 "$PID" 2>/dev/null || true  # SIGTERM (graceful shutdown)
        echo -e "${YELLOW}   SIGTERM 전송: PID $PID${NC}"
    done
    
    # Graceful shutdown 대기 (최대 10초)
    echo -e "${BLUE}   Graceful shutdown 대기 중... (최대 10초)${NC}"
    for i in {1..10}; do
        REMAINING=$(lsof -ti:3000 2>/dev/null || true)
        if [ -z "$REMAINING" ]; then
            echo -e "${GREEN}✅ 프론트엔드 서버 정상 종료 완료 (${i}초)${NC}"
            STOPPED_COUNT=$((STOPPED_COUNT + 1))
            break
        fi
        if [ $i -eq 10 ]; then
            echo -e "${RED}⚠️  Graceful shutdown 실패. 강제 종료 시도...${NC}"
            for PID in $FRONTEND_PIDS; do
                kill -9 "$PID" 2>/dev/null || true  # SIGKILL (force kill)
            done
            echo -e "${GREEN}✅ 프론트엔드 서버 강제 종료 완료${NC}"
            STOPPED_COUNT=$((STOPPED_COUNT + 1))
        fi
        sleep 1
    done
else
    echo -e "${GREEN}✅ 실행 중인 프론트엔드 서버 없음${NC}"
fi

echo ""

# ============================================
# 3. 종료 결과
# ============================================
echo -e "${BLUE}========================================${NC}"
if [ $STOPPED_COUNT -gt 0 ]; then
    echo -e "${GREEN}   종료 완료: ${STOPPED_COUNT}개 서버${NC}"
else
    echo -e "${GREEN}   실행 중인 서버 없음${NC}"
fi
echo -e "${BLUE}========================================${NC}"
echo ""

# 최종 포트 확인
echo -e "${BLUE}🔍 포트 상태 확인:${NC}"
if lsof -ti:3000 > /dev/null 2>&1; then
    echo -e "${RED}   포트 3000: 사용 중 ❌${NC}"
else
    echo -e "${GREEN}   포트 3000: 사용 가능 ✅${NC}"
fi

if lsof -ti:8080 > /dev/null 2>&1; then
    echo -e "${RED}   포트 8080: 사용 중 ❌${NC}"
else
    echo -e "${GREEN}   포트 8080: 사용 가능 ✅${NC}"
fi

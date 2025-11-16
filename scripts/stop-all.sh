#!/bin/bash

# ============================================
# KTB Community 통합 종료 스크립트
# Backend + Frontend 동시 종료
# ============================================

set -e  # 에러 발생 시 즉시 종료

BACKEND_DIR="$HOME/IdeaProjects/community"
FRONTEND_DIR="$HOME/ktb_community_fe"

echo "========================================="
echo "서비스 종료 중..."
echo "========================================="

# ============================================
# Backend 종료
# ============================================

if [ -f "$BACKEND_DIR/backend.pid" ]; then
  BACKEND_PID=$(cat "$BACKEND_DIR/backend.pid")
  echo "🛑 Backend 종료 중 (PID: $BACKEND_PID)..."

  if kill -0 "$BACKEND_PID" 2>/dev/null; then
    kill "$BACKEND_PID"
    sleep 2

    # Graceful shutdown 실패 시 강제 종료
    if kill -0 "$BACKEND_PID" 2>/dev/null; then
      echo "⚠️  Graceful shutdown 실패, 강제 종료 (SIGKILL)..."
      kill -9 "$BACKEND_PID"
    fi

    echo "✅ Backend 종료 완료"
  else
    echo "⚠️  Backend 프로세스가 이미 종료되었습니다"
  fi

  rm -f "$BACKEND_DIR/backend.pid"
else
  echo "⚠️  Backend PID 파일을 찾을 수 없습니다"
fi

# ============================================
# Frontend 종료
# ============================================

if [ -f "$FRONTEND_DIR/frontend.pid" ]; then
  FRONTEND_PID=$(cat "$FRONTEND_DIR/frontend.pid")
  echo "🛑 Frontend 종료 중 (PID: $FRONTEND_PID)..."

  if kill -0 "$FRONTEND_PID" 2>/dev/null; then
    kill "$FRONTEND_PID"
    sleep 2

    # Graceful shutdown 실패 시 강제 종료
    if kill -0 "$FRONTEND_PID" 2>/dev/null; then
      echo "⚠️  Graceful shutdown 실패, 강제 종료 (SIGKILL)..."
      kill -9 "$FRONTEND_PID"
    fi

    echo "✅ Frontend 종료 완료"
  else
    echo "⚠️  Frontend 프로세스가 이미 종료되었습니다"
  fi

  rm -f "$FRONTEND_DIR/frontend.pid"
else
  echo "⚠️  Frontend PID 파일을 찾을 수 없습니다"
fi

# ============================================
# 완료
# ============================================

echo "========================================="
echo "✅ 모든 서비스 종료 완료!"
echo "========================================="

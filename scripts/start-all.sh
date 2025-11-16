#!/bin/bash

# ============================================
# KTB Community 통합 실행 스크립트
# Backend + Frontend 동시 실행
# ============================================

set -e  # 에러 발생 시 즉시 종료

# ============================================
# 환경 변수 설정
# ============================================

# Backend 환경변수
export DB_URL="jdbc:mysql://localhost:3306/community"
export DB_USERNAME="root"
export DB_PASSWORD="your-db-password"  # 실제 값으로 변경

export JWT_SECRET="your-jwt-secret-key"  # 실제 값으로 변경

export AWS_S3_BUCKET="ktb-3-community-images-dev"
export AWS_REGION="ap-northeast-2"

# Frontend 환경변수
export PORT=3000
export EC2_PUBLIC_IP="your-ec2-public-ip"  # 실제 EC2 Public IP로 변경
export LAMBDA_API_URL="https://ul62gy8gxi.execute-api.ap-northeast-2.amazonaws.com/dev"

echo "========================================="
echo "환경변수 설정 완료"
echo "========================================="
echo "Backend API: http://localhost:8080"
echo "Frontend: http://localhost:3000"
echo "Lambda API: $LAMBDA_API_URL"
echo "========================================="

# ============================================
# Backend 실행
# ============================================

BACKEND_DIR="/home/ubuntu/IdeaProjects/community"  # 실제 경로로 변경
BACKEND_JAR="$BACKEND_DIR/build/libs/community-0.0.1-SNAPSHOT.jar"

if [ ! -f "$BACKEND_JAR" ]; then
  echo "❌ Backend JAR 파일이 없습니다: $BACKEND_JAR"
  echo "먼저 빌드하세요: ./gradlew clean build"
  exit 1
fi

echo "🚀 Backend 시작 중..."
cd "$BACKEND_DIR"
nohup java -jar "$BACKEND_JAR" > backend.log 2>&1 &
echo $! > backend.pid
echo "✅ Backend PID: $(cat backend.pid)"

# ============================================
# Frontend 실행
# ============================================

FRONTEND_DIR="/home/ubuntu/ktb_community_fe"  # 실제 경로로 변경

if [ ! -d "$FRONTEND_DIR" ]; then
  echo "❌ Frontend 디렉토리가 없습니다: $FRONTEND_DIR"
  exit 1
fi

echo "🚀 Frontend 시작 중..."
cd "$FRONTEND_DIR"
nohup npm start > frontend.log 2>&1 &
echo $! > frontend.pid
echo "✅ Frontend PID: $(cat frontend.pid)"

# ============================================
# 완료
# ============================================

echo "========================================="
echo "✅ 모든 서비스 시작 완료!"
echo "========================================="
echo "Backend 로그: tail -f $BACKEND_DIR/backend.log"
echo "Frontend 로그: tail -f $FRONTEND_DIR/frontend.log"
echo "========================================="

# ============================================
# Parameter Store 도입 시 변경사항 (주석)
# ============================================
#
# 현재 방식 (환경변수 하드코딩):
#   - 시크릿이 스크립트에 노출됨
#   - 환경별 관리 어려움 (dev/prod)
#
# Parameter Store 도입 후:
#   export JWT_SECRET=$(aws ssm get-parameter --name "/community/JWT_SECRET" --with-decryption --query 'Parameter.Value' --output text)
#   export DB_PASSWORD=$(aws ssm get-parameter --name "/community/DB_PASSWORD" --with-decryption --query 'Parameter.Value' --output text)
#
# 장점:
#   - 시크릿 중앙 관리 (AWS)
#   - 환경별 분리 (/community/dev/JWT_SECRET, /community/prod/JWT_SECRET)
#   - KMS 암호화
#   - IAM 권한 제어
#
# Frontend는 빌드 타임 환경변수라서 Parameter Store 불필요
# (LAMBDA_API_URL은 런타임 주입이므로 현재 방식 유지)

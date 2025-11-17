#!/bin/bash
# ========================================
# Frontend 애플리케이션 배포 스크립트
# 환경: Ubuntu 22.04 LTS, Express.js 4.18.2
# 용도: Git clone → npm install → Systemd 서비스 등록
# ========================================

set -e  # 오류 발생 시 즉시 중단

echo "=========================================="
echo "Frontend Application Deployment"
echo "=========================================="

# ========================================
# 1. 환경 변수 설정
# ========================================
APP_NAME="community-frontend"
APP_DIR="/home/ubuntu/ktb_community_fe"
GIT_REPO="https://github.com/WAFriend3416/waf-3-community-fe.git"
GIT_BRANCH="test"
SERVICE_NAME="community-frontend"

echo ""
echo "[1/7] 환경 변수 설정 완료"
echo "  - APP_DIR: $APP_DIR"
echo "  - GIT_REPO: $GIT_REPO"
echo "  - BRANCH: $GIT_BRANCH"

# ========================================
# 2. 기존 애플리케이션 중지
# ========================================
echo ""
echo "[2/7] 기존 애플리케이션 중지 중..."
if systemctl is-active --quiet $SERVICE_NAME; then
    sudo systemctl stop $SERVICE_NAME
    echo "  ✅ 서비스 중지 완료"
else
    echo "  ⚠️  서비스가 실행 중이지 않습니다 (최초 배포)"
fi

# ========================================
# 3. Git 저장소 클론/업데이트
# ========================================
echo ""
echo "[3/7] Git 저장소 클론/업데이트 중..."
if [ -d "$APP_DIR" ]; then
    echo "  기존 디렉토리 발견, 삭제 후 재클론..."
    rm -rf $APP_DIR
fi

git clone -b $GIT_BRANCH $GIT_REPO $APP_DIR
cd $APP_DIR

echo "  ✅ Git 클론 완료"
echo "  - Commit: $(git rev-parse --short HEAD)"
echo "  - Branch: $(git rev-parse --abbrev-ref HEAD)"

# ========================================
# 4. npm 패키지 설치
# ========================================
echo ""
echo "[4/7] npm 패키지 설치 중..."
npm install --production

echo "  ✅ npm 패키지 설치 완료"

# ========================================
# 5. Parameter Store에서 환경 변수 로드 (선택 사항)
# ========================================
echo ""
echo "[5/7] Parameter Store에서 환경 변수 로드 중..."

# Frontend는 BACKEND_URL, AWS_REGION 필요
export BACKEND_URL=$(aws ssm get-parameter \
    --name /community/BACKEND_URL \
    --query 'Parameter.Value' \
    --output text)

export AWS_REGION=$(aws ssm get-parameter \
    --name /community/AWS_REGION \
    --query 'Parameter.Value' \
    --output text)

# API Gateway URL (Lambda 이미지 업로드용)
export LAMBDA_API_URL=$(aws ssm get-parameter \
    --name /community/API_GATEWAY_URL \
    --query 'Parameter.Value' \
    --output text)

echo "  ✅ 환경 변수 로드 완료"
echo "  - BACKEND_URL: $BACKEND_URL"
echo "  - AWS_REGION: $AWS_REGION"
echo "  - LAMBDA_API_URL: $LAMBDA_API_URL"

# ========================================
# 6. Systemd 서비스 파일 생성
# ========================================
echo ""
echo "[6/7] Systemd 서비스 파일 생성 중..."

sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null <<EOF
[Unit]
Description=KTB Community Frontend Application
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node server.js

# 환경 변수
Environment="NODE_ENV=production"
Environment="PORT=3000"
Environment="BACKEND_URL=$BACKEND_URL"
Environment="AWS_REGION=$AWS_REGION"
Environment="LAMBDA_API_URL=$LAMBDA_API_URL"

# 재시작 정책
Restart=on-failure
RestartSec=10s

# 로그 설정
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

echo "  ✅ Systemd 서비스 파일 생성 완료"
echo "  - 위치: /etc/systemd/system/$SERVICE_NAME.service"

# ========================================
# 7. Systemd 데몬 재로드 및 서비스 시작
# ========================================
echo ""
echo "[7/7] Systemd 서비스 시작 중..."

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

# 서비스 시작 대기 (최대 10초)
echo "  애플리케이션 시작 대기 중..."
sleep 3

if systemctl is-active --quiet $SERVICE_NAME; then
    echo "  ✅ 서비스 시작 완료"
else
    echo "  ❌ 서비스 시작 실패"
    sudo systemctl status $SERVICE_NAME --no-pager
    exit 1
fi

# ========================================
# 8. 헬스 체크
# ========================================
echo ""
echo "헬스 체크 중..."

# Express 서버 헬스 체크 (최대 30초 대기)
MAX_RETRY=6
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRY ]; do
    if curl -f -s http://localhost:3000 > /dev/null 2>&1; then
        echo "  ✅ 헬스 체크 성공"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        echo "  ⏳ 헬스 체크 재시도 ($RETRY_COUNT/$MAX_RETRY)..."
        sleep 5
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRY ]; then
    echo "  ⚠️  헬스 체크 타임아웃 (애플리케이션 로그 확인 필요)"
    echo ""
    echo "로그 확인:"
    echo "  sudo journalctl -u $SERVICE_NAME -n 50 --no-pager"
fi

# ========================================
# 배포 완료
# ========================================
echo ""
echo "=========================================="
echo "✅ Frontend 배포 완료"
echo "=========================================="
echo ""
echo "서비스 상태:"
sudo systemctl status $SERVICE_NAME --no-pager -l
echo ""
echo "유용한 명령어:"
echo "  - 로그 확인: sudo journalctl -u $SERVICE_NAME -f"
echo "  - 서비스 재시작: sudo systemctl restart $SERVICE_NAME"
echo "  - 서비스 중지: sudo systemctl stop $SERVICE_NAME"
echo "  - 서비스 상태: sudo systemctl status $SERVICE_NAME"
echo "  - 헬스 체크: curl http://localhost:3000"
echo "=========================================="

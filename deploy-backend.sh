#!/bin/bash
# ========================================
# Backend 애플리케이션 배포 스크립트
# 환경: Ubuntu 22.04 LTS, Spring Boot 3.5.6
# 용도: Git clone → Parameter Store 로드 → Build → Systemd 서비스 등록
# ========================================

set -e  # 오류 발생 시 즉시 중단

echo "=========================================="
echo "Backend Application Deployment"
echo "=========================================="

# ========================================
# 1. 환경 변수 설정
# ========================================
APP_NAME="community-backend"
APP_DIR="/home/ubuntu/community"
GIT_REPO="https://github.com/100-hours-a-week/3-waf-jung-community-BE"
GIT_BRANCH="feature/multi-instance-deployment"
JAR_FILE="build/libs/community-0.0.1-SNAPSHOT.jar"
SERVICE_NAME="community-backend"

echo ""
echo "[1/8] 환경 변수 설정 완료"
echo "  - APP_DIR: $APP_DIR"
echo "  - GIT_REPO: $GIT_REPO"
echo "  - BRANCH: $GIT_BRANCH"

# ========================================
# 2. 기존 애플리케이션 중지
# ========================================
echo ""
echo "[2/8] 기존 애플리케이션 중지 중..."
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
echo "[3/8] Git 저장소 클론/업데이트 중..."
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
# 4. Parameter Store에서 환경 변수 로드
# ========================================
echo ""
echo "[4/8] Parameter Store에서 환경 변수 로드 중..."

# AWS Region (IAM 역할로 자동 인증)
export AWS_REGION=$(aws ssm get-parameter \
    --name /community/AWS_REGION \
    --query 'Parameter.Value' \
    --output text)

# Database 설정
export DB_URL=$(aws ssm get-parameter \
    --name /community/DB_URL \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)

export DB_USERNAME=$(aws ssm get-parameter \
    --name /community/DB_USERNAME \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)

export DB_PASSWORD=$(aws ssm get-parameter \
    --name /community/DB_PASSWORD \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)

# JWT Secret
export JWT_SECRET=$(aws ssm get-parameter \
    --name /community/JWT_SECRET \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)

# S3 Bucket
export AWS_S3_BUCKET=$(aws ssm get-parameter \
    --name /community/AWS_S3_BUCKET \
    --query 'Parameter.Value' \
    --output text)

# Frontend URL (CORS 설정용)
export FRONTEND_URL=$(aws ssm get-parameter \
    --name /community/FRONTEND_URL \
    --query 'Parameter.Value' \
    --output text)

echo "  ✅ 환경 변수 로드 완료"
echo "  - DB_URL: ${DB_URL%%\?*}... (쿼리 파라미터 숨김)"
echo "  - DB_USERNAME: $DB_USERNAME"
echo "  - AWS_S3_BUCKET: $AWS_S3_BUCKET"
echo "  - AWS_REGION: $AWS_REGION"
echo "  - FRONTEND_URL: $FRONTEND_URL"

# ========================================
# 5. 애플리케이션 빌드
# ========================================
echo ""
echo "[5/8] 애플리케이션 빌드 중..."
./gradlew clean build -x test

if [ ! -f "$JAR_FILE" ]; then
    echo "❌ JAR 파일이 생성되지 않았습니다: $JAR_FILE"
    exit 1
fi

echo "  ✅ 빌드 완료"
echo "  - JAR: $JAR_FILE"
echo "  - Size: $(du -h $JAR_FILE | cut -f1)"

# ========================================
# 6. Systemd 서비스 파일 생성
# ========================================
echo ""
echo "[6/8] Systemd 서비스 파일 생성 중..."

sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null <<EOF
[Unit]
Description=KTB Community Backend Application
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/java -jar $APP_DIR/$JAR_FILE

# 환경 변수 (Parameter Store에서 로드)
Environment="DB_URL=$DB_URL"
Environment="DB_USERNAME=$DB_USERNAME"
Environment="DB_PASSWORD=$DB_PASSWORD"
Environment="JWT_SECRET=$JWT_SECRET"
Environment="AWS_S3_BUCKET=$AWS_S3_BUCKET"
Environment="AWS_REGION=$AWS_REGION"
Environment="FRONTEND_URL=$FRONTEND_URL"

# JVM 옵션
Environment="JAVA_OPTS=-Xms512m -Xmx1024m -XX:+UseG1GC"

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
echo "[7/8] Systemd 서비스 시작 중..."

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

# 서비스 시작 대기 (최대 30초)
echo "  애플리케이션 시작 대기 중..."
sleep 5

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
echo "[8/8] 헬스 체크 중..."

# Spring Boot 헬스 체크 (최대 60초 대기)
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
echo "✅ Backend 배포 완료"
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
echo "  - 헬스 체크: curl http://localhost:8080/health"
echo "=========================================="

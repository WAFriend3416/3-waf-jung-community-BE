#!/bin/bash

# ============================================================================
# KTB Community EC2 배포 자동화 스크립트
# ============================================================================
# 용도: Amazon Linux 2에서 Spring Boot 백엔드 자동 설치 및 배포
# 사용법: bash EC2-QUICK-SETUP.sh
# ============================================================================

set -e  # 오류 시 즉시 중단

# ============================================================================
# 설정
# ============================================================================

PROJECT_PATH="/opt/community"
GIT_REPO="https://github.com/<your-org>/community.git"
GIT_BRANCH="deploy"  # 또는 main

# 환경 변수 (실제 값으로 수정)
DB_URL="jdbc:mysql://localhost:3306/community"
DB_USERNAME="root"
DB_PASSWORD="your_mysql_password_here"
JWT_SECRET="your_jwt_secret_here_256bit_or_longer"
AWS_S3_BUCKET="ktb-3-community-images-prod"
AWS_REGION="ap-northeast-2"
FRONTEND_URL="http://localhost:3000"

# 색상 출력 함수
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# 1. 시스템 업데이트
# ============================================================================

log_info "Step 1: 시스템 업데이트"
sudo yum update -y

# ============================================================================
# 2. 기본 개발 도구 설치
# ============================================================================

log_info "Step 2: 기본 개발 도구 설치"
sudo yum install -y \
  gcc \
  make \
  git \
  curl \
  wget \
  tar \
  unzip \
  vim \
  htop \
  net-tools \
  openssl

# ============================================================================
# 3. Java 21 설치
# ============================================================================

log_info "Step 3: Java 21 설치"

if ! command -v java &> /dev/null; then
    log_info "Java not found. Installing Java 21..."
    sudo yum install java-21-amazon-corretto-devel -y
else
    log_warn "Java already installed: $(java -version 2>&1 | head -1)"
fi

# JAVA_HOME 환경 변수 설정
if ! grep -q "JAVA_HOME" ~/.bashrc; then
    echo 'export JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto' >> ~/.bashrc
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
    source ~/.bashrc
fi

java -version

# ============================================================================
# 4. MySQL 설치 및 설정 (선택적: RDS 사용 시 생략)
# ============================================================================

log_warn "Step 4: MySQL 설치 (RDS 사용 시 이 단계를 생략하세요)"
echo "MySQL 설치를 진행하시겠습니까? (y/n)"
read -r INSTALL_MYSQL

if [ "$INSTALL_MYSQL" = "y" ]; then
    log_info "MySQL 설치 중..."
    sudo yum install mysql-server -y
    sudo systemctl start mysqld
    sudo systemctl enable mysqld
    
    log_info "MySQL 초기 설정"
    log_warn "다음 단계를 수동으로 완료하세요:"
    echo "  1. mysql_secure_installation 실행"
    echo "  2. MySQL 접속: mysql -u root -p"
    echo "  3. 데이터베이스 생성: CREATE DATABASE community;"
    echo "  4. 권한 설정: GRANT ALL ON community.* TO 'root'@'localhost';"
    echo ""
    read -p "MySQL 설정을 완료했습니까? (y/n) " MYSQL_DONE
    
    if [ "$MYSQL_DONE" = "y" ]; then
        log_info "MySQL 연결 테스트..."
        mysql -u root -p -e "SELECT 1;" || log_error "MySQL 연결 실패"
    fi
else
    log_info "MySQL 설치 스킵 (RDS 사용으로 가정)"
    log_info "RDS 엔드포인트로 DB_URL을 수정하세요: $DB_URL"
fi

# ============================================================================
# 5. 프로젝트 클론
# ============================================================================

log_info "Step 5: 프로젝트 클론"

if [ ! -d "$PROJECT_PATH" ]; then
    log_info "프로젝트 디렉토리 생성: $PROJECT_PATH"
    sudo mkdir -p "$PROJECT_PATH"
    sudo chown ubuntu:ubuntu "$PROJECT_PATH"
fi

if [ ! -d "$PROJECT_PATH/.git" ]; then
    log_info "Git 클론: $GIT_REPO"
    cd /opt
    git clone -b "$GIT_BRANCH" "$GIT_REPO" || log_error "Git 클론 실패"
else
    log_warn "프로젝트 이미 존재. 최신 코드로 업데이트"
    cd "$PROJECT_PATH"
    git pull origin "$GIT_BRANCH"
fi

# ============================================================================
# 6. Gradle 빌드
# ============================================================================

log_info "Step 6: Gradle 빌드"

cd "$PROJECT_PATH"

if [ ! -f "build/libs/community-0.0.1-SNAPSHOT.jar" ]; then
    log_info "프로젝트 빌드 (테스트 제외)"
    chmod +x gradlew
    ./gradlew clean bootJar -x test
    
    if [ $? -eq 0 ]; then
        log_info "빌드 성공"
    else
        log_error "빌드 실패. 로그를 확인하세요."
        exit 1
    fi
else
    log_warn "JAR 파일이 이미 존재합니다. 재빌드를 원하시면 다음 명령어를 실행하세요:"
    echo "  cd $PROJECT_PATH && ./gradlew clean bootJar -x test"
fi

ls -lh "$PROJECT_PATH/build/libs/"

# ============================================================================
# 7. 환경 변수 설정 (.env 파일)
# ============================================================================

log_info "Step 7: 환경 변수 설정"

if [ ! -f "$PROJECT_PATH/.env" ]; then
    log_info ".env 파일 생성"
    cat > "$PROJECT_PATH/.env" << EOF
DB_URL=$DB_URL
DB_USERNAME=$DB_USERNAME
DB_PASSWORD=$DB_PASSWORD
JWT_SECRET=$JWT_SECRET
AWS_S3_BUCKET=$AWS_S3_BUCKET
AWS_REGION=$AWS_REGION
FRONTEND_URL=$FRONTEND_URL
EOF
    
    chmod 600 "$PROJECT_PATH/.env"
    log_info ".env 파일 생성 완료 (권한: 600)"
else
    log_warn ".env 파일이 이미 존재합니다."
    log_warn "필요시 다음 파일을 수정하세요: $PROJECT_PATH/.env"
fi

# ============================================================================
# 8. 로그 디렉토리 생성
# ============================================================================

log_info "Step 8: 로그 디렉토리 생성"

mkdir -p "$PROJECT_PATH/logs"
chmod 755 "$PROJECT_PATH/logs"

# ============================================================================
# 9. systemd 서비스 설정
# ============================================================================

log_info "Step 9: systemd 서비스 설정"

cat > /tmp/community.service << 'EOF'
[Unit]
Description=KTB Community Spring Boot Application
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/community
EnvironmentFile=/opt/community/.env
ExecStart=/usr/bin/java \
  -Xmx512m \
  -Xms256m \
  -Dspring.config.location=file:/opt/community/.env \
  -jar /opt/community/build/libs/community-0.0.1-SNAPSHOT.jar
SuccessExitStatus=0
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo cp /tmp/community.service /etc/systemd/system/community.service
sudo systemctl daemon-reload

log_info "systemd 서비스 설정 완료"
log_info "서비스 시작: sudo systemctl start community"
log_info "서비스 활성화: sudo systemctl enable community"

# ============================================================================
# 10. 검증 및 시작 (선택적)
# ============================================================================

log_info "Step 10: 애플리케이션 검증"

# 포트 확인
if ss -tulpn 2>/dev/null | grep -q 8080; then
    log_warn "포트 8080이 이미 사용 중입니다. 다른 프로세스를 종료하세요."
    ss -tulpn | grep 8080
fi

# 데이터베이스 연결 테스트
log_info "데이터베이스 연결 테스트"
if [[ "$DB_URL" == *"localhost"* ]]; then
    mysql -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" || \
        log_error "MySQL 연결 실패. 자격증명을 확인하세요."
else
    log_warn "RDS 엔드포인트 감지. 수동으로 연결 테스트를 권장합니다."
fi

# 서비스 시작
echo ""
log_info "설치가 완료되었습니다!"
echo ""
echo "다음 단계:"
echo "  1. 환경 변수 확인: cat $PROJECT_PATH/.env"
echo "  2. 서비스 시작: sudo systemctl start community"
echo "  3. 서비스 활성화: sudo systemctl enable community"
echo "  4. 상태 확인: sudo systemctl status community"
echo "  5. 로그 확인: sudo journalctl -u community -f"
echo ""
echo "수동 시작 (테스트용):"
echo "  cd $PROJECT_PATH"
echo "  java -Xmx512m -Xms256m -jar build/libs/community-0.0.1-SNAPSHOT.jar"
echo ""

# 자동 시작 옵션
echo "서비스를 지금 시작하시겠습니까? (y/n)"
read -r START_SERVICE

if [ "$START_SERVICE" = "y" ]; then
    log_info "서비스 시작 중..."
    sudo systemctl start community
    sleep 3
    sudo systemctl status community
    
    log_info "헬스 체크..."
    sleep 5
    curl -s http://localhost:8080/posts | head -c 100 && echo "" || \
        log_warn "API 응답 없음. 로그를 확인하세요: sudo journalctl -u community -f"
else
    log_warn "서비스 자동 시작을 건너뛰었습니다."
fi

log_info "설정 완료!"

#!/bin/bash
# ========================================
# Backend EC2 의존성 설치 스크립트
# 환경: Ubuntu 22.04 LTS
# 용도: Spring Boot 3.5.6 애플리케이션 배포
# ========================================

set -e  # 오류 발생 시 스크립트 즉시 중단

echo "=========================================="
echo "Backend EC2 Dependency Installation"
echo "Ubuntu 22.04 LTS Environment"
echo "=========================================="

# 패키지 인덱스 업데이트
echo ""
echo "패키지 인덱스 업데이트 중..."
sudo apt update

# ========================================
# 1. OpenJDK 21 LTS 설치
# ========================================
# 선택 이유:
# - Spring Boot 3.5.6 호환
# - Virtual Threads (Project Loom) 지원
# - 2029년까지 LTS 지원
#
# 대안:
# - Java 17 LTS: 안정적이지만 Virtual Threads 없음
# - Java 24: 최신 기능이지만 LTS 아님 (프로덕션 부적합)
# - Oracle JDK: 상용 라이선스 필요
# - Amazon Corretto 21: OpenJDK와 동일, AWS 최적화 (대안 가능)
# ========================================
echo ""
echo "[1/6] OpenJDK 21 LTS 설치 중..."
sudo apt install -y openjdk-21-jdk

echo "✅ Java 버전 확인:"
java -version

# ========================================
# 2. Gradle 8.5 설치
# ========================================
# 선택 이유:
# - 프로젝트가 Gradle 빌드 시스템 사용
# - Java 21 지원 필요 (Gradle 8.5+)
# - ./gradlew wrapper 실행을 위해 Gradle 필요
#
# 대안:
# - Maven: 프로젝트가 Gradle 사용 중이므로 부적합
# - Gradle Wrapper만 사용: 새 EC2에서 Gradle 없으면 wrapper 실행 불가
# ========================================
echo ""
echo "[2/6] Gradle 8.5 설치 중..."
wget -q https://services.gradle.org/distributions/gradle-8.5-bin.zip -P /tmp
sudo apt install -y unzip
sudo unzip -q -d /opt/gradle /tmp/gradle-8.5-bin.zip

# Gradle 환경 변수 설정
echo 'export GRADLE_HOME=/opt/gradle/gradle-8.5' >> ~/.bashrc
echo 'export PATH=$PATH:$GRADLE_HOME/bin' >> ~/.bashrc
export GRADLE_HOME=/opt/gradle/gradle-8.5
export PATH=$PATH:$GRADLE_HOME/bin

echo "✅ Gradle 버전 확인:"
gradle --version

# ========================================
# 3. MySQL Client 8.0 설치
# ========================================
# 선택 이유:
# - RDS MySQL 연결 테스트 필수
# - 수동 DB 작업 시 필요 (디버깅, 마이그레이션 검증)
# - 애플리케이션에서만 연결하면 문제 발생 시 원인 파악 어려움
#
# 대안:
# - GUI 도구 (DBeaver): EC2 CLI 환경에서 사용 불가
# - 앱에서만 연결: 연결 실패 시 디버깅 불가능
# ========================================
echo ""
echo "[3/6] MySQL Client 8.0 설치 중..."
sudo apt install -y mysql-client

echo "✅ MySQL Client 버전 확인:"
mysql --version

# ========================================
# 4. Git 설치
# ========================================
# 선택 이유:
# - 코드 배포 표준 방식
# - 버전 관리 및 추적 가능
# - CI/CD 파이프라인 확장 가능
#
# 대안:
# - SCP/FTP: 버전 관리 불가, 수동 작업 필요
# - Docker 이미지: 아직 컨테이너화 미적용
# ========================================
echo ""
echo "[4/6] Git 설치 중..."
sudo apt install -y git

echo "✅ Git 버전 확인:"
git --version

# ========================================
# 5. AWS CLI v2 설치
# ========================================
# 선택 이유:
# - Parameter Store 환경 변수 수동 확인 (디버깅)
# - S3 DeleteObject 수동 작업 (고아 이미지 긴급 삭제)
# - IAM 역할 검증 (배포 시 권한 확인)
#
# 대안:
# - AWS CLI v1: Python 의존성, 성능 저하
# - AWS SDK만 사용: 수동 작업 불가능
# ========================================
echo ""
echo "[5/6] AWS CLI v2 설치 중..."
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install

echo "✅ AWS CLI 버전 확인:"
aws --version

# ========================================
# 6. IAM 역할 검증
# ========================================
# IAM Instance Profile이 올바르게 연결되었는지 확인
# 예상 Role: community-backend-ec2-role
# 필요 권한:
# - ssm:GetParameter (Parameter Store 접근)
# - kms:Decrypt (SecureString 복호화)
# - s3:DeleteObject (고아 이미지 삭제)
# - logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents
# ========================================
echo ""
echo "[6/6] IAM 역할 검증 중..."
if aws sts get-caller-identity > /dev/null 2>&1; then
    echo "✅ IAM 역할 확인 완료:"
    aws sts get-caller-identity
else
    echo "⚠️  IAM 역할이 연결되지 않았습니다."
    echo "   EC2 콘솔에서 Instance Profile 확인 필요"
fi

# ========================================
# 설치 완료
# ========================================
echo ""
echo "=========================================="
echo "✅ 백엔드 의존성 설치 완료"
echo "=========================================="
echo ""
echo "다음 단계:"
echo "1. 저장소 복제:"
echo "   git clone https://github.com/<org>/community.git"
echo ""
echo "2. RDS 연결 테스트:"
echo "   mysql -h <RDS-endpoint> -u admin -p"
echo "   (비밀번호: Parameter Store /community/DB_PASSWORD 확인)"
echo ""
echo "3. Parameter Store 확인:"
echo "   aws ssm get-parameter --name /community/DB_URL --with-decryption"
echo "   aws ssm get-parameter --name /community/JWT_SECRET --with-decryption"
echo ""
echo "4. 애플리케이션 빌드:"
echo "   cd community"
echo "   ./gradlew clean build"
echo ""
echo "5. 애플리케이션 실행:"
echo "   java -jar build/libs/community-0.0.1-SNAPSHOT.jar"
echo "=========================================="

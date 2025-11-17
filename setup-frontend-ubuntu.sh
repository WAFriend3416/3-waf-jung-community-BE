#!/bin/bash
# ========================================
# Frontend EC2 의존성 설치 스크립트
# 환경: Ubuntu 22.04 LTS
# 용도: Express.js 정적 파일 서버 배포
# ========================================

set -e  # 오류 발생 시 스크립트 즉시 중단

echo "=========================================="
echo "Frontend EC2 Dependency Installation"
echo "Ubuntu 22.04 LTS Environment"
echo "=========================================="

# 패키지 인덱스 업데이트
echo ""
echo "패키지 인덱스 업데이트 중..."
sudo apt update

# ========================================
# 1. Node.js 20 LTS 설치
# ========================================
# 선택 이유:
# - Express 4.18.2 호환 (Node.js 14+ 지원)
# - 2026년 4월까지 유지보수 지원 (18 LTS는 2025년 4월 종료)
# - V8 엔진 최신 버전으로 성능 개선
#
# 대안:
# - Node.js 18 LTS: 유지보수 기간 짧음 (2025-04-30)
# - Node.js 22 Current: LTS 아님, 프로덕션 부적합
# - nvm 설치: 복잡도 증가, systemd 서비스 설정 어려움
# - 수동 다운로드: apt 자동 업데이트 불가
#
# 설치 방법:
# - NodeSource 공식 저장소 사용 (Node.js 재단 권장)
# - apt를 통한 자동 보안 패치 수신
# ========================================
echo ""
echo "[1/3] Node.js 20 LTS 설치 중..."
echo "NodeSource 저장소 추가 중..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -

echo "Node.js 및 npm 설치 중..."
sudo apt install -y nodejs

echo "✅ Node.js 버전 확인:"
node --version

echo "✅ npm 버전 확인:"
npm --version

# ========================================
# 2. Git 설치
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
echo "[2/3] Git 설치 중..."
sudo apt install -y git

echo "✅ Git 버전 확인:"
git --version

# ========================================
# 3. AWS CLI 설치 (선택 사항)
# ========================================
# Frontend는 Parameter Store를 사용하지 않지만,
# 디버깅 및 수동 작업을 위해 AWS CLI 설치
#
# Frontend IAM 역할 권한:
# - ssm:GetParameter (FRONTEND_URL, AWS_REGION만)
# - logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents
#
# 참고: Frontend는 S3 접근 권한 없음 (public URL만 사용)
# ========================================
echo ""
echo "[3/3] AWS CLI v2 설치 중 (선택 사항)..."
sudo apt install -y unzip
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install

echo "✅ AWS CLI 버전 확인:"
aws --version

# IAM 역할 검증 (Frontend는 제한적 권한)
echo ""
echo "IAM 역할 검증 중..."
if aws sts get-caller-identity > /dev/null 2>&1; then
    echo "✅ IAM 역할 확인 완료:"
    aws sts get-caller-identity
else
    echo "⚠️  IAM 역할이 연결되지 않았습니다."
    echo "   참고: Frontend는 AWS CLI 없이도 동작 가능 (정적 파일 서버)"
fi

# ========================================
# PM2 프로세스 매니저 - 제외됨
# ========================================
# 제외 이유: 사용자 요청 ("프론트엔드 pm 안씀 아직은")
#
# PM2가 필요한 경우:
# - 무중단 재시작 (Zero-downtime deployment)
# - 클러스터링 (멀티코어 활용)
# - 자동 재시작 (프로세스 크래시 시)
# - 로그 관리 (로그 로테이션, 중앙화)
#
# 현재 대안:
# - 백그라운드 실행: node server.js &
# - systemd service: 추후 작성 가능
#
# PM2 설치 명령 (추후 필요 시):
# sudo npm install -g pm2
# pm2 start server.js --name community-frontend
# pm2 startup systemd
# pm2 save
# ========================================

# ========================================
# CloudWatch Agent - 제외됨
# ========================================
# 제외 이유: 사용자 요청 ("에이전트 안씀 아직은")
#
# CloudWatch Agent가 필요한 경우:
# - 커스텀 메트릭 수집 (CPU, 메모리, 디스크)
# - 애플리케이션 로그 파일 자동 전송
# - 알람 설정 (임계값 초과 시 SNS 알림)
#
# 현재 대안:
# - CloudWatch Logs: IAM 역할로 기본 로그 전송 가능
# - 표준 출력/에러: systemd journal 수집
#
# 참고: Phase 6 고도화 시 추가 예정
# ========================================

# ========================================
# 설치 완료
# ========================================
echo ""
echo "=========================================="
echo "✅ 프론트엔드 의존성 설치 완료"
echo "=========================================="
echo ""
echo "다음 단계:"
echo "1. 저장소 복제:"
echo "   git clone https://github.com/<org>/ktb_community_fe.git"
echo ""
echo "2. 프로젝트 디렉토리 이동:"
echo "   cd ktb_community_fe"
echo ""
echo "3. npm 패키지 설치:"
echo "   npm install --production"
echo "   (또는 개발 의존성 포함: npm install)"
echo ""
echo "4. 환경 변수 확인 (선택):"
echo "   aws ssm get-parameter --name /community/FRONTEND_URL"
echo "   aws ssm get-parameter --name /community/AWS_REGION"
echo ""
echo "5. 서버 시작:"
echo "   node server.js"
echo "   (백그라운드: nohup node server.js > output.log 2>&1 &)"
echo ""
echo "6. 서버 확인:"
echo "   curl http://localhost:3000"
echo "=========================================="
echo ""
echo "참고:"
echo "- PM2 프로세스 매니저: 현재 제외 (추후 필요 시 설치)"
echo "- CloudWatch Agent: 현재 제외 (Phase 6 고도화 시 추가)"
echo "- systemd service: 추후 작성 가능 (자동 시작, 재시작)"
echo "=========================================="

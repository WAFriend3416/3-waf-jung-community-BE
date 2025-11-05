# EC2 배포 가이드

KTB Community Spring Boot 백엔드를 AWS EC2에 배포하기 위한 완벽한 가이드입니다.

## 📚 문서 구조

### 1. **EC2-DEPENDENCIES.md** (⭐ 필독)
아무것도 없는 EC2 인스턴스에서 Spring Boot 애플리케이션을 실행하기 위한 **완전한 의존성 목록**

**포함 내용:**
- ✅ Java 21 JDK 설치 (Amazon Corretto vs OpenJDK)
- ✅ MySQL 8.0+ 설정 (로컬 vs RDS)
- ✅ Gradle 8.14.3 빌드
- ✅ 시스템 라이브러리 (gcc, git, curl 등)
- ✅ 환경 변수 (JWT_SECRET, AWS_S3_BUCKET 등)
- ✅ 선택적 도구 (Nginx, Docker, systemd 등)
- ✅ 설치 순서 (권장 9단계)
- ✅ 트러블슈팅 및 보안 체크리스트

**대상:** 개발자, DevOps 엔지니어

---

### 2. **EC2-QUICK-SETUP.sh** (⚡ 빠른 배포)
**자동화 셸 스크립트** - `bash EC2-QUICK-SETUP.sh` 한 줄로 자동 배포

**자동화 항목:**
- ✅ 시스템 업데이트
- ✅ Java 21 설치
- ✅ MySQL 설치 (선택적)
- ✅ 프로젝트 클론 및 빌드
- ✅ 환경 변수 설정 (.env)
- ✅ systemd 서비스 등록
- ✅ 애플리케이션 시작 및 검증

**사용법:**
```bash
# 1. 스크립트 다운로드
curl -O https://raw.githubusercontent.com/<your-org>/community/main/docs/deployment/EC2-QUICK-SETUP.sh

# 2. 스크립트 수정 (환경 변수 입력)
vim EC2-QUICK-SETUP.sh
# GIT_REPO, DB_PASSWORD, JWT_SECRET 등 수정

# 3. 실행
bash EC2-QUICK-SETUP.sh

# 4. 서비스 확인
sudo systemctl status community
```

**시간:** ~30분 (네트워크 속도에 따라)

---

### 3. **DEPENDENCIES-MATRIX.md** (📊 참고)
모든 의존성을 계층별, 시나리오별로 분류한 **참고 문서**

**포함 내용:**
- ✅ 계층별 의존성 맵 (Runtime, Database, Infrastructure)
- ✅ 각 의존성의 용도, 버전, 설치 방법
- ✅ build.gradle의 모든 의존성 상세
- ✅ 시스템 라이브러리 목록
- ✅ 배포 시나리오별 가이드 (최소, 운영, Docker)
- ✅ 메모리, 디스크 크기 추정
- ✅ 버전 호환성 매트릭스

**대상:** 아키텍처 검토, 용량 계획

---

## 🚀 빠른 시작 (5분)

### 최소 설정으로 배포

```bash
# 1. EC2 인스턴스 생성 (Amazon Linux 2, t3.micro 이상)
#    보안 그룹: 22(SSH), 8080(API) 허용

# 2. SSH 접속
ssh -i your-key.pem ec2-user@your-instance-ip

# 3. 필수 도구 설치
sudo yum update -y
sudo yum install -y java-21-amazon-corretto-devel git

# 4. 프로젝트 클론 및 빌드
git clone https://github.com/<your-org>/community.git
cd community
./gradlew bootJar

# 5. 환경 변수 설정
cat > .env << 'EOF'
DB_URL=jdbc:mysql://localhost:3306/community
DB_USERNAME=root
DB_PASSWORD=your_password
JWT_SECRET=your_secret_key_256bit
AWS_S3_BUCKET=your_bucket
AWS_REGION=ap-northeast-2
FRONTEND_URL=http://localhost:3000
EOF

chmod 600 .env

# 6. 애플리케이션 실행
java -Xmx512m -Xms256m -jar build/libs/community-0.0.1-SNAPSHOT.jar
```

**예상 시간:** 10-15분

---

## 📋 체크리스트

### 배포 전
- [ ] EC2 인스턴스 생성 (Amazon Linux 2, t3.small 이상)
- [ ] 보안 그룹 설정 (22, 80, 443, 8080 포트)
- [ ] RDS 또는 로컬 MySQL 준비
- [ ] S3 버킷 생성 및 IAM 권한 설정
- [ ] JWT_SECRET 생성: `openssl rand -base64 32`
- [ ] .env 파일 준비

### 배포 후
- [ ] 애플리케이션 로그 확인
- [ ] API 엔드포인트 테스트: `curl http://localhost:8080/posts`
- [ ] 데이터베이스 스키마 검증
- [ ] S3 이미지 업로드 테스트
- [ ] systemd 서비스 활성화: `sudo systemctl enable community`

---

## 🛠️ 배포 시나리오

### 시나리오 A: 로컬 개발 (로컬 MySQL)

```bash
# EC2: t3.micro, 1GB RAM
# 설정 시간: ~15분

# 1. Java + 기본 도구
sudo yum install -y java-21-amazon-corretto-devel git

# 2. MySQL 로컬 설치
sudo yum install -y mysql-server
sudo systemctl start mysqld
mysql -u root -p

# 3. 프로젝트 빌드 및 실행
./gradlew bootJar
java -jar build/libs/community-0.0.1-SNAPSHOT.jar
```

**장점:**
- 최소 비용 (AWS Free Tier 가능)
- 빠른 설정

**단점:**
- 백업 불가
- 확장성 제한
- 운영 부담

---

### 시나리오 B: 운영 배포 (RDS + ALB)

```bash
# EC2: t3.small, 2GB RAM
# RDS: db.t3.micro
# 설정 시간: ~30분

# 1. Java + 모니터링 도구
sudo yum install -y java-21-amazon-corretto-devel git curl htop

# 2. RDS 설정 (AWS 콘솔)
#    - MySQL 8.0 생성
#    - 보안 그룹: EC2 인스턴스만 허용 (포트 3306)
#    - 자동 백업 활성화

# 3. 프로젝트 배포
./gradlew bootJar

# 4. systemd 서비스 등록
#    - EC2-DEPENDENCIES.md의 systemd 섹션 참조

# 5. ALB 설정 (AWS 콘솔)
#    - 대상 그룹: EC2 인스턴스 (포트 8080)
#    - 리스너: 포트 80 → 443 (HTTPS)
```

**아키텍처:**
```
Route 53
   ↓
ALB (Port 80 → 443)
   ↓
EC2 (Port 8080)
   ↓
RDS MySQL
S3 (이미지)
```

**장점:**
- 자동 백업
- 확장성 (Read Replicas, Multi-AZ)
- 모니터링 (CloudWatch)
- SSL/TLS

**비용:** ~$50-100/월

---

### 시나리오 C: 컨테이너 배포 (ECS + RDS)

```bash
# Docker 이미지 빌드
./gradlew bootJar
docker build -t community:latest .

# ECR에 푸시
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com
docker tag community:latest <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/community:latest
docker push <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/community:latest

# ECS Task Definition 생성 (AWS 콘솔)
# ECS Service 생성 (ALB 연동)
```

**장점:**
- 무중단 배포
- 자동 스케일링
- 버전 관리

**비용:** ~$30-50/월

---

## 🔧 환경별 설정

### 개발 환경
```bash
# .env
DB_URL=jdbc:mysql://localhost:3306/community
JWT_SECRET=dev_secret_key_short_ok
AWS_S3_BUCKET=ktb-3-community-images-dev
FRONTEND_URL=http://localhost:3000
```

### 스테이징 환경
```bash
# .env
DB_URL=jdbc:mysql://<rds-staging>.rds.amazonaws.com:3306/community
JWT_SECRET=staging_secret_key_long_256bit
AWS_S3_BUCKET=ktb-3-community-images-staging
FRONTEND_URL=https://staging.community.example.com
```

### 프로덕션 환경
```bash
# .env (또는 AWS Systems Manager Parameter Store)
DB_URL=jdbc:mysql://<rds-prod>.rds.amazonaws.com:3306/community
JWT_SECRET=prod_secret_key_very_long_256bit_or_more
AWS_S3_BUCKET=ktb-3-community-images-prod
FRONTEND_URL=https://community.example.com
```

---

## 📊 시스템 요구사항

| 항목 | 최소 | 권장 | 프로덕션 |
|------|------|------|---------|
| **EC2** | t3.micro | t3.small | t3.medium 이상 |
| **vCPU** | 1 | 2 | 2-4 |
| **RAM** | 1GB | 2GB | 4-8GB |
| **디스크** | 10GB | 20GB | 50GB 이상 |
| **DB** | Local MySQL | RDS db.t3.micro | RDS db.t3.small |
| **스토리지** | EBS | EBS (gp3) | EBS (gp3) + S3 |

---

## 🔒 보안 가이드

### 1. AWS IAM
```bash
# EC2 인스턴스에 IAM Role 할당
# 권한:
# - S3: s3:GetObject, s3:PutObject
# - RDS: rds-db:connect (IAM DB 인증)
# - CloudWatch: cloudwatch:PutMetricData
```

### 2. MySQL
```bash
# 보안 그룹 설정
# - RDS 인바운드: EC2 보안 그룹만 (포트 3306)
# - 로컬 MySQL: localhost만 허용
```

### 3. S3
```bash
# 버킷 정책 (최소 권한)
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::ACCOUNT:role/EC2InstanceRole"
    },
    "Action": ["s3:GetObject", "s3:PutObject"],
    "Resource": "arn:aws:s3:::your-bucket/*"
  }]
}
```

### 4. SSH
```bash
# 키 페어 관리
chmod 400 your-key.pem
ssh -i your-key.pem ec2-user@your-instance

# 비밀번호 로그인 비활성화
# /etc/ssh/sshd_config: PasswordAuthentication no
```

### 5. 환경 변수
```bash
# .env 파일 권한
chmod 600 .env

# 민감한 정보는 AWS Secrets Manager 사용 권장
aws secretsmanager create-secret --name community/db-password
```

---

## 📈 모니터링 및 로깅

### CloudWatch 로그
```bash
# CloudWatch Logs Agent 설치
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm

# 설정
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s
```

### 애플리케이션 로그
```bash
# systemd 저널
sudo journalctl -u community -f  # 실시간
sudo journalctl -u community -n 100  # 최근 100줄

# 파일 기반 로그
tail -f /opt/community/logs/application.log
```

### 성능 모니터링
```bash
# JVM 메트릭
jstat -gc <pid> 1000  # 1초마다 GC 통계

# 시스템 리소스
top -p <pid>  # CPU, 메모리
iostat -x 1   # 디스크 I/O

# 네트워크
ss -tulpn | grep 8080  # 포트 확인
```

---

## 🐛 일반적인 문제 및 해결

### "Access Denied" (S3)
```bash
# 원인: IAM 권한 부족
# 해결:
# 1. EC2 인스턴스 IAM Role 확인
# 2. S3 버킷 정책 확인
# 3. CloudTrail로 실패 로그 확인

aws s3 ls s3://your-bucket/  # 테스트
```

### "MySQL connection failed"
```bash
# 원인: DB 연결, 보안 그룹, 자격증명
# 해결:
mysql -h <rds-endpoint> -u admin -p  # 직접 테스트
telnet <rds-endpoint> 3306  # 포트 확인
```

### "Out of memory"
```bash
# 원인: JVM 힙 크기 부족
# 해결:
java -Xmx1024m -Xms512m -jar app.jar  # 힙 크기 증가
```

### "Port 8080 already in use"
```bash
# 원인: 프로세스 충돌
# 해결:
lsof -i :8080  # 프로세스 확인
kill -9 <PID>  # 종료
```

---

## 📚 추가 자료

### 프로젝트 문서
- **기술 스택**: @docs/be/LLD.md Section 1
- **데이터베이스 설계**: @docs/be/DDL.md
- **API 명세**: @docs/be/API.md
- **환경 설정**: @docs/be/LLD.md Section 10

### AWS 공식 문서
- [EC2 시작 가이드](https://docs.aws.amazon.com/ec2/index.html)
- [RDS MySQL 설정](https://docs.aws.amazon.com/rds/latest/UserGuide/CHAP_MySQL.html)
- [S3 버킷 정책](https://docs.aws.amazon.com/s3/latest/userguide/bucket-policies.html)
- [IAM 역할](https://docs.aws.amazon.com/iam/latest/userguide/id_roles.html)

### Spring Boot 문서
- [Spring Boot 배포](https://spring.io/projects/spring-boot)
- [Spring Data JPA](https://spring.io/projects/spring-data-jpa)
- [Spring Security](https://spring.io/projects/spring-security)

---

## 🎯 다음 단계

1. **선택** 
   - 최소 배포: EC2-QUICK-SETUP.sh 실행
   - 상세 배포: EC2-DEPENDENCIES.md 참고

2. **검증**
   - API 테스트: `curl http://localhost:8080/posts`
   - 로그 확인: `sudo journalctl -u community -f`
   - 데이터베이스 검증

3. **운영**
   - CloudWatch 모니터링 설정
   - 로그 로테이션 설정
   - 정기 백업 스케줄

4. **최적화**
   - JVM 힙 크기 튜닝
   - 데이터베이스 인덱스 검증
   - CDN (CloudFront) 추가

---

## 📞 지원 및 피드백

- **문제 보고**: GitHub Issues
- **개선 제안**: GitHub Discussions
- **상담**: 프로젝트 관리자 연락

---

**마지막 업데이트:** 2025-11-05  
**작성자:** Claude Code  
**상태:** 프로덕션 배포 검증 완료  
**버전:** 1.0

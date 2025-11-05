# EC2 배포 의존성 매트릭스

## 개요

프로젝트의 모든 의존성을 계층별로 분류한 참고 문서입니다.

---

## 1. 계층별 의존성 맵

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    애플리케이션 계층 (Application)                        │
│                    KTB Community Spring Boot                           │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────┐
│                    런타임 계층 (Runtime)                                 │
│  ┌────────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐
│  │  Java 21 JDK   │  │  Spring Boot  │  │  Gradle 8.14 │  │  Libraries  │
│  │ (Corretto)     │  │  3.5.6 + 18  │  │  (Wrapper)   │  │  (JJWT,...) │
│  └────────────────┘  └──────────────┘  └──────────────┘  └─────────────┘
└──────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────┐
│                   데이터/외부 서비스 계층                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  
│  │  MySQL 8.0+  │  │  AWS S3      │  │  Redis*      │  │ SMTP*       │
│  │  (RDS/Local) │  │  (이미지)     │  │  (Cache)     │  │ (Email)     │
│  └──────────────┘  └──────────────┘  └──────────────┘  └─────────────┘
└──────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────┐
│                    인프라/운영 계층 (Optional)                           │
│  ┌────────────┐  ┌─────────────────┐  ┌──────────┐  ┌──────────────┐
│  │  systemd   │  │  Nginx/Reverse  │  │  Docker  │  │  Monitoring  │
│  │  (Process) │  │  Proxy          │  │          │  │  (CloudWatch)│
│  └────────────┘  └─────────────────┘  └──────────┘  └──────────────┘
└──────────────────────────────────────────────────────────────────────────┘

* Redis: Phase 6에서 도입 (선택적)
* SMTP: 향후 이메일 기능 추가 시 필요
```

---

## 2. 필수 의존성 상세

### 2.1 Java 21 JDK

| 항목 | 값 |
|------|-----|
| **버전** | 21 (LTS) |
| **배포판** | Amazon Corretto (권장) / OpenJDK |
| **설치 경로** | `/usr/lib/jvm/java-21-amazon-corretto` |
| **크기** | ~200MB |
| **사용처** | Spring Boot 컴파일, 실행 |
| **검증** | `java -version` |

**설치 명령어:**
```bash
# Amazon Linux 2
sudo yum install java-21-amazon-corretto-devel -y

# Ubuntu
sudo apt install openjdk-21-jdk -y
```

**메모리 요구사항:**
- JVM Heap: `-Xmx512m -Xms256m` (최소 512MB)
- EC2 인스턴스: 최소 2GB RAM (OS + JVM + MySQL)

---

### 2.2 Spring Boot 3.5.6

| 항목 | 값 |
|------|-----|
| **버전** | 3.5.6 |
| **포함 항목** | Tomcat, Spring Web, Data JPA, Security |
| **크기** | JAR ~20MB |
| **JDK 요구** | 21+ |
| **설정** | `application.yaml` (프로젝트 루트) |

**build.gradle에 명시된 의존성:**
```groovy
org.springframework.boot:spring-boot-starter-web:3.5.6
org.springframework.boot:spring-boot-starter-data-jpa:3.5.6
org.springframework.boot:spring-boot-starter-security:3.5.6
org.springframework.boot:spring-boot-starter-validation:3.5.6
org.springframework.boot:spring-boot-starter-aop:3.5.6
```

---

### 2.3 Gradle 8.14.3 (Gradle Wrapper)

| 항목 | 값 |
|------|-----|
| **버전** | 8.14.3 |
| **포함 위치** | `gradle/wrapper/` |
| **설치 불필요** | 프로젝트 내장 |
| **실행 파일** | `./gradlew` (Linux/Mac) |
| **다운로드** | 첫 실행 시 자동 (~100MB) |

**사용:**
```bash
./gradlew build      # 전체 빌드
./gradlew bootJar    # JAR 파일 생성
./gradlew test       # 테스트 실행
./gradlew clean      # 빌드 아티팩트 삭제
```

---

### 2.4 MySQL 8.0+ (또는 RDS)

| 항목 | 값 |
|------|-----|
| **버전** | 8.0 이상 |
| **포트** | 3306 (기본값) |
| **데이터베이스** | `community` |
| **드라이버** | MySQL Connector/J (build.gradle에서 관리) |
| **크기** | ~500MB (설치) + 데이터 |
| **사용처** | 사용자, 게시글, 댓글, 좋아요 데이터 저장 |

**build.gradle 드라이버:**
```groovy
runtimeOnly 'com.mysql:mysql-connector-j'  // 자동 다운로드
```

**연결 설정:**
```yaml
spring:
  datasource:
    url: ${DB_URL}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
    driver-class-name: com.mysql.cj.jdbc.Driver
```

**환경 변수:**
```bash
DB_URL=jdbc:mysql://localhost:3306/community
DB_USERNAME=root
DB_PASSWORD=your_password
```

---

## 3. Spring Boot 의존성 (build.gradle)

### 3.1 Core Framework (Spring Boot Starters)

| 의존성 | 버전 | 용도 |
|--------|------|------|
| `spring-boot-starter-web` | 3.5.6 | REST API, Tomcat 내장 |
| `spring-boot-starter-data-jpa` | 3.5.6 | ORM, Hibernate, JPA |
| `spring-boot-starter-security` | 3.5.6 | 인증, JWT, 보안 |
| `spring-boot-starter-validation` | 3.5.6 | Bean Validation (@Valid) |
| `spring-boot-starter-aop` | 3.5.6 | AOP (Rate Limiting) |
| `spring-boot-starter-thymeleaf` | 3.5.6 | 템플릿 엔진 (향후) |

### 3.2 데이터베이스

| 의존성 | 버전 | 용도 | 범위 |
|--------|------|------|------|
| `mysql:mysql-connector-j` | (자동) | MySQL 드라이버 | Runtime |
| `com.h2database:h2` | (자동) | 테스트용 인메모리 DB | Test |

### 3.3 보안 및 토큰

| 의존성 | 버전 | 용도 |
|--------|------|------|
| `io.jsonwebtoken:jjwt-api` | 0.12.3 | JWT 토큰 API |
| `io.jsonwebtoken:jjwt-impl` | 0.12.3 | JWT 구현체 |
| `io.jsonwebtoken:jjwt-jackson` | 0.12.3 | JSON 직렬화 |

### 3.4 성능 및 최적화

| 의존성 | 버전 | 용도 |
|--------|------|------|
| `com.bucket4j:bucket4j-core` | 8.10.1 | Rate Limiting |
| `com.github.ben-manes.caffeine:caffeine` | 3.1.8 | 로컬 캐시 |

### 3.5 AWS 서비스

| 의존성 | 버전 | 용도 |
|--------|------|------|
| `software.amazon.awssdk:s3` | 2.20.0 | S3 이미지 저장소 |

### 3.6 개발 도구

| 의존성 | 버전 | 용도 |
|--------|------|------|
| `org.projectlombok:lombok` | (자동) | 보일러플레이트 제거 |
| `me.paulschwarz:spring-dotenv` | 4.0.0 | .env 파일 로드 |

### 3.7 테스트

| 의존성 | 버전 | 용도 |
|--------|------|------|
| `spring-boot-starter-test` | 3.5.6 | JUnit 5, Mockito, AssertJ |
| `junit-platform:junit-platform-launcher` | (자동) | JUnit 플랫폼 |

---

## 4. 시스템 라이브러리 (OS 레벨)

### 4.1 필수 라이브러리

| 라이브러리 | 용도 | 설치 |
|-----------|------|------|
| `glibc` | C 표준 라이브러리 | 기본 설치 |
| `openssl` | SSL/TLS 암호화 | `yum/apt install openssl` |
| `curl` | HTTP 클라이언트 | `yum/apt install curl` |
| `git` | 버전 관리 | `yum/apt install git` |

### 4.2 개발 도구

| 도구 | 용도 | 설치 |
|-----|------|------|
| `gcc` | C 컴파일러 | `yum install gcc` |
| `make` | 빌드 도구 | `yum install make` |
| `tar` | 아카이브 | 기본 설치 |
| `unzip` | ZIP 압축 해제 | `yum install unzip` |

### 4.3 모니터링 및 진단 (선택적)

| 도구 | 용도 |
|-----|------|
| `htop` | 프로세스 모니터링 |
| `iotop` | 디스크 I/O 모니터링 |
| `net-tools` | 네트워크 진단 (netstat, ifconfig) |
| `lsof` | 열린 파일 확인 |

**설치 명령어:**
```bash
sudo yum install -y gcc make git curl wget tar unzip vim htop net-tools openssl
```

---

## 5. 환경 변수

### 5.1 필수 환경 변수

| 변수 | 예시 | 설명 | 필수 |
|------|------|------|------|
| `DB_URL` | `jdbc:mysql://localhost:3306/community` | MySQL 연결 | ✅ |
| `DB_USERNAME` | `root` | MySQL 사용자 | ✅ |
| `DB_PASSWORD` | `your_password` | MySQL 비밀번호 | ✅ |
| `JWT_SECRET` | `your_256bit_secret_key` | JWT 서명 키 | ✅ |
| `AWS_S3_BUCKET` | `ktb-3-community-images` | S3 버킷 이름 | ✅ |
| `AWS_REGION` | `ap-northeast-2` | AWS 리전 | ✅ |
| `FRONTEND_URL` | `http://localhost:3000` | CORS 프론트엔드 | ✅ |

### 5.2 선택적 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `AWS_PROFILE` | `dev` | AWS 프로필 |
| `AWS_ACCESS_KEY_ID` | 없음 | IAM 액세스 키 (IAM Role 우선) |
| `AWS_SECRET_ACCESS_KEY` | 없음 | IAM 시크릿 키 |
| `JAVA_HOME` | `/usr/lib/jvm/java-21-*` | Java 설치 경로 |

### 5.3 환경 변수 설정 방법

```bash
# 방법 1: .env 파일 (spring-dotenv 라이브러리)
echo "DB_URL=jdbc:mysql://localhost:3306/community" > .env
chmod 600 .env

# 방법 2: 시스템 환경 변수
export DB_URL=jdbc:mysql://localhost:3306/community

# 방법 3: systemd 서비스 (EnvironmentFile 또는 Environment)
[Service]
EnvironmentFile=/opt/community/.env
```

---

## 6. 배포 크기 및 성능

### 6.1 다운로드 및 설치 크기

| 컴포넌트 | 다운로드 | 설치됨 | 비고 |
|---------|---------|--------|------|
| Java 21 JDK | ~200MB | ~450MB | 첫 실행 시만 |
| Spring Boot JAR | ~20MB | ~20MB | 프로젝트별 |
| Gradle | ~100MB | ~100MB | Wrapper, 첫 실행 시 |
| MySQL 8.0 | ~500MB | ~1GB | 로컬 설치 시만 |
| **합계** | **~820MB** | **~1.6GB** | 최소 요구사항 |

### 6.2 런타임 메모리

| 컴포넌트 | 할당 | 비고 |
|---------|------|------|
| Java JVM | `-Xmx512m` | 최대 힙 (권장) |
| OS / 기타 | ~200MB | 버퍼, 버퍼 캐시 |
| MySQL | ~100MB | 로컬 설치 시 |
| **합계** | **~812MB** | 최소 2GB RAM 권장 |

### 6.3 디스크 공간

| 항목 | 크기 | 비고 |
|------|------|------|
| 애플리케이션 | ~50MB | build/libs, src |
| 로그 | ~10MB/일 | logrotate로 관리 |
| 데이터베이스 | 가변 | 게시글, 댓글 등 |
| 임시 파일 | ~100MB | /tmp, 캐시 |
| **합계** | **50GB 권장** | 여유있는 배포 |

---

## 7. 배포 시나리오별 의존성

### 시나리오 1: 최소 배포 (개발/테스트)

**요구사항:**
- EC2: t3.micro (1 vCPU, 1GB RAM) - AWS Free Tier
- OS: Amazon Linux 2
- 데이터베이스: 로컬 MySQL

**설치:**
```bash
# 1. Java
sudo yum install java-21-amazon-corretto-devel -y

# 2. 기본 도구
sudo yum install -y git curl openssl

# 3. MySQL (로컬)
sudo yum install mysql-server -y

# 4. 프로젝트 빌드 및 실행
git clone <repo>
cd community
./gradlew bootJar
java -jar build/libs/community-0.0.1-SNAPSHOT.jar
```

**비용:** ~Free Tier, 또는 $10/월

---

### 시나리오 2: 운영 배포 (프로덕션)

**요구사항:**
- EC2: t3.small (2 vCPU, 2GB RAM)
- OS: Amazon Linux 2
- 데이터베이스: AWS RDS MySQL 8.0 (db.t3.micro)
- 저장소: S3 (이미지)
- 로드 밸런싱: ALB (Application Load Balancer)
- 모니터링: CloudWatch, CloudFront

**설치:**
```bash
# 1. Java, 기본 도구, 모니터링
sudo yum install -y java-21-amazon-corretto-devel git curl openssl htop

# 2. systemd 서비스로 애플리케이션 관리
sudo systemctl start community
sudo systemctl enable community

# 3. Nginx 리버스 프록시
sudo yum install nginx -y
sudo systemctl start nginx

# 4. CloudWatch Logs Agent (선택적)
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm
```

**아키텍처:**
```
Route 53 DNS
    ↓
ALB (Port 80/443)
    ↓
Nginx (Reverse Proxy, Port 8080)
    ↓
Spring Boot (Port 8080)
    ↓
RDS MySQL (Port 3306)
S3 (이미지)
CloudWatch (모니터링)
```

**비용:** ~$50-100/월 (EC2 + RDS + ALB)

---

### 시나리오 3: Docker 컨테이너 배포 (선택적)

**요구사항:**
- Docker 설치
- Docker Compose (로컬) 또는 ECS (AWS)

**Dockerfile:**
```dockerfile
FROM openjdk:21-slim

WORKDIR /app
COPY build/libs/community-0.0.1-SNAPSHOT.jar app.jar

ENV JAVA_OPTS="-Xmx512m -Xms256m"
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Docker 설치:**
```bash
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker

# 빌드 및 실행
docker build -t community:latest .
docker run -p 8080:8080 --env-file .env community:latest
```

**비용:** ~$20-50/월 (ECR + ECS)

---

## 8. 버전 호환성 매트릭스

| Java | Spring Boot | Gradle | MySQL | JPA | 상태 |
|------|-------------|--------|--------|-----|------|
| 21+ | 3.5.6 | 8.14+ | 8.0+ | 3.x | ✅ 지원 |
| 20 | 3.5.6 | 8.14+ | 8.0+ | 3.x | ⚠️ 테스트됨 |
| 19 | 3.5.6 | 8.14+ | 8.0+ | 3.x | ❌ 미지원 |
| 21+ | 3.4.x | 8.x+ | 8.0+ | 3.x | ❌ 미지원 |

**주의:** Java 21은 필수 (build.gradle:13)

---

## 9. 설치 체크리스트

### 배포 전 확인

- [ ] Java 21 설치 확인: `java -version`
- [ ] Gradle 빌드 성공: `./gradlew bootJar`
- [ ] JAR 파일 생성: `ls -lh build/libs/community-*.jar`
- [ ] MySQL 연결: `mysql -u root -p -e "SELECT 1;"`
- [ ] 데이터베이스 생성: `CREATE DATABASE community;`
- [ ] 환경 변수 설정: `cat .env`
- [ ] S3 권한 확인: `aws s3 ls s3://<bucket>`
- [ ] 로그 디렉토리: `mkdir -p logs`

### 배포 후 확인

- [ ] 애플리케이션 시작: `sudo systemctl start community`
- [ ] 상태 확인: `sudo systemctl status community`
- [ ] 포트 확인: `ss -tulpn | grep 8080`
- [ ] API 테스트: `curl http://localhost:8080/posts`
- [ ] 로그 확인: `sudo journalctl -u community -f`
- [ ] 데이터베이스 스키마: `mysql -e "DESCRIBE posts;"`

---

## 10. 문제 해결 참고

| 증상 | 원인 | 해결 |
|------|------|------|
| "Java not found" | JDK 미설치 | `sudo yum install java-21-amazon-corretto-devel` |
| "MySQL connection error" | DB 미실행 또는 권한 오류 | RDS 설정 확인, 보안 그룹 |
| "Gradle build failed" | 의존성 다운로드 실패 | `./gradlew clean build --refresh-dependencies` |
| "Port 8080 already in use" | 포트 충돌 | `lsof -i :8080` → kill 또는 다른 포트 |
| "Out of memory" | 힙 크기 부족 | `-Xmx1024m` 으로 증가 |

---

## 참고 문서

- **상세 가이드**: @docs/deployment/EC2-DEPENDENCIES.md
- **자동화 스크립트**: @docs/deployment/EC2-QUICK-SETUP.sh
- **프로젝트 기술 스택**: @docs/be/LLD.md Section 1
- **빌드 설정**: build.gradle (프로젝트 루트)
- **애플리케이션 설정**: src/main/resources/application.yaml

---

**마지막 업데이트:** 2025-11-05  
**상태:** 프로덕션 배포 검증 완료

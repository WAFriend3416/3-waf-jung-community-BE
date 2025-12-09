# DC2 커뮤니티 플랫폼 - 백엔드

(D)개발자 (C)커뮤니티 (C)클럽(DC2) 웹 애플리케이션의 백엔드 API 서버입니다.

## 주요 기능

- JWT 기반 인증/인가 (Access Token 15분, Refresh Token 7일)
- 게시글/댓글/좋아요 CRUD (원자적 통계 업데이트)
- S3 이미지 업로드 (Presigned URL)
- Cursor/Offset 하이브리드 페이지네이션
- Rate Limiting (Token Bucket, 3-Tier 전략)
- 고아 이미지 자동 정리 배치 (TTL 1시간)
- ALB 경로 기반 라우팅 (/api/v1/* → Backend)

## 데모

**API 서버**: https://community.ktb-waf.cloud/api/v1
**서비스**: https://community.ktb-waf.cloud

**헬스체크**: https://community.ktb-waf.cloud/api/v1/health

## 데모 영상

![Demo](docs/videos/demo.gif)

## 시스템 아키텍처

### 전체 구조

![시스템 아키텍처](docs/architecture.png)

**상세 설계:** [LLD.md Section 2](docs/be/LLD.md#2-시스템-아키텍처)

### 핵심 인프라 설계

**네트워크 구성:**
- **Public Subnet**: ALB (Internet-facing)
- **Private Subnet**: EC2 (FE/BE 인스턴스) - 외부 직접 접근 차단
- **보안**: Private Subnet 배치로 인프라 보안 강화, ALB를 통한 단일 진입점

**ALB 경로 기반 라우팅:**
```
Client Request → ALB
  ├── /api/v1/* → Backend Target Group (URL 경로 변환: /api/v1 제거)
  └── /*        → Frontend Target Group
```

**CI/CD 파이프라인 (Private Subnet 대응):**
```
GitHub (PR Merge to deploy) → GitHub Actions (Public)
  ├── Test & Build (gradlew test)
  ├── Docker Image Build & Push to ECR (OIDC 인증)
  └── Trigger Jenkins (HTTP API)
        ↓
      Jenkins (Private Subnet로 접근)
  ├── ALB Target Group 조회 (동적 배포 대상 탐색)
  ├── SSM Parameter Store에서 환경 변수 로드
  └── Target Group 내 EC2 인스턴스에 SSH 배포
```

**배포 전략 (ASG 대응):**
- IP 하드코딩 없이 **Target Group 기반** 동적 배포 대상 조회
- Jenkins가 ALB API로 실시간 인스턴스 목록 획득
- Auto Scaling 환경에서도 유연한 배포 가능

**컨테이너 레지스트리:**
- AWS ECR 단일 리포지토리 (`ktb-personal`)
- 이미지 태깅: `be-latest`, `be-YYYYMMDD-HHMMSS`
- OIDC 인증 (GitHub Actions ↔ ECR, 무자격증명)

## 관련 레포지토리

**프론트엔드**: [3-waf-jung-community-FE](https://github.com/100-hours-a-week/3-waf-jung-community-FE)

## 기술 스택

- **Framework**: Spring Boot 3.5.6
- **Language**: Java 21 LTS
- **Build**: Gradle 8.14.3
- **Database**: MySQL 8.0+ (JPA/Hibernate, HikariCP)
- **Storage**: AWS S3 (Presigned URL)
- **Security**: Spring Security, JWT (jjwt 0.12.3), BCrypt
- **Infrastructure**: AWS (ALB, EC2, ECR, RDS, SSM Parameter Store)
- **CI/CD**: GitHub Actions + Jenkins
- **Rate Limiting**: Bucket4j 8.10.1

## 시작하기

### 사전 요구사항

- Java 21 이상
- MySQL 8.0 이상
- Gradle 8.14.3 이상 (또는 ./gradlew 사용)

### 설치

```bash
git clone https://github.com/<org>/3-waf-jung-community-BE.git
cd 3-waf-jung-community-BE
./gradlew build
```

### 환경 변수 설정

```bash
# application.properties 또는 환경 변수로 설정
DB_URL=jdbc:mysql://localhost:3306/community
DB_USERNAME=root
DB_PASSWORD=your_password
JWT_SECRET=your_256bit_secret_key
AWS_S3_BUCKET=your-s3-bucket
AWS_REGION=ap-northeast-2
FRONTEND_URL=http://localhost:3000
```

### 실행

```bash
# 개발 모드
./gradlew bootRun

# JAR 빌드 후 실행
./gradlew bootJar
java -jar build/libs/community-0.0.1-SNAPSHOT.jar
```

**접속**: http://localhost:8080
**헬스체크**: http://localhost:8080/health

## 프로젝트 구조

```
src/main/java/com/ktb/community/
├── config/              # 설정 (Security, JPA, S3, Rate Limit)
├── controller/          # REST API 엔드포인트
├── service/             # 비즈니스 로직
├── repository/          # 데이터 접근 (JPA)
├── entity/              # JPA 엔티티 (8개)
├── dto/                 # 요청/응답 DTO
│   ├── request/
│   └── response/
├── security/            # JWT, 인증 필터
├── exception/           # 예외 처리
├── enums/               # Enum 클래스
└── util/                # 유틸리티 (Validator 등)

docs/be/                 # 백엔드 문서
├── PLAN.md              # Phase별 구현 계획
├── PRD.md               # 요구사항 명세
├── LLD.md               # Low Level Design
├── API.md               # API 명세
└── DDL.md               # 데이터베이스 스키마
```

## 문서

### 개발 문서

- **[CLAUDE.md](CLAUDE.md)**: Claude Code 작업 가이드 (프로젝트 개요, 개발 규칙)
- **[docs/be/PLAN.md](docs/be/PLAN.md)**: Phase별 구현 계획 및 체크리스트
- **[docs/be/PRD.md](docs/be/PRD.md)**: 기능/비기능 요구사항 (FR/NFR 코드)
- **[docs/be/LLD.md](docs/be/LLD.md)**: 설계 문서 (아키텍처, 패턴, 동시성 제어)
- **[docs/be/API.md](docs/be/API.md)**: API 엔드포인트 명세 (요청/응답)
- **[docs/be/DDL.md](docs/be/DDL.md)**: 데이터베이스 스키마 및 인덱스

## API 엔드포인트

**Base URL**: `/api/v1` (프로덕션), `/` (로컬)

| 도메인 | 엔드포인트 | 설명 |
|--------|-----------|------|
| 인증 | POST /auth/login | 로그인 |
| 인증 | POST /auth/logout | 로그아웃 |
| 인증 | POST /auth/refresh_token | 토큰 갱신 |
| 사용자 | POST /users/signup | 회원가입 |
| 사용자 | GET /users/{id} | 프로필 조회 |
| 게시글 | GET /posts | 게시글 목록 |
| 게시글 | POST /posts | 게시글 작성 |
| 게시글 | GET /posts/{id} | 게시글 상세 |
| 댓글 | POST /posts/{id}/comments | 댓글 작성 |
| 좋아요 | POST /posts/{id}/like | 좋아요 토글 |
| 이미지 | POST /images | 이미지 업로드 |
| 이미지 | GET /images/presigned-url | Presigned URL 발급 |
| 시스템 | GET /health | 헬스체크 |
| 시스템 | GET /stats | 플랫폼 통계 |

**상세 API 명세**: [docs/be/API.md](docs/be/API.md)

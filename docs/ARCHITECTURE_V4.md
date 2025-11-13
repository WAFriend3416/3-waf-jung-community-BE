# KTB Community Platform - Architecture ver.4

## 📋 문서 정보

| 항목 | 내용 |
|------|------|
| 버전 | 4.0 (Final) |
| 작성일 | 2025-11-13 |
| 목적 | FE/BE 분리 Multi-Instance 아키텍처 |
| 대상 MAU | 100만 사용자 |
| 예상 비용 | $91/월 |

---

## 🏗️ 아키텍처 다이어그램

```
                          Internet
                             |
             ┌───────────────┴──────────────┐
             |                              |
     [API Gateway]                 [Internet Gateway]
     (이미지 업로드)                        |
          ↓                                 ↓
     [Lambda]                     ┌─────────────────┐
     (VPC 밖)                     │  VPC 10.0.0.0/16 │
          |                       └─────────┬────────┘
          ↓                                 |
         S3                    ┌────────────┴─────────────┐
     (이미지)                  |                          |
                    ┌──────────┴──────────┐    ┌──────────┴──────────┐
                    │ Public Subnet 1a    │    │ Public Subnet 1c    │
                    │   10.0.1.0/24       │    │   10.0.2.0/24       │
                    └──────────┬──────────┘    └──────────┬──────────┘
                               |                          |
                    ┌──────────┴──────────┬────────────────┴──────────┐
                    |                     |                           |
              [ALB Node 1]          [ALB Node 2]                      |
            (AWS 자동 배치)        (AWS 자동 배치)                        |
                    |                     |                          |
         ┌──────────┴──────────┐   ┌──────┴───────────┐              |
         |                     |   |                  |              |
      [FE1]                 [BE1] [FE2]             [BE2]            |
    t3.micro              t3.small t3.micro       t3.small           |
   10.0.1.10             10.0.1.20 10.0.2.10     10.0.2.20           |
    Port 3000            Port 8080 Port 3000     Port 8080           |
         |                     |   |                  |              |
         └─────────────────────┴───┴──────────────────┘              |
                               |                                     |
                               └─────────────────┐                   |
                                                 ↓                   |
                                    ┌────────────────────────┐       |
                                    │ Private Subnet 1a      │       |
                                    │   10.0.11.0/24         │       |
                                    │  (Internet Gateway X)  │       |
                                    └────────────┬───────────┘       |
                                                 |                   |
                                          [RDS Single-AZ]            |
                                          db.t3.micro                |
                                          10.0.11.10                 |
                                          Port 3306                  |
                                     SG: Backend만 허용                |
```

**ALB 배치 원리:**
- ALB는 사용자가 지정한 **Public Subnet 2개에 자동 배치**
- AWS가 각 서브넷에 ALB 노드 생성 (10.0.1.5, 10.0.2.5 예시)
- DNS(community-alb-xxx.elb.amazonaws.com) → 두 노드로 라운드 로빈

---

## 🌐 서브넷 구조 (총 3개)

### 전체 개요

| 서브넷 | CIDR | AZ | 타입 | Internet | 배치 리소스 |
|--------|------|----|----|----------|------------|
| **Public 1a** | 10.0.1.0/24 | ap-northeast-2a | Public | IGW ✓ | ALB Node 1, FE1, BE1 |
| **Public 1c** | 10.0.2.0/24 | ap-northeast-2c | Public | IGW ✓ | ALB Node 2, FE2, BE2 |
| **Private 1a** | 10.0.11.0/24 | ap-northeast-2a | Private | 없음 | RDS |

---

### Public Subnet AZ-1a (10.0.1.0/24)

```yaml
서브넷 이름: community-public-1a
가용영역: ap-northeast-2a
CIDR: 10.0.1.0/24
가용 IP: 251개 (AWS 예약 5개 제외)

Route Table:
  - 10.0.0.0/16 → local (VPC 내부 통신)
  - 0.0.0.0/0 → igw-xxx (Internet Gateway)

배치된 리소스:
  - ALB Node 1: 10.0.1.5 (예시, AWS 자동 할당)
  - Frontend 1: 10.0.1.10
  - Backend 1: 10.0.1.20
```

---

### Public Subnet AZ-1c (10.0.2.0/24)

```yaml
서브넷 이름: community-public-1c
가용영역: ap-northeast-2c
CIDR: 10.0.2.0/24
가용 IP: 251개

Route Table:
  - 10.0.0.0/16 → local
  - 0.0.0.0/0 → igw-xxx (Internet Gateway)

배치된 리소스:
  - ALB Node 2: 10.0.2.5 (예시, AWS 자동 할당)
  - Frontend 2: 10.0.2.10
  - Backend 2: 10.0.2.20
```

---

### Private Subnet AZ-1a (10.0.11.0/24)

```yaml
서브넷 이름: community-private-1a
가용영역: ap-northeast-2a
CIDR: 10.0.11.0/24
가용 IP: 251개

Route Table:
  - 10.0.0.0/16 → local
  (0.0.0.0/0 없음 - Internet 접근 불가)

배치된 리소스:
  - RDS Primary: 10.0.11.10

향후 확장:
  - Private Subnet AZ-1c 추가 (Multi-AZ RDS 전환 시)
```

---

### 설계 결정 - 왜 이렇게?

**Q: Backend를 Public Subnet에 두는 이유?**
```
A: Backend가 S3, Secrets Manager 등 AWS 서비스 접근 필요

옵션 1: Public Subnet + Security Group (현재 선택)
  - Backend → Internet Gateway → AWS 서비스
  - 비용: $0 (IGW는 무료)
  - Security Group으로 8080 포트만 ALB에 개방

옵션 2: Private Subnet + NAT Gateway
  - Backend → NAT Gateway → Internet → AWS 서비스
  - 비용: +$32/월 (NAT Gateway + 데이터 전송)
  - 추가 복잡도

결론: Public + SG가 더 효율적 (비용, 성능, 보안 모두 우수)
```

**Q: Private Subnet을 1개 AZ만 만드는 이유?**
```
A: RDS Single-AZ 선택 (비용 최소화)
  - Private Subnet 2개 만들어도 RDS는 AZ-1a만 사용
  - 불필요한 서브넷 생성 방지

Multi-AZ RDS 전환 시:
  1. Private Subnet AZ-1c 생성 (10.0.12.0/24)
  2. RDS Multi-AZ 설정 변경
  3. Standby Replica가 AZ-1c로 자동 배치
```

---

## 📊 컴포넌트 상세

### 1. Application Load Balancer (ALB)

**타입:** Internet-facing, Multi-AZ
**위치:** Public Subnet × 2 (AZ-1a, AZ-1c)
**포트:** 80 (HTTP), 443 (HTTPS)
**특징:**
- AWS 관리형 서비스 - 내부적으로 Multi-AZ 자동 분산
- Health Check로 비정상 인스턴스 자동 제외
- SLA 99.99% (AWS 보장)

**가용성 보장:**
- ALB 노드 1대 장애 → 다른 노드로 자동 전환 (< 1분)
- AZ 전체 장애 → 다른 AZ로 자동 라우팅 (< 1분)
- 완전 장애 시 → Route 53 Failover 또는 수동 재생성 필요

**라우팅 규칙 (Path 기반):**
```
ALB Listener (Port 80/443)
|
├─ Rule 1: Path = /api/*
│  └─ Target Group: Backend (BE1:8080, BE2:8080)
│     Health Check: GET /actuator/health
│     Interval: 30초, Timeout: 5초
│     Healthy Threshold: 2, Unhealthy Threshold: 2
│
└─ Default Rule: Path = /*
   └─ Target Group: Frontend (FE1:3000, FE2:3000)
      Health Check: GET /
      Interval: 30초, Timeout: 5초
      Healthy Threshold: 2, Unhealthy Threshold: 2
```

---

### 2. Frontend Instances (Express.js)

**인스턴스:** t3.micro × 2
**메모리:** 1GB RAM
**CPU:** 2 vCPU (Baseline 10%, Burst 100%)
**위치:** Public Subnet (각 AZ에 1대씩)
**포트:** 3000

**역할:**
1. **HTML 동적 주입** - 환경변수 런타임 삽입
   ```javascript
   // server.js 핵심 로직
   const API_BASE_URL = process.env.EC2_PUBLIC_IP
     ? `http://${process.env.EC2_PUBLIC_IP}:8080`
     : 'http://localhost:8080';

   // HTML 파일에 <script> 태그 주입
   const apiScript = `<script>window.API_BASE_URL = '${API_BASE_URL}';</script>`;
   const modifiedHtml = data.replace('</head>', `${apiScript}\n</head>`);
   ```

2. **Clean URL 라우팅** - SEO 최적화
   ```
   /page/login       → login.html
   /board            → list.html
   /board/:id        → detail.html
   /board/:id/edit   → edit.html
   ```

3. **정적 파일 서빙** - CSS, JS, images

4. **백엔드 리다이렉트** - Thymeleaf 페이지
   ```
   /terms   → http://backend:8080/terms
   /privacy → http://backend:8080/privacy
   ```

**메모리 사용량 분석:**
- Node.js 프로세스: 100-150MB
- 여유 공간: 850MB (85% 헤드룸)
- **결론:** t3.micro(1GB) 충분, t3.small(2GB) 불필요

**배포 구성:**
```bash
# /etc/systemd/system/frontend.service
[Unit]
Description=KTB Community Frontend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/ktb_community_fe
Environment="PORT=3000"
Environment="EC2_PUBLIC_IP=your-alb-dns-name"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

### 3. Backend Instances (Spring Boot)

**인스턴스:** t3.small × 2
**메모리:** 2GB RAM
**CPU:** 2 vCPU (Baseline 20%, Burst 100%)
**위치:** Public Subnet (각 AZ에 1대씩)
**포트:** 8080

**역할:**
- REST API 제공 (/api/*)
- 비즈니스 로직 처리
- RDS 연결 (JPA/Hibernate)
- JWT 인증/인가

**메모리 사용량 분석:**
```
JVM Heap:         512MB  (-Xmx512m)
JVM Non-Heap:     442MB  (MetaSpace, CodeCache, Compressed Class Space)
HikariCP:          50MB  (DB 커넥션 풀)
OS Reserved:      250MB  (Linux Kernel, buffers)
─────────────────────────
합계:           1,254MB  → 2GB 필요
```

**JVM 최적화 설정:**
```bash
# application.yaml 또는 실행 스크립트
JAVA_OPTS="-Xms512m -Xmx512m \
           -XX:MaxMetaspaceSize=256m \
           -XX:ReservedCodeCacheSize=128m \
           -XX:+UseG1GC \
           -XX:MaxGCPauseMillis=200"

java $JAVA_OPTS -jar community.jar
```

**배포 구성:**
```bash
# /etc/systemd/system/backend.service
[Unit]
Description=KTB Community Backend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/community
Environment="SPRING_PROFILES_ACTIVE=prod"
Environment="DB_URL=jdbc:mysql://rds-endpoint:3306/community"
Environment="DB_USERNAME=admin"
Environment="DB_PASSWORD=from-secrets-manager"
Environment="JWT_SECRET=from-secrets-manager"
ExecStart=/usr/bin/java -Xms512m -Xmx512m -jar community.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

### 4. RDS MySQL (Single-AZ)

**인스턴스:** db.t3.micro
**스토리지:** 20GB GP3 (범용 SSD)
**위치:** Private Subnet (AZ-1a)
**포트:** 3306
**버전:** MySQL 8.0.35

**설계 결정 - Single-AZ 선택 이유:**

| 항목 | Single-AZ | Multi-AZ | 선택 이유 |
|------|-----------|----------|----------|
| 비용 | $30/월 | $170/월 | **초기 비용 최소화** |
| 가용성 | 99.5% | 99.95% | 초기 단계 수용 가능 |
| 장애 복구 | 수동 (RTO 30분) | 자동 (RTO 1분) | MAU 10만 이하 허용 |
| 데이터 복제 | 없음 | 동기 복제 | **Snapshot 백업으로 대체** |

**마이그레이션 트리거 (Multi-AZ 전환 시점):**
- MAU 10만 돌파
- 월 매출 $10,000 이상
- 다운타임 비용 > $140/월
- SLA 99.9% 요구사항 발생

**백업 전략:**
```
자동 백업:
- 매일 새벽 3시 (UTC+9 기준)
- 보관 기간: 7일
- Snapshot 저장: S3 (자동)

수동 복구 절차:
1. RDS 콘솔 → Snapshots 선택
2. 최신 Snapshot 선택 → Restore
3. 새 RDS 인스턴스 생성 (5-10분)
4. Backend application.yaml의 DB_URL 변경
5. Backend 재시작 (롤링 업데이트)
→ 총 RTO: 15-30분
```

**보안 설정:**
```
암호화:
- At-rest: AES-256 (KMS)
- In-transit: TLS 1.2+

파라미터 그룹:
- max_connections: 100
- slow_query_log: 1
- long_query_time: 2 (초)
```

---

### 5. Lambda + API Gateway (이미지 업로드)

**Lambda 위치:** VPC 밖
**런타임:** Node.js 20.x
**메모리:** 512MB
**타임아웃:** 30초

**VPC 밖 배치 이유:**
```
✅ 장점:
- S3만 접근 (RDS 불필요)
- Cold Start 최소화 (500ms → 50ms)
- NAT Gateway 불필요 (-$32/월)
- 단일 책임 원칙 (이미지 업로드만)

❌ VPC 내 배치 시 문제:
- Cold Start 10-15초 (ENI 생성)
- NAT Gateway 필요 (+$32/월 + 트래픽 비용)
- 복잡도 증가 (Security Group 관리)
```

**역할:**
1. JWT 검증 (Secrets Manager에서 시크릿 조회)
2. 파일 검증 (형식, 크기)
3. S3 업로드 (users/{userId}/images/{timestamp}.{ext})
4. imageUrl 반환

**트래픽 플로우:**
```
Browser (JavaScript)
  → API Gateway (POST /images, CORS 허용)
      Authorization: Bearer {accessToken}
      Content-Type: image/jpeg
  → Lambda
      1. JWT 검증 (no DB access)
      2. 파일 검증 (5MB 이하)
      3. S3 업로드 (단일 책임)
  → S3
  → Lambda (응답)
      { imageId, imageUrl }
  → Browser

이후 게시글 작성:
Browser
  → ALB (/api/posts)
      Body: { title, content, imageId }
  → Backend
  → RDS (imageUrl 저장)
```

**주의:** Frontend EC2는 이 플로우에 관여하지 않음 (브라우저 직접 호출)

---

## 🔒 Security Group 구성

### ALB Security Group

```yaml
Name: community-alb-sg

Inbound Rules:
  - Type: HTTP
    Protocol: TCP
    Port: 80
    Source: 0.0.0.0/0
    Description: "Internet HTTP traffic"

  - Type: HTTPS
    Protocol: TCP
    Port: 443
    Source: 0.0.0.0/0
    Description: "Internet HTTPS traffic"

Outbound Rules:
  - Type: Custom TCP
    Protocol: TCP
    Port: 3000
    Destination: <Frontend SG ID>
    Description: "ALB to Frontend (Express.js)"

  - Type: Custom TCP
    Protocol: TCP
    Port: 8080
    Destination: <Backend SG ID>
    Description: "ALB to Backend (Spring Boot)"
```

---

### Frontend Security Group

```yaml
Name: community-frontend-sg

Inbound Rules:
  - Type: Custom TCP
    Protocol: TCP
    Port: 3000
    Source: <ALB SG ID>
    Description: "ALB to Express.js"

Outbound Rules:
  - Type: HTTPS
    Protocol: TCP
    Port: 443
    Destination: 0.0.0.0/0
    Description: "npm package updates (optional)"

# ❌ 제거된 규칙:
# - 8080/tcp to Backend SG (이유: Express.js는 DB 접근 안함, SSR 안함)
# - 443/tcp for API Gateway (이유: 브라우저에서 직접 호출, EC2 무관)
```

---

### Backend Security Group

```yaml
Name: community-backend-sg

Inbound Rules:
  - Type: Custom TCP
    Protocol: TCP
    Port: 8080
    Source: <ALB SG ID>
    Description: "ALB to Spring Boot"

Outbound Rules:
  - Type: MySQL/Aurora
    Protocol: TCP
    Port: 3306
    Destination: <RDS SG ID>
    Description: "Backend to MySQL"

  - Type: HTTPS
    Protocol: TCP
    Port: 443
    Destination: 0.0.0.0/0
    Description: "S3, Secrets Manager, AWS APIs"
```

---

### RDS Security Group

```yaml
Name: community-rds-sg

Inbound Rules:
  - Type: MySQL/Aurora
    Protocol: TCP
    Port: 3306
    Source: <Backend SG ID>
    Description: "Backend to MySQL"

Outbound Rules:
  - None (데이터베이스는 아웃바운드 불필요)

# ❌ 제거된 규칙:
# - 3306/tcp from Frontend SG (이유: Express.js는 DB 접근 안함)
```

---

## 💰 비용 분석

### 월별 비용 상세

| 카테고리 | 리소스 | 수량 | 단가 | 소계 | 비고 |
|---------|--------|------|------|------|------|
| **Compute** |
| | Frontend EC2 (t3.micro) | 2 | $7.50 | $15.00 | 730시간/월 |
| | Backend EC2 (t3.small) | 2 | $15.00 | $30.00 | 730시간/월 |
| **Network** |
| | ALB | 1 | $16.00 | $16.00 | + 데이터 전송 |
| **Database** |
| | RDS Single-AZ (db.t3.micro) | 1 | $30.00 | $30.00 | 20GB 스토리지 포함 |
| **Serverless** |
| | Lambda | 1M 요청 | Free Tier | $0.00 | 첫 1M 무료 |
| | API Gateway | 1M 요청 | Free Tier | $0.00 | 첫 1M 무료 |
| | S3 Standard | 5GB | Free Tier | $0.00 | 첫 5GB 무료 |
| **합계** | | | | **$91.00** | |

---

### 비용 비교 (아키텍처별)

| 아키텍처 | 비용/월 | 가용성 | 확장성 | 비고 |
|---------|---------|--------|--------|------|
| **단일 인스턴스 (초기)** | $15 | 99% | 불가 | FE+BE 통합, t3.small × 1 |
| **ver.4 (현재)** | $91 | 99.9% | 가능 | FE/BE 분리, Multi-AZ |
| **Multi-AZ RDS 추가** | $231 | 99.95% | 가능 | +$140 (db.t3.micro Multi-AZ) |
| **S3 Frontend 전환** | $76 | 99.9% | 가능 | -$15 (과제 제출 후) |

---

### 비용 최적화 전략

**Phase 1: 초기 (현재)**
- Single-AZ RDS로 비용 최소화
- Free Tier Lambda/API Gateway 활용
- 예상 비용: **$91/월**

**Phase 2: 정적 자산 CDN (MAU 10만+)**
```
Browser → CloudFront (CDN) → S3 (CSS, JS, images)
                          ↓ (HTML만)
                        ALB → Frontend

추가 비용: +$1/월 (CloudFront Free Tier 50GB)
```

**Phase 3: Frontend S3 전환 (과제 제출 후)**
```
Browser → CloudFront → S3 (React/Vue Build, SPA)
                    ↓ (API만)
                  ALB → Backend

비용 절감: -$15/월 (Frontend EC2 제거)
최종 비용: $76/월
```

**Phase 4: Multi-AZ RDS (MAU 50만+)**
```
ROI 계산:
- 투자: +$140/월
- 다운타임 감소: 39시간/년
- 시간당 비용 $1,000 가정: $39,000 - $1,680 = $37,320/년
- ROI: 2,221%

트리거:
- 월 매출 $10,000+
- SLA 99.9% 요구
```

---

## 📈 가용성 및 장애 시나리오

### SLA 계산

**현재 아키텍처 (Single-AZ RDS):**
```
ALB:      99.99% (AWS 보장)
Frontend: 99.95% (2대 × Health Check)
Backend:  99.95% (2대 × Health Check)
RDS:      99.50% (Single-AZ)
──────────────────────────────────
전체:     99.39% ≈ 99.4%

다운타임: 43.8시간/년 (0.61%)
```

**Multi-AZ RDS 적용 시:**
```
RDS:      99.95% (Multi-AZ, 자동 장애조치)
──────────────────────────────────
전체:     99.84% ≈ 99.8%

다운타임: 14.0시간/년 (0.16%)
절감:     29.8시간/년
```

---

### 장애 시나리오별 대응

#### 1. Frontend 인스턴스 1대 장애

```
시나리오:
FE1 (AZ-1a) Health Check 실패
→ ALB가 자동으로 FE1 제외
→ 모든 트래픽 FE2(AZ-1c)로 전환

영향:
- 사용자: 무감지 (< 1분)
- 성능: FE2가 2배 트래픽 처리

복구:
1. Auto Scaling이 FE1 종료 후 새 인스턴스 시작
2. Health Check 통과 후 ALB에 자동 추가
→ RTO: 5분 (인스턴스 부팅 + 애플리케이션 시작)
```

#### 2. Backend 인스턴스 1대 장애

```
시나리오:
BE1 (AZ-1a) 메모리 부족으로 OOM 발생
→ ALB Health Check 실패 (GET /actuator/health → 502)
→ ALB가 자동으로 BE1 제외

영향:
- 사용자: 무감지 (< 1분)
- 성능: BE2가 2배 트래픽 처리
- RDS 부하 증가 (단일 Backend에서만 접근)

복구:
1. Auto Scaling이 BE1 종료 후 새 인스턴스 시작
2. Health Check 통과 후 ALB에 자동 추가
→ RTO: 5-10분 (Spring Boot 시작 시간 포함)
```

#### 3. RDS 장애 (Single-AZ)

```
시나리오:
RDS 인스턴스 하드웨어 장애

영향:
- 전체 서비스 중단 (API 응답 불가)
- Frontend는 정상 (정적 페이지 표시)

복구 절차:
1. RDS 콘솔 → Snapshots → 최신 Snapshot 선택
2. Restore to New Instance (5-10분)
3. Backend application.yaml 수정:
   spring.datasource.url=jdbc:mysql://<NEW_RDS_ENDPOINT>:3306/community
4. Backend 롤링 재시작:
   - BE1 종료 → 새 설정으로 시작 → Health Check 통과
   - BE2 종료 → 새 설정으로 시작 → Health Check 통과
→ RTO: 15-30분

데이터 손실:
- Snapshot 백업 주기: 1일
- 최대 데이터 손실: 24시간
→ RPO: 24시간
```

#### 4. ALB 완전 장애

```
시나리오:
ALB 서비스 자체 장애 (극히 드뭄, AWS 책임)

영향:
- 전체 서비스 접근 불가
- 인스턴스는 정상, 라우팅만 불가

복구 (Option 1 - 수동):
1. 새 ALB 생성 (5분)
2. Target Group 연결
3. Route 53 A Record 업데이트
→ RTO: 10-15분

복구 (Option 2 - 자동):
1. Route 53 Health Check
2. Failover to Secondary ALB (다른 리전)
→ RTO: 1-2분
→ 추가 비용: +$91/월 (복제 인프라)
```

#### 5. AZ 전체 장애

```
시나리오:
AZ-1a 데이터센터 완전 장애

영향:
- FE1, BE1 다운
- RDS 다운 (Single-AZ)
→ 전체 서비스 중단

복구:
1. ALB가 FE2, BE2로 트래픽 전환 (자동, < 1분)
2. RDS Snapshot 복구 (수동, 15-30분)
3. AZ-1c에 새 RDS 생성
4. Backend 설정 변경 및 재시작
→ RTO: 20-40분

Multi-AZ RDS 적용 시:
→ RDS 자동 장애조치 (< 1분)
→ RTO: 1-2분
```

---

## 🚀 Auto Scaling 전략

### Frontend Auto Scaling Group

```yaml
# ASG 설정
Name: community-frontend-asg
Min Size: 2
Max Size: 4
Desired Capacity: 2
Health Check Type: ELB
Health Check Grace Period: 300초

# Launch Template
Instance Type: t3.micro
AMI: Ubuntu 22.04 LTS
User Data:
  - Node.js 20 설치
  - Git clone ktb_community_fe
  - npm install --production
  - systemctl start frontend
```

**Scale Out 조건:**
```
조건 1: CPU Utilization
- Metric: Average CPU > 70%
- Duration: 2분 연속
- Action: +1 인스턴스

조건 2: Request Count
- Metric: RequestCountPerTarget > 1000/분
- Duration: 5분 연속
- Action: +1 인스턴스

Cooldown: 300초 (추가 인스턴스 부팅 시간)
```

**Scale In 조건:**
```
조건 1: CPU Utilization
- Metric: Average CPU < 30%
- Duration: 10분 연속
- Action: -1 인스턴스

Cooldown: 600초 (급격한 축소 방지)
Min Instances: 2 (항상 유지)
```

**시나리오:**
```
평상시:
- FE1, FE2 (2대)
- CPU 15%, 요청 200/분

트래픽 급증 (뉴스 언급):
1. CPU 80% → Scale Out 트리거
2. FE3 생성 (5분)
3. Health Check 통과 → ALB 추가
4. 트래픽 분산: FE1/FE2/FE3
→ CPU 50% 감소

비용:
- 평상시: $15/월 (2대)
- 트래픽 급증: $22.50/월 (3대, 일시적)
```

---

### Backend Auto Scaling Group

```yaml
# ASG 설정
Name: community-backend-asg
Min Size: 2
Max Size: 4
Desired Capacity: 2
Health Check Type: ELB
Health Check Grace Period: 600초 (Spring Boot 시작 시간)

# Launch Template
Instance Type: t3.small
AMI: Ubuntu 22.04 LTS
User Data:
  - Java 24 설치
  - Git clone community
  - ./gradlew bootJar
  - systemctl start backend
```

**Scale Out 조건:**
```
조건 1: CPU Utilization
- Metric: Average CPU > 80%
- Duration: 5분 연속
- Action: +1 인스턴스

조건 2: Database Connections
- Metric: Active Connections > 80
- Duration: 5분 연속
- Action: +1 인스턴스

Cooldown: 600초 (Spring Boot 시작 10분)
```

**Scale In 조건:**
```
조건 1: CPU Utilization
- Metric: Average CPU < 40%
- Duration: 20분 연속
- Action: -1 인스턴스

Cooldown: 1200초 (20분, 급격한 축소 방지)
Min Instances: 2
```

**시나리오:**
```
게시글 작성 급증:
1. CPU 85% → Scale Out 트리거
2. BE3 생성 (10분, Spring Boot 시작)
3. Health Check 통과 → ALB 추가
4. DB Connection Pool 확장:
   - BE1: 33 connections
   - BE2: 33 connections
   - BE3: 33 connections
   → 총 100 connections (RDS max_connections)

병목:
- RDS Single-AZ → Read Replica 추가 고려
- 쓰기 부하 → Multi-AZ 전환 검토
```

---

## 📊 성능 최적화

### 1. Database Optimization

**인덱스 전략:**
```sql
-- 자주 조회되는 컬럼
CREATE INDEX idx_posts_created ON posts(created_at DESC);
CREATE INDEX idx_posts_user_created ON posts(user_id, created_at DESC);
CREATE INDEX idx_comments_post_created ON comments(post_id, created_at, comment_id);

-- 유니크 제약
CREATE UNIQUE INDEX uq_users_email ON users(email);
CREATE UNIQUE INDEX uq_users_nickname ON users(nickname);
CREATE UNIQUE INDEX uq_post_likes ON post_likes(user_id, post_id);

-- 상태 필터링
CREATE INDEX idx_users_status ON users(user_status);
CREATE INDEX idx_posts_status ON posts(post_status);
```

**N+1 문제 해결:**
```java
// PostRepository.java
@Query("SELECT p FROM Post p " +
       "JOIN FETCH p.user " +
       "LEFT JOIN FETCH p.stats " +
       "WHERE p.postStatus = :status")
List<Post> findByStatusWithUserAndStats(PostStatus status, Pageable pageable);

// 효과:
// 기존: 11개 쿼리 (1 + 10 posts × 1 user query)
// 개선: 1개 쿼리 (JOIN FETCH)
// 성능 개선: 91% 쿼리 감소
```

**Batch Fetch Size:**
```yaml
# application.yaml
spring:
  jpa:
    properties:
      hibernate:
        default_batch_fetch_size: 100

# 효과:
# Lazy Loading 시 IN 쿼리로 일괄 로드
# 예: comments 조회 시
# 기존: SELECT * FROM comments WHERE post_id = ? (N번)
# 개선: SELECT * FROM comments WHERE post_id IN (?,?,?...) (1번)
```

---

### 2. Application Optimization

**JVM Tuning:**
```bash
# G1GC 설정 (추천)
JAVA_OPTS="-Xms512m -Xmx512m \
           -XX:+UseG1GC \
           -XX:MaxGCPauseMillis=200 \
           -XX:G1HeapRegionSize=8m \
           -XX:InitiatingHeapOccupancyPercent=45"

# GC 로그 (모니터링용)
JAVA_OPTS="$JAVA_OPTS \
           -Xlog:gc*:file=/var/log/gc.log:time,uptime,level,tags \
           -XX:+UseGCLogFileRotation \
           -XX:NumberOfGCLogFiles=5 \
           -XX:GCLogFileSize=10M"
```

**HikariCP 설정:**
```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 20         # 인스턴스당
      minimum-idle: 5
      connection-timeout: 30000
      idle-timeout: 600000
      max-lifetime: 1800000

# 전체 Backend 인스턴스 × 20 = 40 connections
# RDS max_connections: 100 (여유 60)
```

---

### 3. Frontend Optimization

**정적 자산 캐싱:**
```javascript
// server.js
app.use(express.static('origin_source/static', {
  maxAge: '1d',              // 1일 캐싱
  etag: true,                // ETag 헤더
  lastModified: true,        // Last-Modified 헤더
  immutable: true            // Cache-Control: immutable
}));
```

**Gzip 압축:**
```bash
npm install compression

// server.js
const compression = require('compression');
app.use(compression({
  level: 6,              // 압축 레벨 (1-9)
  threshold: 1024        // 1KB 이상만 압축
}));

# 효과:
# HTML: 80% 압축 (10KB → 2KB)
# CSS:  90% 압축 (50KB → 5KB)
# JS:   85% 압축 (100KB → 15KB)
```

---

## 🔐 보안 강화

### 1. HTTPS 설정 (ACM + ALB)

```yaml
# AWS Certificate Manager (ACM)
Domain: example.com
Validation: DNS (Route 53)
Certificate: arn:aws:acm:ap-northeast-2:123456789012:certificate/xxx

# ALB Listener 변경
Listener 1:
  Port: 443 (HTTPS)
  Protocol: HTTPS
  SSL Certificate: ACM Certificate
  Target Group: Frontend, Backend

Listener 2:
  Port: 80 (HTTP)
  Protocol: HTTP
  Default Action: Redirect to HTTPS (301)
```

---

### 2. Secrets Manager 통합

```bash
# JWT Secret 저장
aws secretsmanager create-secret \
  --name /community/prod/jwt-secret \
  --secret-string "your-256-bit-secret"

# DB Password 저장
aws secretsmanager create-secret \
  --name /community/prod/db-password \
  --secret-string "your-db-password"

# Backend 환경변수
JWT_SECRET_ARN=arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:/community/prod/jwt-secret
DB_PASSWORD_ARN=arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:/community/prod/db-password

# 애플리케이션 시작 시 조회
```

---

### 3. WAF 설정 (선택)

```yaml
# AWS WAF Web ACL
Name: community-waf
Scope: Regional (ALB)
Rules:
  1. AWS Managed Rule: Core Rule Set (CRS)
  2. Rate Limiting: 2000 requests/5min per IP
  3. Geo Blocking: 특정 국가 차단 (선택)
  4. SQL Injection 방어
  5. XSS 방어

Cost: $5/월 + $1/M requests
```

---

## 🎯 모니터링 및 알람

### CloudWatch 메트릭

**ALB:**
```
- TargetResponseTime (평균 < 500ms)
- RequestCount (분당 요청 수)
- HTTPCode_Target_4XX_Count (4xx 에러)
- HTTPCode_Target_5XX_Count (5xx 에러)
- UnHealthyHostCount (비정상 인스턴스)
```

**EC2 (Frontend/Backend):**
```
- CPUUtilization (평균 < 70%)
- NetworkIn/Out (트래픽 모니터링)
- StatusCheckFailed (인스턴스 상태)
- DiskReadBytes/WriteBytes (I/O 병목)
```

**RDS:**
```
- CPUUtilization (평균 < 80%)
- DatabaseConnections (최대 100)
- ReadLatency/WriteLatency (< 10ms)
- FreeStorageSpace (최소 2GB)
```

---

### 알람 설정

```yaml
Alarm 1: Backend High CPU
  Metric: Backend ASG Average CPU > 80%
  Duration: 5분 연속
  Action: SNS → Email/Slack

Alarm 2: RDS High Connections
  Metric: DatabaseConnections > 80
  Duration: 5분 연속
  Action: SNS → Email/Slack

Alarm 3: ALB 5xx Errors
  Metric: HTTPCode_Target_5XX_Count > 10/분
  Duration: 3분 연속
  Action: SNS → Email/Slack → PagerDuty

Alarm 4: Unhealthy Targets
  Metric: UnHealthyHostCount > 0
  Duration: 1분 연속
  Action: SNS → Email/Slack
```

---

## 📝 배포 체크리스트

### Pre-Deployment

- [*] VPC 생성 (10.0.0.0/16)
  - [*] Public Subnet × 2 (AZ-1a, AZ-1b)
  - [*] Private Subnet × 2 (AZ-1a, AZ-1B)
  - [*] Internet Gateway 연결
  - [*] Route Table 설정

- [*] Security Groups 생성 (4개)
  - [*] ALB SG - ktb-community-alb-sg:      sg-0617cbc8fa80bb21d
  - [*] Frontend SG - ktb-community-frontend-sg: sg-08a8431cb1c1b3706
  - [*] Backend SG - ktb-community-backend-sg:  sg-0a1cc7f873441bb15
  - [*] RDS SG - ktb-community-rds-sg:      sg-05b6d9e4d6eb28525
  
- [*] RDS 생성
  - [*] MySQL 8.0.35, db.t3.micro, Single-AZ
  - [*] 20GB GP3 스토리지
  - [*] 자동 백업 활성화 (7일)

- [*] ALB 생성
  - [*] Internet-facing, Multi-AZ
  - [*] Target Group 2개 (Frontend, Backend)
  - [*] Health Check 설정 - backend : /health 엔드포인트 추가

- [ ] Lambda + API Gateway
  - [ ] Lambda 함수 배포 (upload-image.zip)
  - [ ] API Gateway CORS 설정
  - [ ] Secrets Manager 권한 부여

---

### Deployment Steps

**1. Frontend 배포:**
```bash
# EC2 접속
ssh -i keypair.pem ubuntu@<frontend-1-ip>

# Node.js 설치
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# 애플리케이션 배포
git clone https://github.com/your-repo/ktb_community_fe
cd ktb_community_fe
npm install --production

# 환경변수 설정
sudo tee /etc/systemd/system/frontend.service > /dev/null <<EOF
[Unit]
Description=KTB Community Frontend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/ktb_community_fe
Environment="PORT=3000"
Environment="EC2_PUBLIC_IP=your-alb-dns-name"
ExecStart=/usr/bin/node server.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 서비스 시작
sudo systemctl daemon-reload
sudo systemctl enable frontend
sudo systemctl start frontend
sudo systemctl status frontend
```

**2. Backend 배포:**
```bash
# EC2 접속
ssh -i keypair.pem ubuntu@<backend-1-ip>

# Java 24 설치
sudo apt update
sudo apt install -y openjdk-24-jdk

# 애플리케이션 배포
git clone https://github.com/your-repo/community
cd community
./gradlew bootJar

# 환경변수 설정
sudo tee /etc/systemd/system/backend.service > /dev/null <<EOF
[Unit]
Description=KTB Community Backend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/community
Environment="SPRING_PROFILES_ACTIVE=prod"
Environment="DB_URL=jdbc:mysql://rds-endpoint:3306/community"
Environment="DB_USERNAME=admin"
Environment="DB_PASSWORD=from-secrets-manager"
Environment="JWT_SECRET=from-secrets-manager"
ExecStart=/usr/bin/java -Xms512m -Xmx512m -jar build/libs/community.jar
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 서비스 시작
sudo systemctl daemon-reload
sudo systemctl enable backend
sudo systemctl start backend
sudo systemctl status backend
```

---

### Post-Deployment

- [ ] Health Check 확인
  - [ ] ALB → Targets → Frontend (Healthy)
  - [ ] ALB → Targets → Backend (Healthy)

- [ ] 기능 테스트
  - [ ] GET / → Frontend 정상 응답
  - [ ] POST /api/auth/login → Backend JWT 발급
  - [ ] POST /images → Lambda 이미지 업로드

- [ ] 모니터링 설정
  - [ ] CloudWatch Dashboard 생성
  - [ ] SNS Topic 구독 (Email/Slack)
  - [ ] 알람 4개 활성화

- [ ] 백업 확인
  - [ ] RDS Snapshot 1개 이상 존재
  - [ ] AMI 생성 (Frontend/Backend)

---

## 🔄 마이그레이션 로드맵

### Phase 1: 현재 아키텍처 (완료)
```
✅ FE/BE 분리 (EC2 × 4)
✅ ALB Multi-AZ
✅ RDS Single-AZ
✅ Lambda 이미지 업로드
```

### Phase 2: 정적 자산 CDN (MAU 10만+)
```
목표: 정적 파일 성능 개선
아키텍처:
  Browser → CloudFront → S3 (CSS, JS, images)
                       ↓ (HTML만)
                     ALB → Frontend

비용: +$1/월
성능: 4-15x 개선 (글로벌 Edge)
```

### Phase 3: Frontend S3 전환 (과제 제출 후)
```
목표: Frontend EC2 비용 절감
아키텍처:
  Browser → CloudFront → S3 (React/Vue Build)
                       ↓ (API만)
                     ALB → Backend

비용: -$15/월 ($91 → $76)
구현:
  1. 빌드 타임 환경변수 주입
  2. S3 + CloudFront 배포
  3. Frontend EC2 종료
```

### Phase 4: Multi-AZ RDS (MAU 50만+)
```
목표: 데이터베이스 가용성 향상
트리거:
  - 월 매출 $10,000+
  - SLA 99.9% 요구
  - 다운타임 비용 > $140/월

아키텍처:
  RDS Single-AZ → Multi-AZ (자동 장애조치)

비용: +$140/월 ($76 → $216)
가용성: 99.4% → 99.8%
RTO: 30분 → 1분
```

### Phase 5: Read Replica (MAU 100만+)
```
목표: 읽기 성능 향상
아키텍처:
  Backend → RDS Primary (쓰기)
         └→ RDS Read Replica × 2 (읽기)

비용: +$60/월 (db.t3.micro × 2)
성능: 읽기 쿼리 3배 분산
```

---

## 📚 참고 문서

**프로젝트 문서:**
- `@CLAUDE.md` - 프로젝트 개요 및 개발 가이드
- `@docs/be/PLAN.md` - Phase별 구현 로드맵
- `@docs/be/PRD.md` - 요구사항 명세
- `@docs/be/LLD.md` - 상세 설계 문서
- `@docs/be/API.md` - API 엔드포인트 명세

**Legacy 문서 (참고용):**
- `@docs/legacy/ARCHITECTURE_DECISION.md` - 아키텍처 결정 과정
- `@docs/legacy/FRONTEND_ARCHITECTURE_COMPARISON.md` - FE 배포 옵션 비교
- `@docs/legacy/terraform/` - Terraform 코드 (미사용)
- `@docs/legacy/lambda/` - Lambda 함수 코드 (참고)

**AWS 공식 문서:**
- [EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [ALB User Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Auto Scaling User Guide](https://docs.aws.amazon.com/autoscaling/)

---

## 💡 Key Insights

`★ Insight ─────────────────────────────────────`

**1. FE/BE 분리의 핵심 가치**

**리소스 격리:**
- Frontend: CPU 10-20% (정적 파일 I/O)
- Backend: CPU 60-80% (비즈니스 로직)
- 통합 시 Backend 과부하 → Frontend도 영향

**독립적 확장:**
```
시나리오 1: 페이지 조회 급증
→ Frontend만 2대 → 4대 ($15 추가)
→ Backend 유지 (비용 절감)

시나리오 2: API 호출 급증
→ Backend만 2대 → 4대 ($30 추가)
→ Frontend 유지
```

**배포 독립성:**
- UI 수정 → Frontend만 재배포 (무중단)
- API 수정 → Backend만 재배포 (무중단)

**장애 격리:**
- Backend DB 장애 → Frontend 정상 (정적 페이지)
- 사용자에게 "서비스 점검 중" 안내 가능

---

**2. Single-AZ vs Multi-AZ RDS 선택**

**ROI 계산:**
```
투자: +$140/월 = $1,680/년
다운타임 감소: 29.8시간/년
시간당 비용 $1,000 가정:
  절감: $29,800/년
  순이익: $28,120/년
  ROI: 1,674%
```

**의사결정 기준:**
- 초기 (MAU < 10만): Single-AZ (비용 최소화)
- 성장기 (MAU 10-50만): 모니터링 + Snapshot 백업
- 성숙기 (MAU 50만+): Multi-AZ 전환 (SLA 보장)

---

**3. Lambda VPC 밖 배치**

**Cold Start 비교:**
- VPC 밖: 50-200ms (즉시 실행)
- VPC 내: 10-15초 (ENI 생성 대기)

**비용 비교:**
- VPC 밖: $0 (S3 접근 직접)
- VPC 내: +$32/월 (NAT Gateway) + 트래픽 비용

**단일 책임 원칙:**
- Lambda: 이미지 업로드만
- Backend: DB 저장만
- 명확한 역할 분리 → 유지보수 용이

---

**4. t3.micro vs t3.small 선택**

**Frontend (t3.micro 충분):**
```
Node.js: 100-150MB
여유:    850MB (85% 헤드룸)
결론:    t3.small 불필요 (-$15/월)
```

**Backend (t3.small 필수):**
```
JVM:     954MB (Heap + Non-Heap)
DB Pool:  50MB
OS:      250MB
합계:  1,254MB → 2GB 필요
```

**교훈:** 실제 메모리 사용량 측정 후 인스턴스 선택

`─────────────────────────────────────────────────`

---

## 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|-----------|
| 2025-11-13 | 4.0 | 최초 작성 - FE/BE 분리 아키텍처 확정 |

---


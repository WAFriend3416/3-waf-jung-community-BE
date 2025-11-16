# 이미지 업로드 아키텍처 변경사항 (Lambda 통합)

## 문서 정보

| 항목 | 내용 |
|------|------|
| 작성일 | 2025-11-14 |
| 버전 | 1.0 |
| 대상 | 배포 담당자, 개발자 |

---

## 1. 아키텍처 변경 개요

### 1.1 변경 배경

**기존 문제:**
- Backend 서버가 Multipart 파일 파싱 및 S3 업로드 처리
- WAS 메모리 부담 및 응답 시간 지연
- 파일 업로드 실패 시 트랜잭션 롤백 복잡도 증가

**해결 방안:**
- Lambda를 통한 파일 업로드 전담 처리
- Backend는 메타데이터 등록만 담당 (경량화)
- 비용 최적화 (NAT Gateway 제거와 일관된 철학)

### 1.2 아키텍처 비교

**기존 방식 (회원가입/프로필 수정만 유지):**
```
Browser → ALB → Backend → S3
              ↓
           MySQL (트랜잭션 포함)
```

**신규 방식 (게시글 이미지 업로드):**
```
Step 1: 이미지 파일 업로드
  Browser → API Gateway → Lambda → S3
                            ↓
  Browser ← imageUrl 반환

Step 2: 메타데이터 등록 (게시글 작성 시)
  Browser → ALB → Backend → MySQL
           (imageUrl 전달)
```

### 1.3 적용 범위

| 기능 | 방식 | 인증 | 엔드포인트 |
|------|------|------|-----------|
| **회원가입 이미지** | Lambda | Guest Token | POST /images (API Gateway) |
| **게시글 이미지** | Lambda | User Token | POST /images (API Gateway) |
| **프로필 이미지** | Lambda | User Token | POST /images (API Gateway) |
| **회원가입 (메타데이터)** | Backend | Guest Token → User Token | POST /users/signup |
| **프로필 수정 (메타데이터)** | Backend | User Token | PATCH /users/{userId} |

**플로우:**
1. **회원가입 시**: GET /auth/guest-token → Lambda 이미지 업로드 → POST /users/signup (imageId 포함)
2. **게시글 작성 시**: Lambda 이미지 업로드 → POST /posts (imageId 포함)
3. **프로필 수정 시**: Lambda 이미지 업로드 → PATCH /users/{userId} (imageId 포함)

------|------|-----------|
| **회원가입** | Backend Multipart | POST /users/signup |
| **프로필 수정** | Backend Multipart | PATCH /users/{userId} |
| **게시글 이미지** | Lambda (신규) | POST /images (API Gateway) |
| **프로필 이미지** | Lambda (신규) | POST /images (API Gateway) |

---

## 2. Lambda 설정

### 2.1 함수 정보

| 항목 | 값 |
|------|-----|
| **함수 이름** | upload-image |
| **런타임** | Node.js 18.x |
| **핸들러** | index.handler |
| **메모리** | 512 MB |
| **타임아웃** | 30초 |
| **아키텍처** | x86_64 |

### 2.2 IAM Role 권한

**Role 이름:** `upload-image-role`

**정책 (Inline Policy):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::ktb-3-community-images-dev/users/*/images/*"
    },
    {
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:ap-northeast-2:557690602093:parameter/community/JWT_SECRET"
    },
    {
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "*"
    }
  ]
}
```

**AWS 관리형 정책:**
- `AWSLambdaBasicExecutionRole` (CloudWatch Logs)

### 2.3 환경변수

| 변수명 | 값 예시 | 설명 |
|--------|---------|------|
| **S3_BUCKET** | ktb-3-community-images-dev | S3 버킷 이름 |
| **FRONTEND_URL** | * | CORS Allow-Origin (프로덕션: 실제 도메인) |
| AWS_REGION | ap-northeast-2 | 자동 주입 (수동 설정 불필요) |

### 2.4 배포 파일

**위치:** `/lambda/upload-image/upload-image.zip`
**크기:** 4.5 MB
**포함 파일:**
- `index.js` (메인 코드, 213 lines)
- `package.json`
- `node_modules/` (jsonwebtoken, @aws-sdk/client-s3, @aws-sdk/client-ssm)

**재배포 명령:**
```bash
cd /Users/jsh/IdeaProjects/community/lambda/upload-image
zip -r upload-image.zip index.js package.json node_modules/
aws lambda update-function-code \
  --function-name upload-image \
  --zip-file fileb://upload-image.zip \
  --region ap-northeast-2
```

---

## 3. API Gateway 설정

### 3.1 타입 및 이름

| 항목 | 값 |
|------|-----|
| **타입** | HTTP API (비용 최적화: $1.00/million vs REST $3.50/million) |
| **이름** | upload-image-api |
| **프로토콜** | HTTPS |

### 3.2 CORS 설정

| 설정 | 값 |
|------|-----|
| **Access-Control-Allow-Origin** | `*` (개발) / 프론트엔드 도메인 (프로덕션) |
| **Access-Control-Allow-Methods** | POST, OPTIONS |
| **Access-Control-Allow-Headers** | * |
| **Access-Control-Allow-Credentials** | false (Authorization 헤더 사용) |

### 3.3 Lambda 통합

**경로:** `POST /images`
**통합 타입:** Lambda Proxy Integration
**Lambda 함수:** `upload-image`
**페이로드 버전:** 2.0

### 3.4 Invoke URL

**형식:** `https://{api-id}.execute-api.ap-northeast-2.amazonaws.com/images`

**사용 예시:**
```bash
curl -X POST "https://abc123.execute-api.ap-northeast-2.amazonaws.com/images" \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: image/jpeg" \
  -H "x-filename: profile.jpg" \
  --data-binary "@profile.jpg"
```

---

## 4. Lambda 코드 핵심 로직

### 4.1 전체 플로우

```
1. JWT 검증 (Parameter Store에서 시크릿 캐싱)
   ↓
2. 파일 검증 (Content-Type, 크기, Magic Number)
   ↓
3. S3 업로드 (users/{userId}/images/{timestamp}-{uuid}.{ext})
   ↓
4. imageUrl 반환 (201 Created)
```

### 4.2 보안 기능

| 기능 | 구현 | 코드 위치 |
|------|------|----------|
| **JWT 검증** | jwt.verify() + Parameter Store | Line 47-67 |
| **토큰 타입 구분** | role 필드 추출 (USER/GUEST) | Line 59 |
| **토큰 만료 구분** | TokenExpiredError 체크 | Line 62-63 |
| **파일 크기 제한** | 5MB (5 * 1024 * 1024) | Line 95-98 |
| **Content-Type 검증** | 화이트리스트 (jpeg, png, gif) | Line 89-92 |
| **Magic Number 검증** | 바이트 단위 시그니처 확인 | Line 64-82 |
| **MIME Spoofing 방지** | 헤더와 실제 파일 내용 일치 확인 | Line 76-81 |

### 4.3 Guest Token 지원

**용도:** 회원가입 시 프로필 이미지 업로드

**JWT Payload 구조:**
```json
{
  "sub": "guest-550e8400-e29b-41d4-a716-446655440000",
  "role": "GUEST",
  "iat": 1234567890,
  "exp": 1234568190
}
```

**검증 로직 (Line 47-67):**
```javascript
async function verifyJWT(token) {
    // ...
    const payload = jwt.verify(token, jwtSecret);
    return {
        userId: payload.sub,        // "guest-{UUID}" 또는 실제 userId
        email: payload.email,       // GUEST는 undefined
        role: payload.role || 'USER'  // 기본값: USER
    };
}
```

**역할별 처리 (Line 159-163):**
```javascript
// Handler에서 로깅
if (role === 'GUEST') {
    console.log('✅ Guest Token detected - signup image upload');
} else {
    console.log('✅ User Token detected - authenticated upload');
}
```

**S3 키 생성:**
- User Token: `users/{userId}/images/{timestamp}-{uuid}.{ext}`
- Guest Token: `users/guest-{UUID}/images/{timestamp}-{uuid}.{ext}`
- **회원가입 완료 시**: Backend가 이미지 URL로 메타데이터 등록, TTL 해제

**보안 특징:**
- 유효기간: 5분 (회원가입 플로우 내에서만 유효)
- DB 저장 없음 (stateless)
- Refresh Token 없음 (일회용)
- 발급: GET /auth/guest-token (Backend)

### 4.4 S3 키 생성 로직

**패턴:** `users/{userId}/images/{timestamp}-{uuid}.{extension}`

**예시:** `users/123/images/1699876543210-a1b2c3d4-e5f6-7g8h-9i0j-k1l2m3n4o5p6.jpeg`

**특징:**
- **userId 격리:** 사용자별 폴더 분리
- **timestamp:** 시간순 정렬 가능
- **uuid:** 동시 업로드 충돌 방지 (crypto.randomUUID())
- **extension:** Content-Type에서 추출 (jpeg, png, gif)

### 4.5 에러 코드 매핑

| Lambda Error | HTTP | Backend Code | 설명 |
|--------------|------|--------------|------|
| TOKEN_MISSING | 401 | AUTH-003 | Authorization 헤더 없음 |
| TOKEN_EXPIRED | 401 | AUTH-003 | Access Token 만료 |
| TOKEN_INVALID | 401 | AUTH-003 | JWT 서명 불일치 |
| INVALID_FILE_TYPE | 400 | IMAGE-003 | 허용되지 않은 파일 형식 |
| INVALID_FILE_SIGNATURE | 400 | IMAGE-004 | Magic Number 불일치 |
| FILE_TOO_LARGE | 413 | IMAGE-002 | 파일 크기 5MB 초과 |
| (기타) | 500 | COMMON-999 | 예상치 못한 서버 오류 |

---

## 5. Backend 변경사항

### 5.1 신규 엔드포인트

**엔드포인트:** `POST /images/metadata`
**역할:** Lambda 업로드 후 DB에 메타데이터 등록
**요청:** `{ "imageUrl": "https://...", "fileSize": 1234567, "originalFilename": "profile.jpg" }`
**응답:** `{ "imageId": 123, "imageUrl": "...", ... }`

**참조:** `@docs/be/API.md Section 4.1`

### 5.2 신규 파일

| 파일 | 역할 |
|------|------|
| **ImageMetadataRequest.java** | Lambda 업로드 결과 DTO (imageUrl 필수) |
| **ImageService.registerImageMetadata()** | imageUrl 검증 + 중복 체크 + DB 저장 |
| **ImageController.registerImageMetadata()** | POST /images/metadata 엔드포인트 |
| **ImageRepository.existsByImageUrl()** | 중복 검증 쿼리 메서드 |

### 5.3 ErrorCode 추가

```java
INVALID_IMAGE_URL("IMAGE-005", "Invalid image URL format", HttpStatus.BAD_REQUEST)
```

**검증 로직:**
```java
String s3BaseUrl = String.format("https://%s.s3.%s.amazonaws.com/", bucketName, region);
if (!request.getImageUrl().startsWith(s3BaseUrl)) {
    throw new BusinessException(ErrorCode.INVALID_IMAGE_URL);
}
```

### 5.4 기존 유지

**POST /images (Multipart):**
- 회원가입/프로필 수정 시 사용
- ImageService.uploadImage() 유지
- S3 직접 업로드 로직 유지

**이유:** 트랜잭션 원자성이 중요한 경우 (회원가입 실패 시 이미지도 롤백)

---

## 6. Frontend 변경사항

### 6.1 API 엔드포인트 URL

**변경 필요 여부:** 환경변수로 분기

**옵션 1: API Gateway 직접 호출 (권장)**
```javascript
// .env 또는 환경변수
VITE_IMAGE_UPLOAD_URL=https://{api-id}.execute-api.ap-northeast-2.amazonaws.com

// api.js
const imageUploadUrl = import.meta.env.VITE_IMAGE_UPLOAD_URL || `${API_BASE_URL}`;
const response = await fetch(`${imageUploadUrl}/images`, {
    method: 'POST',
    headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': file.type,
        'x-filename': file.name
    },
    body: file
});
```

**옵션 2: ALB를 통한 프록시 (추가 설정 필요)**
- ALB 리스너 규칙에서 `/images` → API Gateway로 라우팅
- 이 경우 Frontend 코드 변경 불필요

### 6.2 요청 방식

**동일:**
- `Authorization: Bearer {access_token}` 헤더
- `Content-Type: image/jpeg` (또는 png, gif)
- `x-filename: {원본파일명}` (선택)

**변경 없음:**
- Multipart 아님, 바이너리 직접 전송
- base64 인코딩 불필요 (API Gateway가 자동 처리)

### 6.3 응답 구조

**Lambda 응답 (Backend와 동일):**
```json
{
  "message": "upload_image_success",
  "data": {
    "imageUrl": "https://ktb-3-community-images-dev.s3.ap-northeast-2.amazonaws.com/...",
    "fileSize": 1234567,
    "originalFilename": "profile.jpg",
    "uploadedAt": "2025-11-14T10:00:00.000Z"
  },
  "timestamp": "2025-11-14T10:00:00.000Z"
}
```

---

## 7. 배포 가이드

### 7.1 사전 준비

**AWS CLI 설정:**
```bash
aws configure
# AWS Access Key ID: {IAM 사용자 키}
# AWS Secret Access Key: {IAM 사용자 시크릿}
# Default region name: ap-northeast-2
# Default output format: json
```

**Parameter Store 확인:**
```bash
aws ssm get-parameter \
  --name /community/JWT_SECRET \
  --with-decryption \
  --region ap-northeast-2
```

### 7.2 Lambda 배포

**Step 1: 배포 패키지 업로드**
```bash
cd /Users/jsh/IdeaProjects/community/lambda/upload-image

# 패키지 생성 (이미 완료)
zip -r upload-image.zip index.js package.json node_modules/

# Lambda 업데이트
aws lambda update-function-code \
  --function-name upload-image \
  --zip-file fileb://upload-image.zip \
  --region ap-northeast-2
```

**Step 2: 환경변수 설정**
```bash
aws lambda update-function-configuration \
  --function-name upload-image \
  --environment "Variables={S3_BUCKET=ktb-3-community-images-dev,FRONTEND_URL=*}" \
  --region ap-northeast-2
```

**Step 3: IAM Role 연결 확인**
```bash
aws lambda get-function-configuration \
  --function-name upload-image \
  --region ap-northeast-2 \
  --query 'Role'
```

**Step 4: 테스트 이벤트 실행**
```bash
# 테스트 페이로드 작성 (test-event.json)
# 실제 이미지 base64 인코딩 필요
aws lambda invoke \
  --function-name upload-image \
  --payload file://test-event.json \
  --region ap-northeast-2 \
  response.json
```

### 7.3 API Gateway 배포

**Step 1: API 생성 (이미 완료)**
- Console: API Gateway → HTTP API → Create
- 이름: upload-image-api

**Step 2: Lambda 통합 설정**
- Routes → POST /images
- Integration: upload-image (Lambda function)
- Payload format version: 2.0

**Step 3: CORS 설정**
- CORS → Configure
- Access-Control-Allow-Origin: *
- Access-Control-Allow-Methods: POST, OPTIONS

**Step 4: Invoke URL 확인**
```bash
aws apigatewayv2 get-apis \
  --region ap-northeast-2 \
  --query 'Items[?Name==`upload-image-api`].ApiEndpoint'
```

### 7.4 Backend 배포

**Step 1: 코드 빌드**
```bash
cd /Users/jsh/IdeaProjects/community
./gradlew clean build
```

**Step 2: JAR 파일 생성 확인**
```bash
ls -lh build/libs/community-*.jar
```

**Step 3: EC2 배포 (기존 프로세스)**
```bash
# SCP로 JAR 전송
scp build/libs/community-*.jar ec2-user@{EC2_IP}:/home/ec2-user/

# SSH 접속 후 재시작
ssh ec2-user@{EC2_IP}
sudo systemctl restart community
```

**Step 4: 환경변수 확인 (application.yaml 또는 환경변수)**
```yaml
aws:
  s3:
    bucket: ktb-3-community-images-dev
    region: ap-northeast-2
```

### 7.5 Frontend 배포

**Step 1: 환경변수 설정**
```bash
# .env.production
VITE_IMAGE_UPLOAD_URL=https://{api-id}.execute-api.ap-northeast-2.amazonaws.com
```

**Step 2: 빌드**
```bash
cd /Users/jsh/ktb_community_fe
npm run build
```

**Step 3: 배포**
```bash
# EC2 배포 예시
scp -r dist/* ec2-user@{EC2_IP}:/var/www/html/
```

---

## 8. 테스트 방법

### 8.1 Lambda 단독 테스트

**Step 1: Access Token 발급**
```bash
# Backend 로그인 API 호출
curl -X POST "http://{ALB_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"Test1234!"}' \
  | jq -r '.data.accessToken'
```

**Step 2: 이미지 업로드**
```bash
# API Gateway Invoke URL 사용
ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
API_GATEWAY_URL="https://{api-id}.execute-api.ap-northeast-2.amazonaws.com"

curl -X POST "${API_GATEWAY_URL}/images" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: image/jpeg" \
  -H "x-filename: test.jpg" \
  --data-binary "@test.jpg" \
  | jq .
```

**예상 응답:**
```json
{
  "message": "upload_image_success",
  "data": {
    "imageUrl": "https://ktb-3-community-images-dev.s3.ap-northeast-2.amazonaws.com/users/123/images/1699876543210-uuid.jpeg",
    "fileSize": 1234567,
    "originalFilename": "test.jpg",
    "uploadedAt": "2025-11-14T10:00:00.000Z"
  },
  "timestamp": "2025-11-14T10:00:00.000Z"
}
```

### 8.2 Backend 메타데이터 등록 테스트

```bash
# Lambda 응답의 imageUrl 사용
IMAGE_URL="https://ktb-3-community-images-dev.s3.ap-northeast-2.amazonaws.com/..."

curl -X POST "http://{ALB_URL}/images/metadata" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"imageUrl\":\"${IMAGE_URL}\",\"fileSize\":1234567,\"originalFilename\":\"test.jpg\"}" \
  | jq .
```

**예상 응답:**
```json
{
  "message": "register_image_metadata_success",
  "data": {
    "imageId": 123,
    "imageUrl": "https://...",
    "createdAt": "2025-11-14T10:00:00"
  },
  "timestamp": "2025-11-14T10:00:00"
}
```

### 8.3 S3 업로드 확인

```bash
aws s3 ls s3://ktb-3-community-images-dev/users/123/images/ \
  --region ap-northeast-2
```

### 8.4 통합 테스트 (Browser)

**플로우:**
1. 브라우저에서 로그인 → Access Token 획득
2. POST /images (API Gateway) → imageUrl 획득
3. (선택) POST /images/metadata (Backend) → imageId 획득
4. 게시글 작성 시 imageId 사용

---

## 9. 주의사항 및 FAQ

### 9.1 Lambda 콜드 스타트

**문제:** 첫 요청 시 1-3초 지연 발생
**해결:**
- 프로비저닝된 동시성 설정 (추가 비용)
- 또는 주기적 Ping (예: CloudWatch Events)

**권장:** 초기 트래픽 낮으므로 현재는 미설정

### 9.2 API Gateway CORS

**문제:** 브라우저에서 CORS 에러 발생
**해결:**
- API Gateway CORS 설정 확인 (Access-Control-Allow-Origin)
- 프로덕션 환경에서는 FRONTEND_URL을 실제 도메인으로 설정

### 9.3 Backend POST /images 유지 이유

**질문:** 왜 기존 엔드포인트를 제거하지 않나요?
**답변:**
- 회원가입/프로필 수정은 트랜잭션 원자성이 중요
- Lambda 업로드 실패 시 회원가입 롤백 불가
- Multipart 방식이 더 간편 (단일 요청)

### 9.4 JWT 만료 처리

**플로우:**
```
1. Lambda: TokenExpiredError 감지
   ↓
2. 401 + AUTH-003 응답
   ↓
3. Browser: POST /auth/refresh_token (RT Cookie 전송)
   ↓
4. Backend: 새 Access Token 발급
   ↓
5. Browser: 이미지 업로드 재시도
```

**참고:** Frontend에서 자동 재시도 로직 구현 필요

### 9.5 비용 최적화

**HTTP API vs REST API:**
- HTTP API: $1.00 per million requests
- REST API: $3.50 per million requests
- **절감:** 71% ($2.50/million)

**NAT Gateway 제거와 일관성:**
- Lambda는 Public 서브넷 불필요 (AWS 관리형)
- S3, SSM은 퍼블릭 엔드포인트 사용
- 추가 NAT Gateway 비용 없음

---

## 10. 트러블슈팅

### 10.1 Lambda 에러: "TOKEN_MISSING"

**원인:** Authorization 헤더 누락 또는 잘못된 형식
**해결:**
```bash
# 올바른 형식
-H "Authorization: Bearer {access_token}"

# 잘못된 형식 (Bearer 누락)
-H "Authorization: {access_token}"
```

### 10.2 Lambda 에러: "INVALID_FILE_SIGNATURE"

**원인:** Content-Type과 실제 파일 내용 불일치
**해결:**
```bash
# Content-Type을 파일 실제 형식에 맞게 설정
file test.jpg  # JPEG image data

-H "Content-Type: image/jpeg"  # ✅ 올바름
-H "Content-Type: image/png"   # ❌ 잘못됨 (MIME spoofing)
```

### 10.3 Backend 에러: "INVALID_IMAGE_URL"

**원인:** imageUrl이 S3 버킷 URL 형식이 아님
**해결:**
```javascript
// Lambda 응답의 imageUrl을 그대로 사용
const { imageUrl } = lambdaResponse.data;

// ✅ 올바른 형식
https://ktb-3-community-images-dev.s3.ap-northeast-2.amazonaws.com/...

// ❌ 잘못된 형식
https://example.com/image.jpg
```

### 10.4 S3 업로드 실패: "Access Denied"

**원인:** Lambda IAM Role에 S3 PutObject 권한 없음
**해결:**
```bash
# IAM Role 정책 확인
aws iam list-attached-role-policies \
  --role-name upload-image-role

# Inline Policy 확인
aws iam get-role-policy \
  --role-name upload-image-role \
  --policy-name upload-image-policy
```

### 10.5 API Gateway 502 Bad Gateway

**원인:** Lambda 함수 실행 오류 또는 타임아웃
**해결:**
```bash
# CloudWatch Logs 확인
aws logs tail /aws/lambda/upload-image \
  --follow \
  --region ap-northeast-2

# Lambda 타임아웃 확인 (30초 설정 필요)
aws lambda get-function-configuration \
  --function-name upload-image \
  --query 'Timeout'
```

---

## 11. 참고 문서

| 문서 | 경로 | 내용 |
|------|------|------|
| **API 명세** | `@docs/be/API.md Section 4` | POST /images, POST /images/metadata |
| **설계 문서** | `@docs/be/LLD.md Section 7.5` | 이미지 업로드 패턴 3가지 |
| **개발 가이드** | `@CLAUDE.md` | 프로젝트 전체 가이드 |
| **계획 문서** | `@docs/be/PLAN.md Phase 5` | Lambda 통합 계획 |

---

## 12. 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|-----------|
| 2025-11-14 | 1.0 | 초기 문서 작성 (Lambda, API Gateway, Backend 통합) |

# Lambda 함수: 이미지 업로드

## 개요
- **목적**: S3 이미지 업로드 전용 Lambda 함수
- **트리거**: API Gateway POST /images
- **인증**: JWT (Parameter Store에서 JWT_SECRET 로드)
- **저장소**: Parameter Store (Secrets Manager 대신)

## 변경 사항 (v2.0.0)
- ✅ Secrets Manager → Parameter Store 전환
- ✅ `/community/JWT_SECRET` 파라미터 사용
- ✅ Cold Start 15ms 개선 (SSM이 SM보다 빠름)
- ✅ 비용 절감 ($0.40/월 → $0/월)

## 로컬 패키징

### 1. 의존성 설치
```bash
cd lambda/upload-image
npm install --production
```

### 2. Lambda 패키지 생성
```bash
zip -r upload-image.zip index.js node_modules/ package.json
ls -lh upload-image.zip  # 약 5MB
```

### 3. 생성된 파일
- `upload-image.zip` - AWS Lambda에 업로드할 패키지

## AWS Lambda 설정

### 환경 변수
```
AWS_REGION=ap-northeast-2
S3_BUCKET=ktb-community-images-prod
FRONTEND_URL=https://your-frontend-domain.com
```

### IAM 권한
Lambda 실행 역할에 다음 권한 필요:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter"
      ],
      "Resource": "arn:aws:ssm:ap-northeast-2:*:parameter/community/JWT_SECRET"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "ssm.ap-northeast-2.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::ktb-community-images-prod/*"
    }
  ]
}
```

## Lambda 스펙
- **Runtime**: Node.js 20.x
- **Memory**: 512 MB
- **Timeout**: 30초
- **Architecture**: x86_64

## API Gateway 통합
- **Method**: POST /images
- **Integration**: Lambda Proxy
- **Binary Media Types**: image/jpeg, image/png, image/gif
- **CORS**: Enabled (OPTIONS 메서드)

## 테스트

### AWS Console 테스트 이벤트
```json
{
  "headers": {
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "content-type": "image/jpeg",
    "x-filename": "test.jpg"
  },
  "body": "/9j/4AAQSkZJRgABAQEA...",
  "isBase64Encoded": true
}
```

### cURL 테스트
```bash
# 1. 로그인
ACCESS_TOKEN=$(curl -X POST http://alb-dns/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"Test1234!"}' \
  | jq -r '.data.accessToken')

# 2. 이미지 업로드
curl -X POST https://[API_GATEWAY_ID].execute-api.ap-northeast-2.amazonaws.com/prod/images \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: image/jpeg" \
  -H "X-Filename: test.jpg" \
  --data-binary "@test.jpg"
```

## 응답 형식

### 성공 (201)
```json
{
  "message": "upload_image_success",
  "data": {
    "imageUrl": "https://ktb-community-images-prod.s3.ap-northeast-2.amazonaws.com/users/123/images/1699999999999.jpg",
    "fileSize": 524288,
    "originalFilename": "test.jpg",
    "uploadedAt": "2025-11-13T08:00:00.000Z"
  },
  "timestamp": "2025-11-13T08:00:00.000Z"
}
```

### 에러 (4xx/5xx)
```json
{
  "message": "AUTH-003",
  "data": {
    "details": "Invalid token"
  },
  "timestamp": "2025-11-13T08:00:00.000Z"
}
```

## 에러 코드
| 에러 | HTTP | 코드 | 설명 |
|------|------|------|------|
| TOKEN_MISSING | 401 | AUTH-003 | Authorization 헤더 없음 |
| TOKEN_INVALID | 401 | AUTH-003 | JWT 검증 실패 |
| INVALID_FILE_TYPE | 400 | IMAGE-003 | JPG/PNG/GIF만 허용 |
| FILE_TOO_LARGE | 413 | IMAGE-002 | 5MB 초과 |

## CloudWatch 로그
- 로그 그룹: `/aws/lambda/community-upload-image`
- 보존 기간: 7일 (비용 절감)
- 모니터링: Invocations, Duration, Errors

## 비용 추정
- Lambda: $0/월 (Free Tier 1M 요청)
- Parameter Store: $0/월 (Standard Tier)
- S3 PUT: $0.005/1,000 요청
- **총계**: ~$0/월 (이미지 업로드 20K/월 기준)

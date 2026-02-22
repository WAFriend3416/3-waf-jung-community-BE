# 이미지 업로드 테스트

## 테스트 개요
- **목적**: Presigned URL 발급 + S3 직접 업로드 vs Multipart 업로드 성능 비교
- **스크립트**: `scripts/k6/image_upload_test.js`
- **실행 시각**: (테스트 실행 후 기입)
- **소요 시간**: ~4분

## 테스트 환경
- BE 인스턴스: 2대 × t3.medium Spot (HikariCP max=30, JVM -Xms1g -Xmx1500m)
- S3 Bucket: community-loadtest-images (ap-northeast-2)
- 테스트 이미지: 6장 (4~12 KB, JPG/JPEG)
- 데이터: 600 users

## 시나리오 설정
| 시나리오 | Executor | VUs | Stages | 비고 |
|----------|----------|-----|--------|------|
| presigned_upload (70%) | ramping-vus | 0→10→20→20→0 | 20s/1m30s/1m/20s | Presigned URL + S3 PUT |
| multipart_upload (30%) | ramping-vus | 0→5→10→10→0 | 20s/1m30s/1m/20s | Multipart POST |

### Presigned URL 플로우
1. 로그인 → AccessToken 획득
2. `GET /images/presigned-url?filename=...&content_type=...` → upload_url + image_id
3. `PUT {upload_url}` with `x-amz-acl: public-read` → S3 직접 업로드

### Multipart 플로우
1. 로그인 → AccessToken 획득
2. `POST /images` (multipart/form-data, file field) → image_id

## Threshold 결과
| 메트릭 | 값 | Threshold | 판정 |
|--------|-----|-----------|------|
| presigned_url_duration p(95) | — | <500ms | — |
| s3_upload_duration p(95) | — | <3000ms | — |
| multipart_upload_duration p(95) | — | <3000ms | — |
| errors | — | <10% | — |

## 주요 메트릭 상세
| 메트릭 | avg | med | p90 | p95 | p99 | max |
|--------|-----|-----|-----|-----|-----|-----|
| presigned_url_duration | — | — | — | — | — | — |
| s3_upload_duration | — | — | — | — | — | — |
| multipart_upload_duration | — | — | — | — | — | — |

## 업로드 방식 비교
| 방식 | 성공률 | avg | p95 | 처리량 | 서버 부하 |
|------|--------|-----|-----|--------|----------|
| Presigned URL + S3 PUT | — | — | — | — | 낮음 (URL 발급만) |
| Multipart (서버 경유) | — | — | — | — | 높음 (파일 수신 + S3 전송) |

## Check 결과
| Check | 성공 | 실패 | 성공률 |
|-------|------|------|--------|
| presigned URL status 201 | — | — | — |
| presigned URL has uploadUrl | — | — | — |
| s3 upload status 200 | — | — | — |
| multipart upload status 201 | — | — | — |
| multipart upload has imageId | — | — | — |

## 실행 통계
| 항목 | 값 |
|------|-----|
| Total Upload Operations | — |
| Presigned Uploads | — |
| Multipart Uploads | — |
| RPS | — |

## 분석
### 관찰 사항
- (테스트 실행 후 기입)

### Presigned URL vs Multipart
- (서버 CPU 부하 차이, 응답시간 차이, 실패율 차이)

### S3 병목
- (S3 PUT throughput 한계, 네트워크 레이턴시)

### 개선 방안
- (대용량 파일 시 Presigned URL 우위 예상, CDN 도입 가능성)

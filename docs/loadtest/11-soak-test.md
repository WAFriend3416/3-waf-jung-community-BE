# Soak Test + 무중단 배포 검증

## 테스트 개요
- **목적**: 30분 지속 부하 안정성 + Instance Refresh 중 zero-downtime 검증
- **스크립트**: `scripts/k6/soak_test.js`
- **실행 시각**: (테스트 실행 후 기입)
- **소요 시간**: 30분

## 테스트 환경
- BE 인스턴스: 2대 × t3.medium Spot (HikariCP max=30, JVM -Xms1g -Xmx1500m)
- RDS: db.t3.medium Primary + db.t3.small Replica
- 데이터: 600 users, 1,500+ posts, 20,000+ comments

## 시나리오 설정
| 시나리오 | Executor | VUs | Stages | 비고 |
|----------|----------|-----|--------|------|
| read_traffic (70%) | ramping-vus | 0→35→35→0 | 1m/27m/2m | 게시글 목록, 상세, 댓글 |
| write_traffic (30%) | ramping-vus | 0→15→15→0 | 1m/27m/2m | 로그인+쓰기+30% 이미지 업로드 |

### 무중단 배포 시점
- **T+10분**: ASG Instance Refresh 트리거
  ```bash
  aws autoscaling start-instance-refresh \
    --auto-scaling-group-name community-loadtest-be-asg \
    --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 180}'
  ```

## 성공 기준
| 기준 | 목표 | 실제 | 판정 |
|------|------|------|------|
| 에러율 (soak 전체) | < 1% | — | — |
| Instance Refresh 중 5xx | 0건 | — | — |
| p95 < 2× baseline (220ms) | < 220ms | — | — |
| Refresh 전후 p95 차이 | < 50% | — | — |

## Threshold 결과
| 메트릭 | 값 | Threshold | 판정 |
|--------|-----|-----------|------|
| http_req_duration p(95) | — | <1000ms | — |
| http_req_duration p(99) | — | <2000ms | — |
| errors | — | <1% | — |
| login_duration p(95) | — | <500ms | — |
| post_list_duration p(95) | — | <300ms | — |
| post_detail_duration p(95) | — | <300ms | — |

## 주요 메트릭 상세
| 메트릭 | avg | med | p90 | p95 | p99 | max |
|--------|-----|-----|-----|-----|-----|-----|
| http_req_duration | — | — | — | — | — | — |
| login_duration | — | — | — | — | — | — |
| post_list_duration | — | — | — | — | — | — |
| post_detail_duration | — | — | — | — | — | — |
| presigned_url_duration | — | — | — | — | — | — |
| s3_upload_duration | — | — | — | — | — | — |

## 시간대별 성능 추이
| 구간 | p95 응답시간 | 에러율 | RPS | 비고 |
|------|-------------|--------|-----|------|
| 0~5분 (웜업) | — | — | — | |
| 5~10분 (안정) | — | — | — | |
| 10~15분 (Refresh 중) | — | — | — | **Instance Refresh** |
| 15~20분 (Refresh 후) | — | — | — | |
| 20~25분 (후반) | — | — | — | |
| 25~30분 (종료) | — | — | — | |

## 무중단 배포 결과
| 항목 | 값 |
|------|-----|
| Instance Refresh 시작 시각 | — |
| Instance Refresh 완료 시각 | — |
| 소요 시간 | — |
| Refresh 중 5xx 발생 | — |
| Refresh 중 p95 최대값 | — |
| Refresh 중 에러율 최대 | — |
| ALB HealthyHostCount 최저 | — |

## Check 결과
| Check | 성공 | 실패 | 성공률 |
|-------|------|------|--------|
| posts list status 200 | — | — | — |
| post detail status 200/404 | — | — | — |
| comments list status 200/404 | — | — | — |
| login status 200 | — | — | — |
| create post status 201 | — | — | — |
| like post status ok | — | — | — |
| create comment status 201/404 | — | — | — |
| presigned url status 201 | — | — | — |
| s3 upload status 200 | — | — | — |

## 실행 통계
| 항목 | 값 |
|------|-----|
| Total Requests | — |
| RPS (avg) | — |
| Iterations | — |
| Data Received | — |
| Data Sent | — |

## 분석
### Soak 안정성
- (메모리 누수, 커넥션 풀 고갈, GC pause 발생 여부)

### 무중단 배포 분석
- (Instance Refresh 중 요청 유실 여부, ALB drain 동작)

### 관찰 사항
- (테스트 실행 후 기입)

### 개선 방안
- (장시간 운영 시 주의사항, 모니터링 포인트)

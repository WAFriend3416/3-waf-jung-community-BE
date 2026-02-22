# DB 커넥션 풀 스트레스 테스트

## 테스트 개요
- **목적**: HikariCP 커넥션 풀 한계 식별 — 동시 다발적 DB 쓰기 부하
- **스크립트**: `scripts/k6/db_stress_test.js`
- **실행 시각**: (테스트 실행 후 기입)
- **소요 시간**: ~4분

## 테스트 환경
- BE 인스턴스: 2대 × t3.medium Spot (HikariCP max=30, JVM -Xms1g -Xmx1500m)
- RDS: db.t3.medium Primary (max_connections=300) + db.t3.small Replica
- 데이터: 600 users, 1,500 posts

## 시나리오 설정
| 시나리오 | Executor | VUs | Stages | 비고 |
|----------|----------|-----|--------|------|
| db_stress | ramping-vus | 0→30→60→100→0 | 20s/30s 각 단계 | 매 iteration 5~6개 DB 연산 |

### 시나리오 상세 (1 iteration당 DB 연산)
1. 로그인 (SELECT users + INSERT user_tokens)
2. 게시글 조회 (SELECT posts + UPDATE post_stats 조회수)
3. 좋아요 (INSERT post_likes + UPDATE post_stats)
4. 댓글 작성 (INSERT comments + UPDATE post_stats)
5. 게시글 작성 (INSERT posts + INSERT post_stats)
6. 좋아요 취소 (DELETE post_likes + UPDATE post_stats)

## Threshold 결과
| 메트릭 | 값 | Threshold | 판정 |
|--------|-----|-----------|------|
| db_op_duration p(95) | — | <2000ms | — |
| errors | — | <20% | — |

## 주요 메트릭 상세
| 메트릭 | avg | med | p90 | p95 | p99 | max |
|--------|-----|-----|-----|-----|-----|-----|
| db_op_duration | — | — | — | — | — | — |

## VU 단계별 DB 성능
| VU 구간 | p95 DB 연산 시간 | 에러율 | DB ops/s |
|---------|-----------------|--------|----------|
| 30 VUs | — | — | — |
| 60 VUs | — | — | — |
| 100 VUs | — | — | — |

## DB 연산별 성능
| 연산 | 성공률 | 평균 응답시간 | 비고 |
|------|--------|-------------|------|
| 로그인 | — | — | SELECT + INSERT |
| 조회수 증가 | — | — | SELECT + UPDATE |
| 좋아요 | — | — | INSERT + UPDATE |
| 댓글 작성 | — | — | INSERT + UPDATE |
| 게시글 작성 | — | — | INSERT × 2 |
| 좋아요 취소 | — | — | DELETE + UPDATE |

## 실행 통계
| 항목 | 값 |
|------|-----|
| Total Requests | — |
| Total DB Operations | — |
| RPS | — |
| Iterations | — |

## 분석
### 관찰 사항
- (테스트 실행 후 기입)

### 커넥션 풀 분석
- HikariCP max=30 × 2 인스턴스 = 최대 60 커넥션
- RDS max_connections=300
- (풀 고갈 시점, 대기열 발생 여부)

### 병목 지점
- (커넥션 풀 vs RDS CPU vs 네트워크)

### 개선 방안
- (커넥션 풀 사이즈 조정, Read Replica 활용도, 쿼리 최적화)

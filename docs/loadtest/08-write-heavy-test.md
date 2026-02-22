# 쓰기 집중 부하 테스트

## 테스트 개요
- **목적**: DB INSERT/UPDATE 집중 부하 — 지속 쓰기 시 성능 저하 패턴 측정
- **스크립트**: `scripts/k6/write_heavy_test.js`
- **실행 시각**: (테스트 실행 후 기입)
- **소요 시간**: ~4분

## 테스트 환경
- BE 인스턴스: 2대 × t3.medium Spot (HikariCP max=30, JVM -Xms1g -Xmx1500m)
- RDS: db.t3.medium Primary (max_connections=300)
- 데이터: 600 users, 1,500 posts

## 시나리오 설정
| 시나리오 | Executor | VUs | Stages | 비고 |
|----------|----------|-----|--------|------|
| write_stress | ramping-vus | 0→20→50→50→0 | 30s/2m/1m/30s | 100% 쓰기 작업 |

### 시나리오 상세 (1 iteration당 쓰기 연산)
1. 로그인 (INSERT user_tokens) — 1회
2. 게시글 작성 (INSERT posts + INSERT post_stats) — 1회
3. 좋아요 (INSERT post_likes + UPDATE post_stats) — 3회 연속
4. 댓글 작성 (INSERT comments + UPDATE post_stats) — 5회 연속
5. 좋아요 취소 (DELETE post_likes + UPDATE post_stats) — 1회
6. 로그아웃 (DELETE user_tokens) — 1회

**총 DB 쓰기 연산**: ~12 operations/iteration

## Threshold 결과
| 메트릭 | 값 | Threshold | 판정 |
|--------|-----|-----------|------|
| http_req_duration p(95) | — | <1000ms | — |
| errors | — | <10% | — |

## 주요 메트릭 상세
| 메트릭 | avg | med | p90 | p95 | p99 | max |
|--------|-----|-----|-----|-----|-----|-----|
| http_req_duration | — | — | — | — | — | — |
| write_duration | — | — | — | — | — | — |

## 쓰기 연산별 성능
| 연산 | 성공률 | avg | p95 | 비고 |
|------|--------|-----|-----|------|
| 로그인 | — | — | — | BCrypt + INSERT |
| 게시글 작성 | — | — | — | INSERT × 2 |
| 좋아요 | — | — | — | INSERT + UPDATE |
| 댓글 작성 | — | — | — | INSERT + UPDATE |
| 좋아요 취소 | — | — | — | DELETE + UPDATE |
| 로그아웃 | — | — | — | DELETE |

## 실행 통계
| 항목 | 값 |
|------|-----|
| Total Requests | — |
| Total Write Operations | — |
| RPS | — |
| Iterations | — |

## 분석
### 관찰 사항
- (테스트 실행 후 기입)

### 쓰기 성능 분석
- 초당 쓰기 연산 수: —
- DB WriteIOPS 피크: —
- post_stats 동시성 제어 (원자적 UPDATE) 효과: —

### 병목 지점
- (DB CPU, InnoDB lock contention, 커넥션 풀)

### 개선 방안
- (배치 INSERT, 비동기 쓰기, 큐 도입 가능성)

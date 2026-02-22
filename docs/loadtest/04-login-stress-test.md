# 로그인 스트레스 테스트

## 테스트 개요
- **목적**: JWT 생성 + BCrypt 해싱 병목 측정 — CPU-bound 연산 한계 식별
- **스크립트**: `scripts/k6/login_stress_test.js`
- **실행 시각**: (테스트 실행 후 기입)
- **소요 시간**: ~4분

## 테스트 환경
- BE 인스턴스: 2대 × t3.medium Spot (HikariCP max=30, JVM -Xms1g -Xmx1500m)
- RDS: db.t3.medium Primary + db.t3.small Replica
- 데이터: 600 users

## 시나리오 설정
| 시나리오 | Executor | VUs | Stages | 비고 |
|----------|----------|-----|--------|------|
| login_stress | ramping-vus | 0→30→50→100→0 | 20s/1m/1m/30s | 로그인 → 로그아웃 반복 |

### 시나리오 상세
1. 랜덤 사용자(1~600)로 로그인 (`POST /auth/login`)
2. 0.5초 대기
3. 로그아웃 (`POST /auth/logout`)
4. 1초 대기 후 반복

## Threshold 결과
| 메트릭 | 값 | Threshold | 판정 |
|--------|-----|-----------|------|
| login_duration p(95) | — | <500ms | — |
| errors | — | <10% | — |

## 주요 메트릭 상세
| 메트릭 | avg | med | p90 | p95 | p99 | max |
|--------|-----|-----|-----|-----|-----|-----|
| login_duration | — | — | — | — | — | — |

## VU 단계별 로그인 성능
| VU 구간 | p95 로그인 응답시간 | 에러율 | 초당 로그인 수 |
|---------|-------------------|--------|------------|
| 30 VUs | — | — | — |
| 50 VUs | — | — | — |
| 100 VUs | — | — | — |

## Check 결과
| Check | 성공 | 실패 | 성공률 |
|-------|------|------|--------|
| login 200 | — | — | — |
| has token | — | — | — |
| logout ok | — | — | — |

## 실행 통계
| 항목 | 값 |
|------|-----|
| Total Requests | — |
| Login Count | — |
| RPS | — |
| Iterations | — |

## 분석
### 관찰 사항
- (테스트 실행 후 기입)

### BCrypt 병목 분석
- (p95 500ms 초과 시점, CPU 사용률과의 상관관계)

### 개선 방안
- (BCrypt cost factor 조정, 캐싱, 인스턴스 스케일아웃 효과 분석)

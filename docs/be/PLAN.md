# PLAN.md - KTB Community 프로젝트 구현 계획

## 프로젝트 개요

**프로젝트명**: KTB Community Platform
**기술 스택 및 아키텍처**: **@docs/be/LLD.md Section 1-2** 참조

---

## 현재 진행 상황

**Phase 1 완료** ✅
**Phase 2 완료** ✅ (Week 2-3)
**Phase 3 완료** ✅ (Week 4-5)
**Phase 3.5 완료** ✅ (S3 이미지 업로드)
**Phase 3.6 완료** ✅ (회원가입/프로필 Multipart 전환 + P0/P1 수정)

---

## 전체 로드맵

| Phase | Week | 목표 | FR 범위 | 상태 |
|-------|------|------|---------|------|
| Phase 1 | 1 | 기반 설정 | - | ✅ 완료 |
| Phase 2 | 2-3 | 인증/사용자 | AUTH-001~004, USER-001~004 | ✅ 완료 |
| Phase 3 | 4-5 | 게시글/댓글/좋아요 | POST-001~005, COMMENT-001~004, LIKE-001~003 | ✅ 완료 |
| Phase 3.5 | 5 | 이미지 업로드 (S3) | IMAGE-001, IMAGE-003 | ✅ 완료 |
| Phase 3.6 | 5 | Multipart 전환 + P0/P1 수정 | AUTH-001, USER-002 | ✅ 완료 |
| Phase 4 | 6 | 통계 및 배치 | IMAGE-002 (고아 이미지) | ✅ 완료 |
| Phase 5 | 7 | 테스트/문서 + 버그 수정 | detached entity 해결 | ⏳ 진행 예정 |
| Phase 6 | 8+ | Redis 도입 (조건부) | 성능 최적화 | ⏸️ 조건 대기 |

---

## Phase 1: 프로젝트 기반 설정 ✅ 완료

**목표**: 개발 환경 구축 및 데이터베이스 스키마 구축

| 구성 요소 | 완료 내용 |
|----------|----------|
| 프로젝트 | Spring Boot 3.5.6, Java 24, Gradle 8.x |
| 데이터베이스 | MySQL 8.0+, HikariCP |
| Entity 클래스 | 8개 (User, Post, Comment, PostLike, Image, UserToken, PostStats, PostImage) |
| Enum 클래스 | 4개 (UserRole, UserStatus, PostStatus, CommentStatus) |
| 패키지 구조 | 3-Layer Architecture (Controller-Service-Repository) |

**참조**: **@docs/be/LLD.md Section 3** (패키지 구조), **@docs/be/DDL.md** (스키마)

---

## Phase 2: 인증 및 사용자 관리 ✅ 완료

**목표**: JWT 기반 인증 시스템 및 사용자 CRUD 구현

| 구성 요소 | 완료 내용 | 테스트 결과 |
|----------|----------|------------|
| **인증 시스템** | JwtTokenProvider, UserToken(RDB), Spring Security, BCrypt | JwtTokenProvider 9/9 ✅ |
| **API** | 인증 3개 (/login, /logout, /refresh_token), 사용자 5개 (/signup, /{id}, /{id}/password 등) | AuthService 8/8, UserService 7/7 ✅ |
| **비즈니스 로직** | 비밀번호 정책, 이메일/닉네임 중복 확인, Rate Limiting (3-Tier) | RateLimitAspect 10/10 ✅ |
| **동시성 제어** | PostStats 원자적 UPDATE (JPQL) | Repository 12/12 (H2) ✅ |
| **FR 매핑** | FR-AUTH-001~004, FR-USER-001~004 | 전체 15/15 (100%) ✅ |

**참조**: **@docs/be/LLD.md Section 6** (인증 및 보안), **@docs/be/API.md Section 1-2**

---

## Phase 3: 게시글 및 댓글 기능 ✅ 완료

**목표**: 커뮤니티 핵심 기능 구현

| 구성 요소 | 완료 내용 | 테스트 결과 |
|----------|----------|------------|
| **게시글 기능** | PostService (CRUD, 페이지네이션, 정렬), API 6개, 조회수 자동 증가, 권한 검증 | PostServiceTest 11/11 ✅ |
| **댓글 기능** | CommentService (CRUD), API 4개, 댓글 수 자동 업데이트, 권한 검증 | CommentServiceTest 10/10 ✅ |
| **좋아요 기능** | LikeService (추가/취소), API 3개, 중복 방지 (UNIQUE), 좋아요 수 자동 업데이트 | LikeServiceTest 9/9 ✅ |
| **Repository** | Fetch Join (N+1 방지), JPQL 최적화 (Post, Comment, PostLike, Image) | Repository 12/12 (H2) ✅ |
| **FR 매핑** | FR-POST-001~005, FR-COMMENT-001~004, FR-LIKE-001~003 | 전체 98/98 (100%) ✅ |

**참조**: **@docs/be/LLD.md Section 7** (비즈니스 로직), **@docs/be/API.md Section 3, 5, 6**

---

## Phase 3.5: 이미지 업로드 인프라 ✅ 완료

**목표**: S3 직접 연동 이미지 업로드 시스템 구현

| 구성 요소 | 완료 내용 |
|----------|----------|
| **이미지 업로드** | ImageService (파일 검증, S3 업로드, DB 저장), ImageController (POST /images), S3Client (AWS SDK v2), TTL 1시간 |
| **통합** | PostService/UserService 이미지 연결 (clearExpiresAt), PostImage 브릿지 테이블 |
| **FR 매핑** | FR-IMAGE-001 (이미지 정보 저장), FR-IMAGE-003 (이미지 업로드) |
| **테스트** | ImageService, 파일 검증, S3 업로드 통합 테스트 ✅ |

**참조**: **@docs/be/LLD.md Section 7.5**, **@docs/be/API.md Section 4.1**

---

## Phase 3.6: 회원가입/프로필 Multipart 전환 ✅ 완료

**목표**: 회원가입과 프로필 수정 시 이미지와 데이터를 함께 전송하는 자연스러운 UX 구현

| 구성 요소 | 완료 내용 | 테스트 결과 |
|----------|----------|------------|
| **문서/DTO/Controller** | PLAN.md, PRD.md, API.md, LLD.md 업데이트; SignupRequest/UpdateProfileRequest 수정; @RequestPart 적용 | Manual Validation 검증 ✅ |
| **Service** | AuthService.signup(), UserService.updateProfile() - ImageService 통합 (MultipartFile) | AuthServiceTest, UserServiceTest ✅ |
| **FR 매핑** | FR-AUTH-001, FR-USER-002 (2단계 → Multipart 직접 업로드) | 102 tests (100%) ✅ |
| **P0/P1 수정** | Manual Validation 복원, PasswordValidator ErrorCode 일관성 (USER-004) | P0/P1 해결 ✅ |

**참조**: **@docs/be/LLD.md Section 7.5** (2가지 업로드 패턴), **@docs/be/API.md Section 2.1, 2.3**

---

## Phase 4: 통계 및 배치 작업 ✅ 완료

**목표**: 게시글 통계 활용 및 고아 이미지 정리 배치 구현

| 구성 요소 | 완료 내용 | 테스트 결과 |
|----------|----------|------------|
| **통계 기능** | PostStats 자동 업데이트, 통계 기반 정렬 (like_count DESC), N+1 방지 | Phase 3 완료 ✅ |
| **고아 이미지 배치** | @Scheduled (매일 3AM), expires_at < NOW() 조건, S3 + DB 삭제, 배치 로그 | ImageCleanupBatchServiceTest ✅ |
| **만료 토큰 배치** | @Scheduled (매일 3AM), user_tokens 테이블 정리, JPQL DELETE | TokenCleanupBatchServiceTest 4/4 ✅ |

**참조**: **@docs/be/LLD.md Section 7.5** (고아 이미지 처리)

---

## Phase 5: 테스트 및 문서화

**목표**: 품질 확보 및 문서 정리

### 체크리스트

**Phase 4 버그 수정:**
- [x] PostService detached entity 문제 해결
  - 해결: `clearAutomatically = false` 적용 (PostStatsRepository 5개 메서드)
  - 부가효과: Optimistic Update 패턴 도입으로 DB 통신 17% 감소
  - 영향: PostService.getPostDetail(), LikeService (2개 메서드), PostController (2개 메서드)
  - 변경 파일: 9개 (Backend 5개, Frontend 1개, Docs 2개, Test 1개)
  - 상세: 이 대화 스레드 "Optimistic Update 패턴 도입" 참조

**Optimistic Update 패턴:**
- [x] 좋아요 API 응답 간소화 (like_count 제거)
- [x] 클라이언트 UI 즉시 업데이트 + 에러 시 Rollback
- [x] 원자적 쿼리 유지 (100% 데이터 정확도)
- [x] DB 통신: 6번 → 5번 (17% 성능 개선)


**페이지네이션:**
- [x] Cursor 페이지네이션 전환 (최신순만, 하이브리드 방식)
  - Repository: findByStatusWithCursor, findByStatusWithoutCursor 추가
  - Service: getPosts 시그니처 변경 (cursor, offset 파라미터)
  - Controller: cursor/offset 파라미터 추가
  - 응답 구조: latest (cursor/hasMore), likes (offset/total_count)
- [ ] Cursor 페이지네이션 확장 (likes 정렬, 추후 작업)
- [ ] GET /posts/users/me/likes cursor 전환 (추후 작업)

**테스트:**
- [ ] 전체 Service Layer 테스트 (커버리지 80%+)
- [ ] Repository Layer 테스트 (커버리지 60%+)
- [ ] 통합 테스트 주요 플로우

**문서화:**
- [ ] @docs/be/API.md 최종 검토
- [ ] Postman Collection 작성
- [ ] README 업데이트

**코드 품질:**
- [ ] 코드 리뷰 및 리팩토링
- [ ] 네이밍 컨벤션 통일
- [ ] 불필요한 주석 제거

### 완료 조건
- 전체 테스트 커버리지 60% 이상
- API 문서 최신화
- 코드 리뷰 완료

---

## 개발 규칙

**Phase 완료 기준:**
1. 모든 체크리스트 완료
2. 단위 테스트 통과 (Service 80%+)
3. 완료 조건 검증
4. PLAN.md 체크박스 업데이트

**문서 동기화:**
- 자동: Documentation Sync Manager 스킬 (`문서 동기화`, pre-commit hook)
- 참조: `.claude/skills/Documentation Sync Manager/SKILL.md`

---

## 제약사항 (설계 배경)

**기술 제약**: 토큰 RDB 저장 → Redis 전환, S3 직접 저장
**성능 가정**: 초기 트래픽 낮음, 단일 서버, 원자적 UPDATE
**데이터 정책**: Soft Delete (User/Post/Comment), Hard Delete (UserToken/Image)

**상세**: **@docs/be/PRD.md Section 5**, **@docs/be/LLD.md Section 7.5, 12.3**

---

---

## 주요 리스크

| 리스크 | 대응 방안 |
|--------|-----------|
| JWT RDB 성능 저하 | 인덱스 최적화, Redis 전환 |
| 동시성 이슈 | 원자적 UPDATE, 락 전략 |
| 고아 이미지 누적 | TTL 기반 배치 삭제 (Phase 4) |
| S3 비용 초과 | Free Tier 모니터링, 압축 최적화 |

---

## 참고 문서

- **요구사항**: @docs/be/PRD.md (FR/NFR 코드)
- **설계**: @docs/be/LLD.md (아키텍처, 패턴)
- **스키마**: @docs/be/DDL.md
- **API**: @docs/be/API.md
- **가이드**: @CLAUDE.md

---

## 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|-----------|
| 2025-10-01 | 1.0 | 초기 PLAN.md 작성 (Phase 1-6 로드맵) |
| 2025-11-12 | 1.1 | 문서 최적화 - Phase 1-4 테이블 요약 형식으로 전환 (1,500 tokens 절감) |
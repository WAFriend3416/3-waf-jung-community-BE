# LLD.md - Low Level Design Document

## 문서 정보

| 항목 | 내용                        |
|------|**3가지 패턴 비교:**

| 항목 | Multipart 직접 업로드 | 2단계 업로드 | 이미지 제거 |
|------|---------------------|-------------|-----------|
| **사용처** | 회원가입, 프로필 수정 | 게시글 작성/수정 | 프로필 수정 |
| **요청 횟수** | 1회 (multipart/form-data) | 2회 (POST /images → POST /posts) | 1회 (removeImage: true) |
| **트랜잭션** | 원자적 (이미지 포함) | 독립적 (이미지 선행) | 원자적 (TTL 복원) |
| **UX 장점** | 간편함, 한 번에 완료 | 미리보기, 임시 저장 지원 | 명시적 제거 의도 |
| **핵심 메서드** | AuthService.signup() | PostService.createPost() | UserService.updateProfile() |------|
| 프로젝트명 | KTB Community Platform    |
| 버전 | 1.7                       |
| 문서 유형 | Low Level Design Document |

---

## 1. 기술 스택

**백엔드:** Spring Boot 3.5.6, Java 24, Gradle 8.x  
**데이터베이스:** MySQL 8.0+, JPA (Hibernate), HikariCP  
**보안:** Spring Security, JWT, BCrypt  
**Storage:** AWS S3 (이미지 직접 저장, Free Tier)  
**추후:** Redis (토큰 캐싱)

**패키지 루트:** `com.ktb.community`

---

## 2. 시스템 아키텍처

### 2.1 전체 구조

```
Client (Frontend)
    ↓ HTTPS REST API
Controller Layer (요청/응답 처리)
    ↓
Service Layer (비즈니스 로직, @Transactional)
    ↓
Repository Layer (데이터 접근, JPA)
    ↓
MySQL Database
```

### 2.2 계층별 책임

**Controller:**
- DTO 검증: @Valid + Bean Validation (표준), Manual Validation (@RequestPart 예외)
- 요청 → Service 전달, 응답 포매팅
- 예외 메시지: 영어 통일 (ErrorCode 기본 메시지와 일관성)
- **권한**: GET(조회)는 public, POST/PATCH/DELETE(작성/수정/삭제)는 Authentication 필수
- 위치: `com.ktb.community.controller`

**Service:**
- 비즈니스 로직, 트랜잭션 관리
- 엔티티 ↔ DTO 변환
- 위치: `com.ktb.community.service`

**Repository:**
- CRUD, 커스텀 쿼리 (JPA)
- 위치: `com.ktb.community.repository`

---

## 3. 패키지 구조

**주요 패키지:**
- `config/` - 애플리케이션 설정 (Security, JPA, S3, RateLimit)
- `controller/` - REST API 엔드포인트 (Auth, User, Post, Comment, Image)
- `service/` - 비즈니스 로직 (Auth, User, Post, Comment, Like, Image)
- `repository/` - 데이터 접근 계층 (JPA Repository)
- `entity/` - JPA 엔티티 및 복합키
- `dto/` - 요청/응답 DTO (request, response)
- `security/` - JWT 토큰 관리 및 인증 필터
- `exception/` - 예외 처리 (GlobalExceptionHandler, BusinessException)
- `util/` - 공통 유틸리티 (Validator, S3KeyGenerator)
- `enums/` - 열거형 (UserStatus, PostStatus, CommentStatus, UserRole)

**패키지 루트:** `com.ktb.community`
**상세 파일 구조:** IDE 탐색 또는 프로젝트 루트 참조

---

## 4. 데이터베이스 설계

**테이블 구조 및 DDL:** `@docs/be/DDL.md` 참조

**핵심 관계:**
- `users` 1:N → `posts`, `comments`, `post_likes`, `user_tokens`
- `posts` 1:1 → `post_stats`, 1:N → `comments`, M:N → `images` (via `post_images`)
- `post_likes` 복합 유니크 키: `(user_id, post_id)` 중복 방지

**주요 인덱스:**
- `users`: email, nickname (UNIQUE), user_status
- `posts`: created_at, (user_id, created_at)
- `comments`: (post_id, created_at, comment_id)
- `post_likes`: post_id, (user_id, post_id) UNIQUE

---

## 5. API 설계

**전체 API 스펙 및 엔드포인트 목록**: **@docs/be/API.md** 참조

### 공통 응답 구조
```json
{
  "message": "작업_결과_메시지",
  "data": { /* 응답 데이터 또는 null */ },
  "timestamp": "2025-10-01T14:30:00"
}
```

---

## 6. 인증 및 보안

### 6.1 JWT 토큰

**3가지 토큰 타입:**

| 토큰 타입 | 유효기간 | 용도 | DB 저장 | Refresh Token |
|----------|---------|------|---------|--------------|
| Access Token (AT) | 15분 | API 인증 | ❌ | ✅ |
| Refresh Token (RT) | 7일 | AT 갱신 | ✅ user_tokens | ❌ |
| Guest Token | 5분 | 회원가입 이미지 업로드 | ❌ | ❌ |

**Access Token (AT):**
- **유효기간**: 15분 (900,000ms)
- **용도**: API 인증
- **전달**: Authorization: Bearer {token}
- **저장**: 클라이언트 JS 메모리

**Refresh Token (RT):**
- **유효기간**: 7일 (604,800,000ms)
- **용도**: Access Token 갱신
- **전달**: httpOnly Cookie (SameSite=Lax, Path=/auth)
- **저장**: user_tokens 테이블 (RDB)

**Guest Token:**
- **유효기간**: 5분 (300,000ms)
- **용도**: 회원가입 시 프로필 이미지 업로드
- **전달**: Authorization: Bearer {guestToken}
- **저장**: 없음 (stateless)
- **특징**: Refresh Token 없음, DB 저장 없음, 일회용
- **발급**: GET /auth/guest-token
- **Payload**: subject=guest-{UUID}, role=GUEST

**Payload 예시 (User Token):**
```json
{
  "sub": "user_id",
  "email": "user@example.com",
  "role": "USER",
  "iat": 1234567890,
  "exp": 1234569690
}
```

**Payload 예시 (Guest Token):**
```json
{
  "sub": "guest-550e8400-e29b-41d4-a716-446655440000",
  "role": "GUEST",
  "iat": 1234567890,
  "exp": 1234568190
}
```

### 6.2 인증 흐름 (JWT + Authorization Header)

**현재 구현:** 순수 Servlet Filter 기반 (`filter/JwtAuthenticationFilter.java`)

**로그인:**
1. Client → POST /auth/login (credentials: 'include')
2. 서버 → BCrypt 검증
3. 서버 → Access + Refresh 토큰 생성
4. 서버 → httpOnly Cookie 발급 (refresh_token만), Access Token은 응답 body
5. 서버 → Refresh를 user_tokens 테이블에 저장
6. 클라이언트 → AT는 JS 메모리 저장, RT는 Cookie 자동 저장

**API 호출 (Authorization Header):**
1. Client → API 요청 (`Authorization: Bearer {access_token}`)
2. JwtAuthenticationFilter (순수 Servlet Filter, @Order(1))
   - Authorization header에서 토큰 추출
   - JWT 검증 (JwtTokenProvider)
   - userId 추출 및 Request Attribute 저장 (`req.setAttribute("userId", userId)`)
3. Controller → HttpServletRequest에서 userId 추출
4. 비즈니스 로직 실행

**토큰 갱신:**
1. Client → POST /auth/refresh_token (credentials: 'include')
2. 서버 → Cookie에서 refresh_token 추출
3. 서버 → user_tokens 테이블 검증
4. 서버 → 새 access_token 발급 → 응답 body (RT 재사용)

**필터 구현 예시:**
```java
@Component
@Order(1)
public class JwtAuthenticationFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response,
                         FilterChain chain) {
        // 1. Authorization header에서 토큰 추출
        String bearerToken = req.getHeader("Authorization");
        String jwt = bearerToken.substring(7); // "Bearer " 제거

        // 2. JWT 검증
        if (!jwtTokenProvider.validateToken(jwt)) {
            sendUnauthorized(res, "Invalid token");
            return;
        }

        // 3. userId 추출 및 Request Attribute 저장
        Long userId = jwtTokenProvider.getUserIdFromToken(jwt);
        req.setAttribute("userId", userId);

        chain.doFilter(request, response);
    }
}
```

**Controller 통합:**
```java
@PostMapping
public ResponseEntity<ApiResponse<PostResponse>> createPost(
        @RequestBody PostCreateRequest request,
        HttpServletRequest httpRequest) {

    Long userId = (Long) httpRequest.getAttribute("userId");
    PostResponse post = postService.createPost(request, userId);
    return ResponseEntity.ok(ApiResponse.success("create_post_success", post));
}
```

**공개 엔드포인트 처리:**
- GET /posts, GET /users/{id}: 선택적 인증 (JWT 있으면 검증, 없으면 통과)
- POST /posts, PATCH /users/{id}: 필수 인증 (JWT 없으면 401)
- OPTIONS 요청: 통과 (CORS Preflight)

### 6.3 핵심 보안 설정 (CORS + CSRF)

**SecurityConfig 핵심:**
```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOrigins(List.of(frontendUrl));  // Express.js
    config.setAllowedMethods(List.of("GET", "POST", "PATCH", "DELETE", "OPTIONS"));
    config.setAllowedHeaders(List.of("*"));
    config.setAllowCredentials(true);  // Cookie 전송 허용
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
}

@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .csrf(csrf -> csrf
                    .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
                    .ignoringRequestMatchers(
                            "/auth/**",           // 인증 관련
                            "/users/**",          // 사용자 관련 (회원가입, 프로필 수정 등)
                            "/posts/**",          // 게시글 관련 모든 API
                            "/images/**"          // 이미지 업로드
                    )
            )
            .sessionManagement(session ->
                    session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                    // ========== 순서 중요: 구체적인 패턴 먼저! ==========

                    // 1. 특수 케이스 - GET이지만 인증 필요
                    .requestMatchers(HttpMethod.GET, "/posts/users/me/likes").authenticated()
                    
                    // 2. Public GET 엔드포인트
                    .requestMatchers(HttpMethod.GET, 
                            "/posts",                // 게시글 목록
                            "/posts/*",              // 게시글 상세
                            "/posts/*/comments",     // 댓글 목록
                            "/users/*"               // 사용자 프로필 (공개)
                    ).permitAll()
                    
                    // 3. 인증 필요 - Posts
                    .requestMatchers(HttpMethod.POST, "/posts").authenticated()
                    .requestMatchers(HttpMethod.PATCH, "/posts/*").authenticated()
                    .requestMatchers(HttpMethod.DELETE, "/posts/*").authenticated()
                    .requestMatchers(HttpMethod.POST, "/posts/*/like").authenticated()
                    .requestMatchers(HttpMethod.DELETE, "/posts/*/like").authenticated()
                    
                    // 4. 인증 필요 - Comments
                    .requestMatchers(HttpMethod.POST, "/posts/*/comments").authenticated()
                    .requestMatchers(HttpMethod.PATCH, "/posts/*/comments/*").authenticated()
                    .requestMatchers(HttpMethod.DELETE, "/posts/*/comments/*").authenticated()
                    
                    // 5. 인증 필요 - Users
                    .requestMatchers(HttpMethod.PATCH, "/users/*").authenticated()
                    .requestMatchers(HttpMethod.PATCH, "/users/*/password").authenticated()
                    
                    // 6. 인증 필요 - Images
                    .requestMatchers(HttpMethod.POST, "/images").authenticated()
                    
                    // 7. Public - Auth
                    .requestMatchers("/auth/login", "/auth/refresh_token", "/users/signup").permitAll()

                    // 8. Public - Legal & Static Resources
                    .requestMatchers("/terms", "/privacy", "/css/**").permitAll()

                    // 9. 나머지는 인증 필요
                    .anyRequest().authenticated()
            )
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

    return http.build();
}
```

**보안 강화 요소:**
- **CORS**: Express.js 연동 (allowCredentials: true)
- **CSRF**: Cookie 기반 토큰, API 엔드포인트는 제외 (/auth/**, /users/**, /posts/**, /images/**)
  - 제외 이유: JWT httpOnly Cookie 기반 인증이 CSRF 보호 제공
  - Cross-origin 환경 (localhost:3000 → localhost:8080)에서 CSRF 토큰 접근 불가 해결
- **Cookie**: httpOnly (XSS 방어), SameSite=Strict (CSRF 방어)

**권한 제어:**
- Spring Security가 HTTP Method별로 엔드포인트 접근 제어
- GET(조회)는 permitAll(), POST/PATCH/DELETE는 authenticated()
- Controller는 Authentication 파라미터로 userId 추출 (Security 검증 완료 후)

### 6.4 비밀번호 정책

**정책:**
- 길이: 8자 이상, 20자 이하
- 대문자: 최소 1개 (`[A-Z]`)
- 소문자: 최소 1개 (`[a-z]`)
- 특수문자: 최소 1개 (`[!@#$%^&*(),.?":{}|<>]`)

**구현:**
```java
public class PasswordValidator {
    private static final String REGEX =
        "^(?=.*[a-z])(?=.*[A-Z])(?=.*[!@#$%^&*(),.?\":{}|<>]).{8,20}$";

    public static boolean isValid(String password) {
        return password != null && password.matches(REGEX);
    }
}
```

### 6.5 Rate Limiting

**정책:**
- 제한: 엔드포인트별 개별 설정 (5~200회/분, Tier 전략)
- 키: FQCN.methodName + IP 주소 + 사용자 ID (인증 시)
- 저장소: 인메모리 (Caffeine Cache), 추후 Redis
- 응답: 429 Too Many Requests

**설계 결정사항:**

| 항목 | 선택 | 이유 |
|------|------|------|
| 알고리즘 | Token Bucket | Burst traffic 허용, 점진적 refill, 산업 표준 |
| 라이브러리 | Bucket4j | Redis 전환 용이, 경량, Spring 친화적 |
| 캐시 | Caffeine | 자동 만료 (10분), 메모리 상한 (10k), LRU 지원 |
| 키 형식 | FQCN.methodName:IP:userId | 패키지 다른 동일 클래스명 충돌 방지 |
| 엔드포인트 격리 | FQCN 포함 | RESTful CRUD 메서드명 중복 대응 |

**구현 (AOP):**
```java
@Aspect
@Component
public class RateLimitAspect {
    // Caffeine Cache: 10분 미사용 시 자동 삭제, 최대 10,000개
    private final Cache<String, Bucket> buckets = Caffeine.newBuilder()
        .expireAfterAccess(10, TimeUnit.MINUTES)
        .maximumSize(10_000)
        .build();

    @Around("@annotation(rateLimit)")
    public Object rateLimit(ProceedingJoinPoint pjp, RateLimit rateLimit) throws Throwable {
        String clientKey = getClientKey(pjp);
        int requestsPerMinute = rateLimit.requestsPerMinute();

        // Token Bucket: 600ms마다 1개 토큰 refill
        Bucket bucket = buckets.get(clientKey, k -> createBucket(requestsPerMinute));

        if (!bucket.tryConsume(1)) {
            throw new BusinessException(ErrorCode.TOO_MANY_REQUESTS);
        }
        return pjp.proceed();
    }

    // 키 예시: "com.ktb.community.controller.AuthController.login:192.168.1.1:123" (FQCN:IP:userId)
    private String getClientKey(ProceedingJoinPoint pjp) {
        String methodName = pjp.getSignature().getDeclaringTypeName()
                          + "." + pjp.getSignature().getName();
        // ... IP + userId 조합
        return methodName + ":" + userKey;
    }
}
```

**적용 대상 (3-Tier 전략):**

**Tier 1 (5회/분) - 강한 제한:**
- AuthController.login - brute-force 방지
- UserController.changePassword - enumeration 방지

**Tier 2 (10-50회/분) - 중간 제한:**
- UserController.signup (10회/분) - spam bot, 정상 사용자 재시도 고려
- AuthController.refreshToken (30회/분) - 비정상 토큰 갱신 감지
- UserController.updateProfile (30회/분) - 프로필 수정 spam 방지
- UserController.deactivateAccount (10회/분) - 계정 비활성화 남용 방지
- PostController.createPost (30회/분) - 게시글 spam 방지
- CommentController.createComment (50회/분) - 댓글 spam 방지 (더 빈번)
- ImageController.uploadImage (10회/분) - 파일 업로드 부하

**Tier 3 (제한 없음 또는 200회/분) - 약한 제한/해제:**
- 모든 GET 조회 API - 제한 없음 (페이지네이션으로 제어)
- AuthController.logout - 제한 없음 (공격 동인 없음)
- PostController.likePost/unlikePost (200회/분) - 빈번한 액션, 원자적 UPDATE
- Post/Comment 수정 API (50회/분) - 본인 권한 검증 있음
- Post/Comment 삭제 API (30회/분) - Soft Delete

---

## 7. 주요 비즈니스 로직

### 7.1 게시글 작성 흐름

**핵심 단계:**
1. 사용자 검증 (ACTIVE 필터링 - Soft Delete 정책)
2. 게시글 생성 및 저장 (DTO → Entity 변환)
3. 통계 초기화 (PostStats, Builder 기본값 0)
4. 양방향 연관관계 동기화 (savedPost.updateStats)
5. 이미지 TTL 해제 (imageId 있을 경우, clearExpiresAt)

**설계 결정사항:**
- **예외**: BusinessException + ErrorCode 사용 (ResourceNotFoundException 아님)
- **통계 초기화**: Builder 기본값 의존 (명시적 0 설정 불필요)
- **updateStats() 필수**: 양방향 연관관계 동기화, PostResponse null 방지
- **이미지 TTL**: clearExpiresAt() 호출로 영구 보존 전환

**구현:** PostService.createPost() (Line 49-105)

### 7.2 페이지네이션

**하이브리드 전략 (Phase 5)**: latest(cursor), likes(offset)

#### Cursor 기반 (latest 전용)
```java
// Repository
@Query("SELECT p FROM Post p JOIN FETCH p.user LEFT JOIN FETCH p.stats " +
       "WHERE p.postStatus = :status AND p.postId < :cursor " +
       "ORDER BY p.postId DESC")
List<Post> findByStatusWithCursor(PostStatus status, Long cursor, Pageable pageable);

// Service (limit+1 패턴)
List<Post> posts = (cursor == null)
    ? postRepository.findByStatusWithoutCursor(PostStatus.ACTIVE, PageRequest.of(0, limit + 1))
    : postRepository.findByStatusWithCursor(PostStatus.ACTIVE, cursor, PageRequest.of(0, limit + 1));

boolean hasMore = posts.size() > limit;
if (hasMore) posts.remove(limit);

Long nextCursor = hasMore && !posts.isEmpty()
    ? posts.get(posts.size() - 1).getPostId()
    : null;

// 응답: { posts, nextCursor, hasMore }
```

**장점:**
- 인덱스 활용 (postId PRIMARY KEY)
- 실시간 안정성 (중간 데이터 변경에 안전)
- 무한 스크롤 최적화

**단점:**
- 특정 페이지 번호 이동 불가
- total_count 제공 불가

#### Offset/Limit (likes 등)
```java
int page = offset / limit;
Pageable pageable = PageRequest.of(page, limit, getSort(sort));
Page<Post> postPage = postRepository.findByStatusWithUserAndStats(PostStatus.ACTIVE, pageable);

// 응답: { posts, pagination: { total_count } }
```

**장점:**
- 페이지 번호 네비게이션
- total_count 제공 (UX)

**단점:**
- Offset 클수록 성능 저하
- 실시간 데이터 변경에 취약

**현재 구현:**
- GET /posts?sort=latest → Cursor
- GET /posts?sort=likes → Offset
- GET /posts/{postId}/comments → Offset (변경 없음)

**향후 계획:**
- likes 정렬 cursor 전환 (복합 cursor: likeCount:postId)
- GET /posts/users/me/likes cursor 전환

### 7.3 댓글 작성 흐름

**핵심 단계:**
1. 게시글 존재 확인 (Fetch Join, ACTIVE만)
2. 사용자 확인 (ACTIVE 필터링 - Soft Delete 정책)
3. 댓글 생성 및 저장
4. 댓글 수 자동 증가 (동시성 제어 - 원자적 UPDATE)

**설계 결정사항:**
- **Repository 메서드**: findByIdWithUserAndStats (Fetch Join + ACTIVE 필터링)
- **동시성 제어**: incrementCommentCount() - DB 레벨 원자적 UPDATE (Section 12.3)
- **트랜잭션 경계**: 댓글 저장 + 통계 증가가 동일 트랜잭션 (원자성 보장)
- **권한 검증**: 작성자 본인만 수정/삭제 가능 (userId 비교)

**구현**: CommentService.createComment() (Line 48-75)
**참조**: **@docs/be/API.md Section 5**, **@docs/be/DDL.md** (comments 테이블)

---

### 7.4 이미지 업로드 전략

**3가지 패턴 비교:**

| 항목 | Multipart 직접 업로드 | 2단계 업로드 | 이미지 제거 |
|------|---------------------|-------------|-----------|
| **사용처** | 회원가입, 프로필 수정 | 게시글 작성/수정 | 프로필 수정 |
| **요청 횟수** | 1회 (multipart/form-data) | 2회 (POST /images → POST /posts) | 1회 (removeImage: true) |
| **트랜잭션** | 원자적 (이미지 포함) | 독립적 (이미지 선행) | 원자적 (TTL 복원) |
| **UX 장점** | 간편함, 한 번에 완료 | 미리보기, 임시 저장 지원 | 명시적 제거 의도 |
| **핵심 메서드** | AuthService.signup() | PostService.createPost() | UserService.updateProfile() |

**구현 위치:**
- Pattern 1: AuthService.signup() (Line 61-105)
- Pattern 2: PostService.createPost() (Line 49-105)
- Pattern 3: UserService.updateProfile() (Line 88-170)

**TTL 패턴 (공통 핵심):**
- **업로드 시**: ImageService가 `expires_at = NOW() + 1시간` 설정
- **사용 시**: `image.clearExpiresAt()` 호출 → `expires_at = NULL` (영구 보존)
- **제거 시**: `image.setExpiresAt(NOW() + 1시간)` 호출 → TTL 복원 (고아 처리)
- **미사용 시**: Phase 4 배치가 expires_at < NOW() 조건으로 S3 + DB 삭제
- **인덱스**: `idx_images_expires` 활용으로 빠른 조회

**설계 결정사항:**
- **검증 로직**: AuthService.signup()에서 이메일/닉네임/비밀번호 검증 모두 구현됨 (생략 아님)
- **User 생성**: Builder 직접 사용 대신 `request.toEntity()` + `updateProfileImage()` 패턴
- **TTL 복원 전략**: 
  - 패턴 1 (새 이미지 교체): 기존 이미지 TTL 1시간 복원 → 고아 처리
  - 패턴 3 (이미지 제거): 기존 이미지 TTL 1시간 복원 → 관계 해제
  - Phase 4 배치가 expires_at < NOW() 조건으로 S3 + DB 삭제
- **트랜잭션 안전성**: 패턴 1/3은 완전 원자적, 패턴 2는 이미지만 선행 업로드 (S3 파일 고아 가능)

**참조**: 
- AuthService.signup() - 패턴 1 전체 구현
- PostService.createPost() - 패턴 2 전체 구현
- UserService.updateProfile() - 패턴 3 전체 구현
- ImageService.uploadImage() - 공통 검증 로직
- **@docs/be/API.md Section 2.1, 2.3, 3.3, 4.1**
- **@docs/be/DDL.md** (images 테이블)

---

## 8. 예외 처리

### 8.1 예외 처리 구조

**단일 통합 예외 아키텍처:**
- **ErrorCode enum**: 에러 정보 중앙 관리 (28개 에러 코드) - HTTP 상태, 에러 코드, 메시지 포함
- **BusinessException**: 단일 통합 예외 클래스 (ErrorCode 래핑, 4가지 생성자 지원)
- **GlobalExceptionHandler**: 중앙 예외 처리 (@RestControllerAdvice, 7개 핸들러)

**ErrorCode 형식:** `{DOMAIN}-{NUMBER}` (예: USER-001, POST-001, AUTH-001)

**전체 에러 코드 목록**: **@docs/be/API.md Section 7** (도메인별 28개 에러 코드)

---

### 8.2 예외 핸들러 목록

| 핸들러 | 예외 타입 | HTTP 상태 | 설명 |
|--------|-----------|-----------|------|
| handleBusinessException | BusinessException | ErrorCode 기반 | 비즈니스 로직 에러 (통합) |
| handleMaxUploadSizeExceeded | MaxUploadSizeExceededException | 413 | 파일 크기 초과 (Phase 3.5) |
| handleValidationException | MethodArgumentNotValidException | 400 | DTO 검증 실패 (@Valid) |
| handleIllegalArgumentException | IllegalArgumentException | 400 | 잘못된 요청 파라미터 |
| handleIllegalStateException | IllegalStateException | 400 | 비즈니스 로직 오류 |
| handleGeneralException | Exception | 500 | 예상하지 못한 서버 오류 |
| handleNullPointerException | NullPointerException | 500 | Null 참조 오류 |

---

### 8.3 핵심 패턴

**통합 예외 처리 (BusinessException):**
```java
@ExceptionHandler(BusinessException.class)
public ResponseEntity<ApiResponse<ErrorDetails>> handleBusinessException(BusinessException ex) {
    ErrorCode errorCode = ex.getErrorCode();
    ErrorDetails errorDetails = ErrorDetails.of(ex.getMessage());
    ApiResponse<ErrorDetails> response = ApiResponse.error(errorCode.getCode(), errorDetails);
    
    return ResponseEntity.status(errorCode.getHttpStatus()).body(response);
}
```

**핵심 장점:**
- ErrorCode enum이 HTTP 상태, 에러 코드, 메시지 모두 관리
- Service Layer에서 `throw new BusinessException(ErrorCode.XXX)` 한 줄로 통일
- GlobalExceptionHandler가 자동 매핑 (ErrorCode → HTTP 상태 + 응답)

**사용 예시:**
```java
// Service Layer
if (!comment.getUser().getUserId().equals(userId)) {
    throw new BusinessException(ErrorCode.UNAUTHORIZED_ACCESS,
            "Not authorized to update this comment");
}

// 자동 변환: UNAUTHORIZED_ACCESS → HTTP 403 + "COMMON-XXX" + 메시지
```

**참조:** GlobalExceptionHandler.java (전체 핸들러 7개), ErrorCode.java (28개 에러 정의)

---

## 9. 데이터 변환 (Entity ↔ DTO)

**패턴:**
```java
// Entity → DTO
public static PostResponse from(Post post) {
    return PostResponse.builder()
        .postId(post.getPostId())
        .title(post.getTitle())
        .author(UserSummary.from(post.getUser()))
        .stats(PostStatsResponse.from(post.getStats()))
        .build();
}

// DTO → Entity
public Post toEntity(User user) {
    return Post.builder()
        .title(this.title)
        .content(this.content)
        .status(PostStatus.ACTIVE)
        .user(user)
        .build();
}
```

**DTO 검증:** `@NotBlank`, `@Size`, `@Valid` 활용

---

## 10. 설정 파일

**핵심 설정 항목:**

| 항목 | 설정값 | 설명 |
|------|--------|------|
| **HikariCP** | Spring Boot default | DB 커넥션 풀 (default: 10) |
| **Multipart** | max-file-size: 5MB, max-request-size: 10MB | 이미지 업로드 제한 |
| **JPA** | ddl-auto: validate, open-in-view: false, default_batch_fetch_size: 100 | 운영 모드, OSIV 비활성화, N+1 최적화 |
| **JWT** | access: 15분 (900000ms), refresh: 7일 (604800000ms) | 토큰 유효기간 |
| **S3** | bucket/region 환경 변수 주입 | DefaultCredentialsProvider 체인 |
| **Rate Limit** | 코드 기반 (@RateLimit 어노테이션) | 엔드포인트별 개별 설정 |
| **Logging** | root: INFO, com.ktb.community: DEBUG | 개발 환경 로깅 레벨 |
| **Server** | port: 8080 | 서버 포트 |

**환경 변수 (필수):**
```bash
# Phase 1-2 (Database & JWT)
DB_URL=jdbc:mysql://localhost:3306/community
DB_USERNAME=root
DB_PASSWORD=<MySQL 비밀번호>
JWT_SECRET=<256bit 이상 시크릿>

# Phase 3.5+ (S3)
AWS_ACCESS_KEY_ID=<AWS Access Key>
AWS_SECRET_ACCESS_KEY=<AWS Secret Key>
AWS_REGION=ap-northeast-2
AWS_S3_BUCKET=<버킷 이름>
```

**참조:** `src/main/resources/application.yaml` (전체 설정)

---

## 11. 테스트 전략

**커버리지 목표:** Service 80%+, Repository 60%+, 전체 60%+

**패턴:**
```java
// Service 테스트
@ExtendWith(MockitoExtension.class)
class PostServiceTest {
    @Mock private PostRepository postRepository;
    @InjectMocks private PostService postService;
    
    @Test
    void createPost_Success() {
        // Given, When, Then + verify()
    }
}

// Repository 테스트
@DataJpaTest
class PostRepositoryTest {
    @Autowired private PostRepository postRepository;
    // 실제 DB 쿼리 테스트
}
```

---

## 12. 성능 최적화

### 12.1 데이터베이스 최적화

**N+1 문제 해결:**
- JOIN FETCH 사용 (Post + User + PostStats 동시 로드)
- Repository 커스텀 쿼리: `findByStatusWithUserAndStats()`
- 인덱스 활용: DDL.md 정의 준수, EXPLAIN 분석

**Batch Fetch Size 설정:**
- `default_batch_fetch_size: 100` (application.yaml)
- to-many lazy loading 시 IN 쿼리로 일괄 로드
- **효과**: Post 목록 조회 11개 쿼리 → 2개 쿼리 (82% 감소)
- 코드 변경 없이 설정만으로 적용 가능

**User Soft Delete 필터링:**
- Repository: `findByUserIdAndUserStatus(userId, UserStatus.ACTIVE)`
- INACTIVE/DELETED 사용자의 활동 차단 (게시글/댓글/좋아요)
- 보안 취약점 제거: 탈퇴 사용자 차단
- **적용**: UserService 4곳, PostService/CommentService/LikeService 각 1곳

### 12.2 캐싱 전략 (추후)

**Redis 도입 시:**
- 토큰 관리: Refresh Token 저장
- 세션 관리: 사용자 세션 캐싱
- 데이터 캐싱: 자주 조회되는 게시글 목록
- TTL 설정: 데이터 특성별 만료 시간

### 12.3 동시성 제어

**문제:** PostStats (좋아요/댓글/조회수) 동시 업데이트 시 Race Condition

**해결:** DB 레벨 원자적 UPDATE

```sql
UPDATE post_stats
SET like_count = like_count + 1,
    last_updated = NOW()
WHERE post_id = ?;
```

**Repository 구현:**
```java
@Modifying(clearAutomatically = false)
@Query("UPDATE PostStats ps SET ps.likeCount = ps.likeCount + 1, " +
       "ps.lastUpdated = CURRENT_TIMESTAMP WHERE ps.postId = :postId")
int incrementLikeCount(@Param("postId") Long postId);

@Modifying(clearAutomatically = false)
@Query("UPDATE PostStats ps SET ps.likeCount = ps.likeCount - 1, " +
       "ps.lastUpdated = CURRENT_TIMESTAMP " +
       "WHERE ps.postId = :postId AND ps.likeCount > 0")
int decrementLikeCount(@Param("postId") Long postId);
```

**적용 대상:**
- `likeCount`: 좋아요 증감
- `commentCount`: 댓글 수 증감
- `viewCount`: 조회수 증가 (가장 빈번)

**대안 검토:**
- ❌ 낙관적 락 (@Version): 재시도 폭증
- ❌ 비관적 락 (FOR UPDATE): 과도한 오버헤드
- ✅ 원자적 UPDATE: 성능과 일관성 최적

**Phase 5 최적화 (clearAutomatically = false):**
- **문제**: PostStats 조회 후 JPQL UPDATE 실행 시 영속성 컨텍스트의 stale 데이터 유지
- **기존 방식**: clearAutomatically = true → 1차 캐시 자동 초기화, 이후 조회 시 DB 재조회 필요
- **최적화**: clearAutomatically = false → 1차 캐시 유지, Optimistic Update 패턴으로 클라이언트가 보정
- **결과**: DB 통신 17% 감소, detached entity 이슈 해결, 동시성 보장 유지
- **Trade-off**: 서버 응답값은 stale (증가 전 값), 클라이언트가 UI에서 +1/-1 처리
- **참조**: PLAN.md Phase 5 (Line 295-306), API.md Section 3.2/6.1/6.2

---

## 13. 배포 및 운영

**환경 변수:** `@docs/be/LLD.md Section 10` 참조 (6개 필수 변수)

**배치 작업:**
- 고아 이미지 정리: 매일 새벽 3시, @Scheduled (ImageCleanupBatchService)
- TTL 만료 이미지 (expires_at < NOW) 자동 삭제 (S3 + DB)

**로그 레벨:**
- 운영: INFO, 개발: DEBUG
- 주요 포인트: API 요청/응답, 인증 실패, 비즈니스 에러

---

## 14. 로깅 정책

### 14.1 로그 레벨 기준

| 레벨 | 용도 | 예시 |
|------|------|------|
| debug | 상세 디버깅 (개발 환경만) | 메서드 진입/종료, 상태 변화 |
| info | 비즈니스 이벤트 (비개인정보) | 배치 시작/종료, 통계 |
| warn | 의도적 실패 (복구 가능) | 404, 403, 409, RateLimit |
| error | 예상치 못한 실패 | 500, 예외 스택 |

### 14.2 민감정보 처리 규칙

**금지:**
- ❌ Email, UserId (개인 식별자)
- ❌ 비밀번호, 토큰 원본

**허용:**
- ✅ PostId, CommentId, ImageId (콘텐츠/리소스 식별자)
- ✅ HTTP 메서드, 경로

**대안:**
- 요청 추적: MDC + requestId (Phase 6+)
- 감사 로그: 별도 AuditLog 테이블

### 14.3 현재 적용 현황

**Service Layer:**
- 성공 플로우: debug (운영 환경에서 숨김)
- 비즈니스 이벤트: info (배치, 통계만)

**GlobalExceptionHandler:**
- 의도적 실패: warn (4xx, RateLimit)
- 예상치 못한 실패: error (5xx, 예외)

**운영 환경 설정**: `application-prod.yaml`에서 INFO 레벨 사용

---

## 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|-----------|
| 2025-09-30 | 1.0 | 초기 LLD 작성 |
| 2025-10-04 | 1.1 | Claude Code 최적화 (참조 기반, 섹션 재구조화) |
| 2025-10-04 | 1.2 | 핵심 섹션 완전 복원 (6.4, 6.5, 12.3) |
| 2025-10-04 | 1.3 | Section 7.4 댓글 작성 흐름 추가 (참조 무결성 복원) |
| 2025-10-10 | 1.4 | HTML 이스케이프 코드 수정 (Section 6.5) |
| 2025-10-15 | 1.5 | Section 14 로깅 정책 추가, Service Layer 로그 레벨 조정 |
| 2025-10-15 | 1.6 | Section 12.1 User Soft Delete 필터링 및 Batch Fetch Size 추가 |
| 2025-10-21 | 1.7 | Section 6.3 SecurityConfig CSRF 설정 업데이트 (API 엔드포인트 제외 반영) |
| 2025-10-22 | 1.8 | 중복 제거 및 참조 최적화 (Section 5 API 엔드포인트, Section 8.1 에러 코드 - API.md 참조) |
| 2025-10-22 | 1.9 | Section 7.2, 12.3 clearAutomatically 파라미터 동기화 (true → false, Phase 5 최적화 반영) |
| 2025-11-03 | 2.0 | Section 7.5 Pattern 3 추가 (이미지 제거, UserService.updateProfile), TTL 복원 전략 문서화 |
| 2025-11-12 | 2.1 | 문서 최적화 - 코드 블록 제거 및 참조 기반 재구조화 (Section 3, 7.1, 7.3, 7.4, 12.1 압축, Section 7.2 삭제, 2,300 tokens 절감) |
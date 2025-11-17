FROM eclipse-temurin:21-jdk-alpine

WORKDIR /app

# Gradle Wrapper와 의존성 파일 복사
COPY gradlew .
COPY gradle gradle
COPY build.gradle .
COPY settings.gradle .

# Gradle Wrapper 실행 권한 부여
RUN chmod +x gradlew

# 의존성 다운로드 (캐시 레이어)
RUN ./gradlew dependencies --no-daemon

# 소스 코드 복사
COPY src src

# JAR 파일 빌드
RUN ./gradlew bootJar --no-daemon

# JAR 파일 이름 통일
RUN mv build/libs/*.jar app.jar

# 컨테이너 실행 시 사용할 포트
EXPOSE 8080

# 애플리케이션 실행
ENTRYPOINT ["java", "-jar", "app.jar"]

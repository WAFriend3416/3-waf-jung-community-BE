package com.ktb.community.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
public class S3Config {

    @Value("${aws.s3.region}")
    private String region;

    /**
     * S3Client Bean 생성
     *
     * Credentials Provider: DefaultCredentialsProvider (IAM Role)
     * - 로컬 개발: ~/.aws/credentials 프로필 자동 인식
     * - EC2 배포: IAM Role 자동 인식
     * - 자동 갱신: AWS SDK에서 자동 처리
     * - AWS 공식 권장 방식
     *
     * 인증 순서:
     * 1. 환경변수 (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
     * 2. 시스템 프로퍼티
     * 3. ~/.aws/credentials 파일
     * 4. EC2 IAM Instance Profile
     * 5. ECS Task Role
     */
    @Bean
    public S3Client s3Client() {
        return S3Client.builder()
                .region(Region.of(region))
                .credentialsProvider(software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider.create())
                .build();
    }

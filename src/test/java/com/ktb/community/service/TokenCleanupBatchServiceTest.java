package com.ktb.community.service;

import com.ktb.community.repository.UserTokenRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * TokenCleanupBatchService 테스트
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("만료 토큰 배치 테스트")
class TokenCleanupBatchServiceTest {

    @Mock
    private UserTokenRepository userTokenRepository;

    @InjectMocks
    private TokenCleanupBatchService batchService;

    @BeforeEach
    void setUp() {
        // 테스트 초기화 (필요 시)
    }

    @Test
    @DisplayName("만료 토큰 배치 - 만료된 토큰 삭제 성공")
    void cleanupExpiredTokens_Success() {
        // Given
        int expectedDeleteCount = 5;
        when(userTokenRepository.deleteExpiredTokens(any(LocalDateTime.class)))
                .thenReturn(expectedDeleteCount);

        // When
        batchService.cleanupExpiredTokens();

        // Then
        verify(userTokenRepository).deleteExpiredTokens(any(LocalDateTime.class));
    }

    @Test
    @DisplayName("만료 토큰 배치 - 삭제할 토큰 없음")
    void cleanupExpiredTokens_NoExpiredTokens() {
        // Given
        when(userTokenRepository.deleteExpiredTokens(any(LocalDateTime.class)))
                .thenReturn(0);

        // When
        batchService.cleanupExpiredTokens();

        // Then
        verify(userTokenRepository).deleteExpiredTokens(any(LocalDateTime.class));
    }

    @Test
    @DisplayName("만료 토큰 배치 - 다수의 토큰 일괄 삭제")
    void cleanupExpiredTokens_MultipleDeletions() {
        // Given
        int expectedDeleteCount = 42;
        when(userTokenRepository.deleteExpiredTokens(any(LocalDateTime.class)))
                .thenReturn(expectedDeleteCount);

        // When
        batchService.cleanupExpiredTokens();

        // Then
        verify(userTokenRepository).deleteExpiredTokens(any(LocalDateTime.class));
    }

    @Test
    @DisplayName("만료 토큰 배치 - 예외 발생 시 다음 스케줄 실행 보장")
    void cleanupExpiredTokens_ExceptionHandling() {
        // Given
        when(userTokenRepository.deleteExpiredTokens(any(LocalDateTime.class)))
                .thenThrow(new RuntimeException("DB connection failed"));

        // When
        batchService.cleanupExpiredTokens();  // 예외를 던지지 않아야 함

        // Then
        verify(userTokenRepository).deleteExpiredTokens(any(LocalDateTime.class));
        // 예외가 발생해도 메서드가 정상 종료되어야 함 (다음 스케줄 실행 보장)
    }
}

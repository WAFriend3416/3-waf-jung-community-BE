package com.ktb.community.repository;

import com.ktb.community.entity.Image;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 이미지 Repository
 * FR-IMAGE-001, FR-IMAGE-003, FR-IMAGE-002 (고아 이미지)
 */
@Repository
public interface ImageRepository extends JpaRepository<Image, Long> {

    /**
     * 이미지 URL 존재 여부 확인
     * Lambda에서 업로드한 이미지 URL의 중복 검증용
     */
    boolean existsByImageUrl(String imageUrl);

    /**
     * 만료된 이미지 조회 (고아 이미지 배치용)
     * - expires_at < 지정 시간
     * - idx_images_expires 인덱스 활용
     */
    List<Image> findByExpiresAtBefore(LocalDateTime dateTime);

    /**
     * 영구 고아 이미지 조회 (참조 없는 이미지)
     * - expires_at IS NULL (영구 보존 상태)
     * - created_at < threshold (안전 마진, 예: 7일 이전)
     * - User 테이블 참조 없음
     * - PostImage 테이블 참조 없음
     */
    @Query("SELECT i FROM Image i " +
           "WHERE i.expiresAt IS NULL " +
           "AND i.createdAt < :threshold " +
           "AND i.imageId NOT IN (" +
           "  SELECT u.profileImage.imageId FROM User u WHERE u.profileImage IS NOT NULL" +
           ") " +
           "AND i.imageId NOT IN (" +
           "  SELECT pi.image.imageId FROM PostImage pi" +
           ")")
    List<Image> findPermanentOrphans(@Param("threshold") LocalDateTime threshold);
}

package com.ktb.community;

import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class CommunityApplicationTests {

	@Disabled("CI 환경변수 없이 실행 불가")
	@Test
	void contextLoads() {
	}

}

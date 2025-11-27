package com.ktb.community;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class CommunityApplication {

	//CI/CD 테스트용 주석
	public static void main(String[] args) {
		SpringApplication.run(CommunityApplication.class, args);
	}

}

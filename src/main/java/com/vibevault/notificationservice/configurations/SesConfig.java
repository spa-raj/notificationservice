package com.vibevault.notificationservice.configurations;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ses.SesClient;

@Getter
@Setter
@Configuration
@ConfigurationProperties(prefix = "notification.ses")
@ConditionalOnProperty(name = "notification.ses.enabled", havingValue = "true")
public class SesConfig {

    private boolean enabled;
    private String fromEmail;
    private String region;

    @Bean
    public SesClient sesClient() {
        return SesClient.builder()
                .region(Region.of(region))
                .build();
    }
}

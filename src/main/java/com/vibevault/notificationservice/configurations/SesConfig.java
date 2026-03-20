package com.vibevault.notificationservice.configurations;

import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.validation.annotation.Validated;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ses.SesClient;

@Getter
@Setter
@Validated
@Configuration
@ConfigurationProperties(prefix = "notification.ses")
@ConditionalOnProperty(name = "notification.ses.enabled", havingValue = "true")
public class SesConfig {

    private boolean enabled;

    @NotBlank(message = "notification.ses.from-email must be configured when SES is enabled")
    private String fromEmail;

    @NotBlank(message = "notification.ses.region must be configured when SES is enabled")
    private String region;

    private String toEmail;

    @Bean
    public SesClient sesClient() {
        return SesClient.builder()
                .region(Region.of(region))
                .build();
    }
}

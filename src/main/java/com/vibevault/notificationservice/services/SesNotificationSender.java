package com.vibevault.notificationservice.services;

import com.vibevault.notificationservice.configurations.SesConfig;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.ses.SesClient;
import software.amazon.awssdk.services.ses.model.*;

@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "notification.ses.enabled", havingValue = "true")
public class SesNotificationSender implements NotificationSender {

    private final SesClient sesClient;
    private final SesConfig sesConfig;

    @Override
    public void send(String to, String subject, String body) {
        try {
            SendEmailRequest request = SendEmailRequest.builder()
                    .source(sesConfig.getFromEmail())
                    .destination(Destination.builder()
                            .toAddresses(to)
                            .build())
                    .message(Message.builder()
                            .subject(Content.builder().data(subject).charset("UTF-8").build())
                            .body(Body.builder()
                                    .text(Content.builder().data(body).charset("UTF-8").build())
                                    .build())
                            .build())
                    .build();

            sesClient.sendEmail(request);
            log.info("SES email sent to {} — subject: {}", to, subject);
        } catch (SesException e) {
            log.error("Failed to send SES email to {}: {}", to, e.awsErrorDetails().errorMessage());
        }
    }
}

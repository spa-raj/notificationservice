package com.vibevault.notificationservice.services;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class ConsoleNotificationSender implements NotificationSender {

    @Override
    public void send(String to, String subject, String body) {
        log.info("""
                ========== NOTIFICATION ==========
                To:      {}
                Subject: {}
                Body:    {}
                ===================================""", to, subject, body);
    }
}

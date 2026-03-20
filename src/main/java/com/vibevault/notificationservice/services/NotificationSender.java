package com.vibevault.notificationservice.services;

public interface NotificationSender {
    void send(String to, String subject, String body);
}

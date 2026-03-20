package com.vibevault.notificationservice.services;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class NotificationDispatcher {

    private final List<NotificationSender> senders;

    public void notifyOrderCreated(String userId, UUID orderId, BigDecimal amount, String currency) {
        String subject = "Order Placed - " + orderId;
        String body = String.format("Your order %s has been placed for %s %s. We'll notify you once payment is confirmed.",
                orderId, currency, amount);
        dispatch(userId, subject, body);
    }

    public void notifyOrderConfirmed(String userId, UUID orderId) {
        String subject = "Order Confirmed - " + orderId;
        String body = String.format("Your order %s has been confirmed and is being processed.", orderId);
        dispatch(userId, subject, body);
    }

    public void notifyOrderCancelled(String userId, UUID orderId) {
        String subject = "Order Cancelled - " + orderId;
        String body = String.format("Your order %s has been cancelled.", orderId);
        dispatch(userId, subject, body);
    }

    public void notifyPaymentConfirmed(String userId, UUID orderId, BigDecimal amount) {
        String subject = "Payment Successful - Order " + orderId;
        String body = String.format("Payment of %s for order %s has been confirmed.", amount, orderId);
        dispatch(userId, subject, body);
    }

    public void notifyPaymentFailed(String userId, UUID orderId, String reason) {
        String subject = "Payment Failed - Order " + orderId;
        String body = String.format("Payment for order %s failed. Reason: %s", orderId, reason != null ? reason : "Unknown");
        dispatch(userId, subject, body);
    }

    private void dispatch(String to, String subject, String body) {
        for (NotificationSender sender : senders) {
            try {
                sender.send(to, subject, body);
            } catch (Exception e) {
                log.error("Failed to send notification via {}", sender.getClass().getSimpleName(), e);
            }
        }
    }
}

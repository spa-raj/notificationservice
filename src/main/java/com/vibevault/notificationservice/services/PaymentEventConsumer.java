package com.vibevault.notificationservice.services;

import com.vibevault.notificationservice.constants.KafkaTopics;
import com.vibevault.notificationservice.events.PaymentEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class PaymentEventConsumer {

    private final NotificationDispatcher notificationDispatcher;

    @KafkaListener(
            topics = KafkaTopics.PAYMENT_EVENTS,
            groupId = "notificationservice",
            containerFactory = "paymentEventListenerContainerFactory"
    )
    public void handlePaymentEvent(PaymentEvent event) {
        if (event.getEventType() == null) {
            log.warn("Payment event with null eventType — skipping");
            return;
        }
        log.info("Received payment event: {} for order {}", event.getEventType(), event.getOrderId());

        switch (event.getEventType()) {
            case "PAYMENT_CONFIRMED" -> notificationDispatcher.notifyPaymentConfirmed(
                    event.getUserId(), event.getOrderId(), event.getAmount());
            case "PAYMENT_FAILED" -> notificationDispatcher.notifyPaymentFailed(
                    event.getUserId(), event.getOrderId(), event.getFailureReason());
            default -> log.debug("Ignoring payment event type: {}", event.getEventType());
        }
    }
}

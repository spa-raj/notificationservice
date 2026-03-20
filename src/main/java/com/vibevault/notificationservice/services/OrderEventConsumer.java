package com.vibevault.notificationservice.services;

import com.vibevault.notificationservice.constants.KafkaTopics;
import com.vibevault.notificationservice.events.OrderEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class OrderEventConsumer {

    private final NotificationDispatcher notificationDispatcher;

    @KafkaListener(
            topics = KafkaTopics.ORDER_EVENTS,
            groupId = "notificationservice",
            containerFactory = "orderEventListenerContainerFactory"
    )
    public void handleOrderEvent(OrderEvent event) {
        if (event.getEventType() == null) {
            log.warn("Order event with null eventType — skipping");
            return;
        }
        log.info("Received order event: {} for order {}", event.getEventType(), event.getOrderId());

        switch (event.getEventType()) {
            case "ORDER_CREATED" -> notificationDispatcher.notifyOrderCreated(
                    event.getUserId(), event.getOrderId(), event.getTotalAmount(), event.getCurrency());
            case "ORDER_CONFIRMED" -> notificationDispatcher.notifyOrderConfirmed(
                    event.getUserId(), event.getOrderId());
            case "ORDER_CANCELLED" -> notificationDispatcher.notifyOrderCancelled(
                    event.getUserId(), event.getOrderId());
            default -> log.debug("Ignoring order event type: {}", event.getEventType());
        }
    }
}

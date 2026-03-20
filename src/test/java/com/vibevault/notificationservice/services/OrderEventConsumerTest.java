package com.vibevault.notificationservice.services;

import com.vibevault.notificationservice.events.OrderEvent;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderEventConsumerTest {

    @Mock
    private NotificationDispatcher notificationDispatcher;

    @InjectMocks
    private OrderEventConsumer orderEventConsumer;

    @Test
    void handleOrderEvent_orderCreated() {
        OrderEvent event = OrderEvent.builder()
                .eventId("e1")
                .eventType("ORDER_CREATED")
                .orderId(UUID.randomUUID())
                .userId("user@test.com")
                .totalAmount(new BigDecimal("999.98"))
                .currency("INR")
                .timestamp(LocalDateTime.now())
                .build();

        orderEventConsumer.handleOrderEvent(event);

        verify(notificationDispatcher).notifyOrderCreated("user@test.com", event.getOrderId(), event.getTotalAmount(), "INR");
    }

    @Test
    void handleOrderEvent_orderConfirmed() {
        OrderEvent event = OrderEvent.builder()
                .eventId("e2")
                .eventType("ORDER_CONFIRMED")
                .orderId(UUID.randomUUID())
                .userId("user@test.com")
                .timestamp(LocalDateTime.now())
                .build();

        orderEventConsumer.handleOrderEvent(event);

        verify(notificationDispatcher).notifyOrderConfirmed("user@test.com", event.getOrderId());
    }

    @Test
    void handleOrderEvent_orderCancelled() {
        OrderEvent event = OrderEvent.builder()
                .eventId("e3")
                .eventType("ORDER_CANCELLED")
                .orderId(UUID.randomUUID())
                .userId("user@test.com")
                .timestamp(LocalDateTime.now())
                .build();

        orderEventConsumer.handleOrderEvent(event);

        verify(notificationDispatcher).notifyOrderCancelled("user@test.com", event.getOrderId());
    }

    @Test
    void handleOrderEvent_unknownType_ignored() {
        OrderEvent event = OrderEvent.builder()
                .eventId("e4")
                .eventType("UNKNOWN")
                .orderId(UUID.randomUUID())
                .userId("user@test.com")
                .timestamp(LocalDateTime.now())
                .build();

        orderEventConsumer.handleOrderEvent(event);

        verifyNoInteractions(notificationDispatcher);
    }

    @Test
    void handleOrderEvent_nullEventType_skipped() {
        OrderEvent event = OrderEvent.builder()
                .eventId("e5")
                .eventType(null)
                .orderId(UUID.randomUUID())
                .userId("user@test.com")
                .timestamp(LocalDateTime.now())
                .build();

        orderEventConsumer.handleOrderEvent(event);

        verifyNoInteractions(notificationDispatcher);
    }
}

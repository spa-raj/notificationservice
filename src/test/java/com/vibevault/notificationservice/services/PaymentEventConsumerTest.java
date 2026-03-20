package com.vibevault.notificationservice.services;

import com.vibevault.notificationservice.events.PaymentEvent;
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
class PaymentEventConsumerTest {

    @Mock
    private NotificationDispatcher notificationDispatcher;

    @InjectMocks
    private PaymentEventConsumer paymentEventConsumer;

    @Test
    void handlePaymentEvent_paymentConfirmed() {
        PaymentEvent event = PaymentEvent.builder()
                .eventId("p1")
                .eventType("PAYMENT_CONFIRMED")
                .orderId(UUID.randomUUID())
                .userId("user@test.com")
                .amount(new BigDecimal("999.98"))
                .timestamp(LocalDateTime.now())
                .build();

        paymentEventConsumer.handlePaymentEvent(event);

        verify(notificationDispatcher).notifyPaymentConfirmed("user@test.com", event.getOrderId(), event.getAmount());
    }

    @Test
    void handlePaymentEvent_paymentFailed() {
        PaymentEvent event = PaymentEvent.builder()
                .eventId("p2")
                .eventType("PAYMENT_FAILED")
                .orderId(UUID.randomUUID())
                .userId("user@test.com")
                .amount(new BigDecimal("999.98"))
                .failureReason("expired")
                .timestamp(LocalDateTime.now())
                .build();

        paymentEventConsumer.handlePaymentEvent(event);

        verify(notificationDispatcher).notifyPaymentFailed("user@test.com", event.getOrderId(), "expired");
    }

    @Test
    void handlePaymentEvent_unknownType_ignored() {
        PaymentEvent event = PaymentEvent.builder()
                .eventId("p3")
                .eventType("UNKNOWN")
                .orderId(UUID.randomUUID())
                .userId("user@test.com")
                .timestamp(LocalDateTime.now())
                .build();

        paymentEventConsumer.handlePaymentEvent(event);

        verifyNoInteractions(notificationDispatcher);
    }

    @Test
    void handlePaymentEvent_nullEventType_skipped() {
        PaymentEvent event = PaymentEvent.builder()
                .eventId("p4")
                .eventType(null)
                .orderId(UUID.randomUUID())
                .userId("user@test.com")
                .timestamp(LocalDateTime.now())
                .build();

        paymentEventConsumer.handlePaymentEvent(event);

        verifyNoInteractions(notificationDispatcher);
    }
}

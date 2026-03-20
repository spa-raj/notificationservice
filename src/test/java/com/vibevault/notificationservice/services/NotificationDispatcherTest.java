package com.vibevault.notificationservice.services;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class NotificationDispatcherTest {

    @Mock
    private NotificationSender sender1;

    @Mock
    private NotificationSender sender2;

    @InjectMocks
    private NotificationDispatcher dispatcher;

    NotificationDispatcherTest() {
        // InjectMocks needs List<NotificationSender> — set up manually
    }

    private NotificationDispatcher createDispatcher() {
        return new NotificationDispatcher(List.of(sender1, sender2));
    }

    @Test
    void notifyOrderCreated_dispatchesToAllSenders() {
        NotificationDispatcher d = createDispatcher();
        UUID orderId = UUID.randomUUID();

        d.notifyOrderCreated("user@test.com", orderId, new BigDecimal("999.98"), "INR");

        verify(sender1).send(eq("user@test.com"), contains("Order Placed"), contains(orderId.toString()));
        verify(sender2).send(eq("user@test.com"), contains("Order Placed"), contains(orderId.toString()));
    }

    @Test
    void notifyOrderConfirmed_dispatchesToAllSenders() {
        NotificationDispatcher d = createDispatcher();
        UUID orderId = UUID.randomUUID();

        d.notifyOrderConfirmed("user@test.com", orderId);

        verify(sender1).send(eq("user@test.com"), contains("Order Confirmed"), contains(orderId.toString()));
        verify(sender2).send(eq("user@test.com"), contains("Order Confirmed"), contains(orderId.toString()));
    }

    @Test
    void notifyOrderCancelled_dispatchesToAllSenders() {
        NotificationDispatcher d = createDispatcher();
        UUID orderId = UUID.randomUUID();

        d.notifyOrderCancelled("user@test.com", orderId);

        verify(sender1).send(eq("user@test.com"), contains("Order Cancelled"), contains(orderId.toString()));
        verify(sender2).send(eq("user@test.com"), contains("Order Cancelled"), contains(orderId.toString()));
    }

    @Test
    void notifyPaymentConfirmed_dispatchesToAllSenders() {
        NotificationDispatcher d = createDispatcher();
        UUID orderId = UUID.randomUUID();

        d.notifyPaymentConfirmed("user@test.com", orderId, new BigDecimal("999.98"));

        verify(sender1).send(eq("user@test.com"), contains("Payment Successful"), contains(orderId.toString()));
        verify(sender2).send(eq("user@test.com"), contains("Payment Successful"), contains(orderId.toString()));
    }

    @Test
    void notifyPaymentFailed_dispatchesToAllSenders() {
        NotificationDispatcher d = createDispatcher();
        UUID orderId = UUID.randomUUID();

        d.notifyPaymentFailed("user@test.com", orderId, "expired");

        verify(sender1).send(eq("user@test.com"), contains("Payment Failed"), contains("expired"));
        verify(sender2).send(eq("user@test.com"), contains("Payment Failed"), contains("expired"));
    }

    @Test
    void dispatch_continuesIfOneSenderFails() {
        NotificationDispatcher d = createDispatcher();
        UUID orderId = UUID.randomUUID();

        doThrow(new RuntimeException("SES down")).when(sender1).send(anyString(), anyString(), anyString());

        d.notifyOrderCreated("user@test.com", orderId, new BigDecimal("100"), "INR");

        verify(sender1).send(anyString(), anyString(), anyString());
        verify(sender2).send(eq("user@test.com"), contains("Order Placed"), anyString());
    }
}

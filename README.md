# VibeVault Notification Service

Event-driven notification microservice for the VibeVault e-commerce platform. Consumes Kafka events and delivers notifications via console logging and AWS SES email.

## Tech Stack

- **Runtime:** Java 21, Spring Boot 4.0.3
- **Messaging:** Apache Kafka (consumer, KRaft mode)
- **Email:** AWS SES SDK v2 (optional, conditional via config)
- **Infrastructure:** AWS EKS, Helm, GitHub Actions CI/CD

## Kafka Events Consumed

### From `order-events` topic

| Event | Notification |
|-------|-------------|
| `ORDER_CREATED` | "Order Placed — Your order has been placed for {currency} {amount}" |
| `ORDER_CONFIRMED` | "Order Confirmed — Your order is being processed" |
| `ORDER_CANCELLED` | "Order Cancelled" |

### From `payment-events` topic

| Event | Notification |
|-------|-------------|
| `PAYMENT_CONFIRMED` | "Payment Successful — Payment of {amount} confirmed" |
| `PAYMENT_FAILED` | "Payment Failed — Reason: {reason}" |

## Notification Senders

### Console (always active)
Logs notifications to stdout with a formatted banner. Always enabled — no configuration needed.

### AWS SES Email (conditional)
Real email delivery via AWS SES SDK v2. Enabled via `notification.ses.enabled=true`.

- **Sandbox mode:** Both sender and recipient must be verified in SES console
- **`SES_TO_EMAIL` override:** In sandbox mode, routes all emails to a verified address regardless of userId
- **Fail-fast:** `@Validated` + `@NotBlank` on `fromEmail` and `region` when SES is enabled

## Architecture

```
order-events topic ──→ OrderEventConsumer ──→ NotificationDispatcher ──→ ConsoleNotificationSender
                                                                    └──→ SesNotificationSender (optional)
payment-events topic ──→ PaymentEventConsumer ──→ NotificationDispatcher ──→ (same senders)
```

- `NotificationDispatcher` injects `List<NotificationSender>` — dispatches to all active senders
- If one sender fails, others still execute (fault isolation)

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8085` | Server port |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | Kafka broker address |
| `SES_ENABLED` | `false` | Enable AWS SES email sender |
| `SES_FROM_EMAIL` | — | Verified sender email address |
| `SES_REGION` | `ap-south-1` | AWS SES region |
| `SES_TO_EMAIL` | — | Override recipient (for SES sandbox testing) |

## Local Development

### Prerequisites
- Java 21
- Docker & Docker Compose
- Other services running (cartservice with Kafka on vibevault-network)

### Console only (default)
```bash
docker network create vibevault-network 2>/dev/null || true
docker compose up --build
```

### With SES email
```bash
eval "$(aws configure export-credentials --format env)"
SES_ENABLED=true \
SES_FROM_EMAIL=your-verified-email@gmail.com \
SES_TO_EMAIL=your-verified-email@gmail.com \
docker compose up --build
```

### Test
```bash
./scripts/test-notification-e2e.sh
```

**E2E test** verifying full saga across all 6 services: cart checkout → order → Razorpay payment → webhook → notifications (console + email).

## Unit Tests

**16 tests** (6 dispatcher + 5 order consumer + 4 payment consumer + 1 context):
```bash
./mvnw verify
```

## Port

`8085` (configurable via `PORT` env var)

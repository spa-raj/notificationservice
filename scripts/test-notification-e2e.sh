#!/bin/bash
# ==============================================================================
# Notification Service E2E Test Suite
# ==============================================================================
# Tests the full event-driven notification flow:
# Cart checkout → Order → Payment → Notifications logged/emailed
#
# Prerequisites:
#   - All 6 services running via docker compose on vibevault-network
#   - ngrok running for Razorpay webhook (if testing full payment flow)
#
# Usage:
#   ./test-notification-e2e.sh
#   TOKEN="xxx" ./test-notification-e2e.sh    # skip OAuth2 flow
# ==============================================================================

set -euo pipefail

USERSERVICE="http://localhost:8081"
PRODUCTSERVICE="http://localhost:8080"
CARTSERVICE="http://localhost:8082"
ORDERSERVICE="http://localhost:8083"
PAYMENTGATEWAY="http://localhost:8084"
NOTIFICATIONSERVICE="http://localhost:8085"

# Local docker-compose credentials
ADMIN_EMAIL="admin@gmail.com"
ADMIN_PASSWORD="abcd@1234"
CLIENT_ID="vibevault-client"
CLIENT_SECRET="abc@12345"
REDIRECT_URI="https://oauth.pstmn.io/v1/callback"
SCOPES="openid+profile+email+read+write"

PASS=0
FAIL=0
SKIP=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Helpers
# ============================================================================

assert_status() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    local body="${4:-}"

    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GREEN}PASS${NC} [$actual] $description"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} [$actual expected $expected] $description"
        [ -n "$body" ] && echo "       Response: $(echo "$body" | head -c 300)"
        FAIL=$((FAIL + 1))
    fi
}

request() {
    local method="$1"
    local url="$2"
    local headers="${3:-}"
    local data="${4:-}"

    local curl_args=(-s -w "\n%{http_code}" -X "$method" "$url")
    if [ -n "$headers" ]; then
        while IFS= read -r header; do
            [ -n "$header" ] && curl_args+=(-H "$header")
        done <<< "$headers"
    fi
    if [ -n "$data" ]; then
        curl_args+=(-d "$data")
    fi

    local response
    response=$(curl "${curl_args[@]}")
    BODY=$(echo "$response" | head -n -1)
    STATUS=$(echo "$response" | tail -n 1)
}

section() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
}

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

# ============================================================================
# OAuth2 Token Flow
# ============================================================================

get_oauth2_token() {
    set +e
    local username="$1"
    local password="$2"

    local COOKIE_JAR
    COOKIE_JAR=$(mktemp /tmp/notif_test_cookies.XXXXXX)

    local AUTH_URL="${USERSERVICE}/oauth2/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPES}"
    curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -L --max-redirs 1 -o /dev/null "$AUTH_URL"

    local LOGIN_PAGE
    LOGIN_PAGE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" "${USERSERVICE}/login")
    local CSRF
    CSRF=$(echo "$LOGIN_PAGE" | grep -oP 'name="_csrf".*?value="\K[^"]+')

    if [ -z "$CSRF" ]; then
        rm -f "$COOKIE_JAR"
        set -e
        echo ""
        return
    fi

    local ENCODED_PASSWORD
    ENCODED_PASSWORD=$(urlencode "$password")
    curl -s -D- -o /dev/null -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "${USERSERVICE}/login" \
        -d "username=${username}&password=${ENCODED_PASSWORD}&_csrf=${CSRF}" > /dev/null

    local AUTHORIZE_RESPONSE
    AUTHORIZE_RESPONSE=$(curl -s -D- -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
        "${USERSERVICE}/oauth2/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPES}&continue")

    local AUTHORIZE_LOCATION
    AUTHORIZE_LOCATION=$(echo "$AUTHORIZE_RESPONSE" | grep -i "^Location:" | tr -d '\r' || true)

    local AUTH_CODE=""
    if echo "$AUTHORIZE_LOCATION" | grep -q "code="; then
        AUTH_CODE=$(echo "$AUTHORIZE_LOCATION" | grep -oP 'code=\K[^&\s]+' || true)
    else
        local CONSENT_BODY
        CONSENT_BODY=$(echo "$AUTHORIZE_RESPONSE" | sed '1,/^\r$/d')
        local STATE
        STATE=$(echo "$CONSENT_BODY" | grep -oP 'name="state"[^>]*value="\K[^"]+' || true)

        if [ -z "$STATE" ]; then
            rm -f "$COOKIE_JAR"
            set -e
            echo ""
            return
        fi

        local CONSENT_RESPONSE
        CONSENT_RESPONSE=$(curl -s -D- -o /dev/null -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "${USERSERVICE}/oauth2/authorize" \
            -d "client_id=${CLIENT_ID}&state=${STATE}&scope=read&scope=profile&scope=write&scope=email")

        local CONSENT_LOCATION
        CONSENT_LOCATION=$(echo "$CONSENT_RESPONSE" | grep -i "^Location:" | tr -d '\r' || true)
        AUTH_CODE=$(echo "$CONSENT_LOCATION" | grep -oP 'code=\K[^&\s]+' || true)
    fi

    if [ -z "$AUTH_CODE" ]; then
        rm -f "$COOKIE_JAR"
        set -e
        echo ""
        return
    fi

    local TOKEN_RESPONSE
    TOKEN_RESPONSE=$(curl -s -X POST "${USERSERVICE}/oauth2/token" \
        -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        -d "grant_type=authorization_code" \
        -d "code=${AUTH_CODE}" \
        -d "redirect_uri=${REDIRECT_URI}")

    local TOKEN
    TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || echo "")

    rm -f "$COOKIE_JAR"
    set -e
    echo "$TOKEN"
}

# ============================================================================
# Test Suite
# ============================================================================

echo "=============================================="
echo "  Notification Service E2E Test Suite"
echo "=============================================="

# --------------------------------------------------
section "1. Health Checks (all 6 services)"
# --------------------------------------------------

request GET "$USERSERVICE/actuator/health"
assert_status "userservice health" "200" "$STATUS"

request GET "$PRODUCTSERVICE/actuator/health"
assert_status "productservice health" "200" "$STATUS"

request GET "$CARTSERVICE/actuator/health"
assert_status "cartservice health" "200" "$STATUS"

request GET "$ORDERSERVICE/actuator/health"
assert_status "orderservice health" "200" "$STATUS"

request GET "$PAYMENTGATEWAY/actuator/health"
assert_status "paymentgateway health" "200" "$STATUS"

request GET "$NOTIFICATIONSERVICE/actuator/health"
assert_status "notificationservice health" "200" "$STATUS"

# --------------------------------------------------
section "2. Setup Test User + OAuth2 Token"
# --------------------------------------------------

# Get admin JJWT token to create user/role
ADMIN_LOGIN_RESP=$(curl -s -X POST "$USERSERVICE/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}")
ADMIN_JJWT=$(echo "$ADMIN_LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || echo "")

# Ensure CUSTOMER role exists
if [ -n "$ADMIN_JJWT" ]; then
    request POST "$USERSERVICE/roles/create" "$(printf 'Authorization: %s\nContent-Type: application/json' "$ADMIN_JJWT")" '{"roleName":"CUSTOMER","description":"Customer role"}'
    echo -e "  ${GREEN}OK${NC} CUSTOMER role ready"
fi

# Use provided email or default to a test email
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-sparshraj90@gmail.com}"
NOTIFICATION_PASSWORD="Test@1234"
NOTIFICATION_PHONE="91$(date +%s | tail -c 9)"

# Create test user with real email
request POST "$USERSERVICE/auth/signup" "Content-Type: application/json" \
    "{\"email\":\"${NOTIFICATION_EMAIL}\",\"password\":\"${NOTIFICATION_PASSWORD}\",\"name\":\"Notification Test User\",\"phone\":\"${NOTIFICATION_PHONE}\",\"role\":\"CUSTOMER\"}"
if [ "$STATUS" = "201" ] || [ "$STATUS" = "409" ] || [ "$STATUS" = "400" ]; then
    echo -e "  ${GREEN}OK${NC} Test user ready (${NOTIFICATION_EMAIL})"
fi

# Get OAuth2 token for test user
if [ -n "${TOKEN:-}" ]; then
    echo -e "  ${GREEN}PASS${NC} Using provided TOKEN"
    PASS=$((PASS + 1))
else
    echo "  Obtaining OAuth2 token for ${NOTIFICATION_EMAIL}..."
    TOKEN=$(get_oauth2_token "$NOTIFICATION_EMAIL" "$NOTIFICATION_PASSWORD")
fi

if [[ "$TOKEN" =~ ^eyJ.*\..*\..*$ ]]; then
    echo -e "  ${GREEN}PASS${NC} OAuth2 token obtained for ${NOTIFICATION_EMAIL}"
    PASS=$((PASS + 1))
    AUTH_HEADERS="$(printf 'Authorization: Bearer %s\nContent-Type: application/json' "$TOKEN")"
    AUTH_ONLY="Authorization: Bearer $TOKEN"
else
    echo -e "  ${RED}FAIL${NC} Could not obtain OAuth2 token"
    FAIL=$((FAIL + 1))
    echo ""
    echo "=============================================="
    printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d skipped${NC}\n" "$PASS" "$FAIL" "$SKIP"
    echo "=============================================="
    exit 1
fi

# --------------------------------------------------
section "3. Trigger Full Saga (as ${NOTIFICATION_EMAIL})"
# --------------------------------------------------

# Need admin token to create product
echo "  Obtaining admin OAuth2 token for product creation..."
ADMIN_TOKEN=$(get_oauth2_token "$ADMIN_EMAIL" "$ADMIN_PASSWORD")
ADMIN_AUTH_HEADERS="$(printf 'Authorization: Bearer %s\nContent-Type: application/json' "$ADMIN_TOKEN")"

TIMESTAMP=$(date +%s)
PRODUCT_NAME="NotifTest-Product-${TIMESTAMP}"

request POST "$PRODUCTSERVICE/categories" "$ADMIN_AUTH_HEADERS" '{"name":"Electronics","description":"Electronic devices"}'
if [ "$STATUS" = "200" ] || [ "$STATUS" = "409" ]; then
    echo -e "  ${GREEN}OK${NC} Category ready"
fi

request POST "$PRODUCTSERVICE/products" "$ADMIN_AUTH_HEADERS" \
    "{\"name\":\"${PRODUCT_NAME}\",\"description\":\"Test product for notification\",\"price\":299.99,\"currency\":\"INR\",\"categoryName\":\"Electronics\"}"
assert_status "Create test product" "200" "$STATUS"
PRODUCT_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")
echo -e "  ${CYAN}Product ID: ${PRODUCT_ID}${NC}"

# Clear cart (as test user)
curl -s -X DELETE "$CARTSERVICE/cart" -H "$AUTH_ONLY" > /dev/null 2>&1
echo -e "  ${GREEN}OK${NC} Cart cleared"

# Add to cart (as test user — userId = NOTIFICATION_EMAIL)
request POST "$CARTSERVICE/cart/items" "$AUTH_HEADERS" \
    "{\"productId\":\"${PRODUCT_ID}\",\"quantity\":1}"
assert_status "Add to cart" "201" "$STATUS"

# Checkout → triggers ORDER_CREATED → PAYMENT_LINK → notifications to NOTIFICATION_EMAIL
request POST "$CARTSERVICE/cart/checkout" "$AUTH_ONLY"
assert_status "Checkout (triggers saga as ${NOTIFICATION_EMAIL})" "200" "$STATUS"

echo -e "  ${CYAN}Waiting for saga: cart → order → payment → notifications...${NC}"
sleep 10

# --------------------------------------------------
section "4. Verify Notifications in Logs"
# --------------------------------------------------

NOTIF_CONTAINER="notificationservice-app"

if docker ps --format '{{.Names}}' | grep -q "$NOTIF_CONTAINER"; then
    echo -e "  ${GREEN}OK${NC} Notification service container running"

    NOTIF_LOGS=$(docker logs "$NOTIF_CONTAINER" 2>&1 | tail -100)

    # Check for ORDER_CREATED notification
    if echo "$NOTIF_LOGS" | grep -q "Order Placed"; then
        echo -e "  ${GREEN}PASS${NC} ORDER_CREATED notification logged"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} ORDER_CREATED notification not found in logs"
        FAIL=$((FAIL + 1))
    fi

    # Check for NOTIFICATION banner
    if echo "$NOTIF_LOGS" | grep -q "NOTIFICATION"; then
        echo -e "  ${GREEN}PASS${NC} Console notification banner found"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} Console notification banner not found"
        FAIL=$((FAIL + 1))
    fi

    # Show recent notifications
    echo ""
    echo -e "  ${CYAN}Recent notifications:${NC}"
    echo "$NOTIF_LOGS" | grep -A3 "NOTIFICATION" | tail -20
    echo ""
else
    echo -e "  ${YELLOW}SKIP${NC} Notification container not running"
    SKIP=$((SKIP + 2))
fi

# --------------------------------------------------
section "5. Verify Order Created"
# --------------------------------------------------

request GET "$ORDERSERVICE/orders" "$AUTH_ONLY"
assert_status "GET /orders" "200" "$STATUS"

ORDER_ID=$(echo "$BODY" | python3 -c "
import sys,json
data = json.load(sys.stdin)
orders = data.get('content', [])
if orders:
    print(orders[0]['orderId'])
else:
    print('')
" 2>/dev/null || echo "")

if [ -n "$ORDER_ID" ]; then
    echo -e "  ${CYAN}Order ID: ${ORDER_ID}${NC}"
    echo -e "  ${GREEN}PASS${NC} Order created"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} No order found"
    FAIL=$((FAIL + 1))
fi

# --------------------------------------------------
section "6. Verify Payment Created"
# --------------------------------------------------

if [ -n "$ORDER_ID" ]; then
    request GET "$PAYMENTGATEWAY/payments/order/${ORDER_ID}" "$AUTH_ONLY"
    assert_status "GET /payments/order/{orderId}" "200" "$STATUS"

    PAYMENT_LINK=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('gatewayPaymentLink', ''))" 2>/dev/null || echo "")
    if [ -n "$PAYMENT_LINK" ]; then
        echo -e "  ${CYAN}Razorpay Link: ${PAYMENT_LINK}${NC}"
        echo -e "  ${GREEN}PASS${NC} Payment link generated"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} No payment link"
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "  ${YELLOW}SKIP${NC} No order ID"
    SKIP=$((SKIP + 2))
fi

# --------------------------------------------------
section "7. Interactive Payment + Full Saga Verification"
# --------------------------------------------------

if [ -n "$PAYMENT_LINK" ]; then
    echo ""
    echo -e "  ${YELLOW}═══════════════════════════════════════════════════${NC}"
    echo -e "  ${YELLOW}  Complete payment using Razorpay test mode:${NC}"
    echo -e "  ${YELLOW}  Link: ${PAYMENT_LINK}${NC}"
    echo -e "  ${YELLOW}  Card: 4111 1111 1111 1111${NC}"
    echo -e "  ${YELLOW}  Expiry: any future date | CVV: any 3 digits${NC}"
    echo -e "  ${YELLOW}═══════════════════════════════════════════════════${NC}"
    echo ""
    read -p "  Press ENTER after completing payment (or 's' to skip): " PAYMENT_CHOICE

    if [ "$PAYMENT_CHOICE" != "s" ] && [ "$PAYMENT_CHOICE" != "S" ]; then
        echo -e "  ${CYAN}Waiting for webhook + notifications...${NC}"
        sleep 12

        # Verify payment CONFIRMED
        request GET "$PAYMENTGATEWAY/payments/order/${ORDER_ID}" "$AUTH_ONLY"
        PAYMENT_STATUS=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status', ''))" 2>/dev/null || echo "")

        if [ "$PAYMENT_STATUS" = "CONFIRMED" ]; then
            echo -e "  ${GREEN}PASS${NC} Payment CONFIRMED"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} Payment status: ${PAYMENT_STATUS} (expected CONFIRMED)"
            FAIL=$((FAIL + 1))
        fi

        # Verify order CONFIRMED
        request GET "$ORDERSERVICE/orders/${ORDER_ID}" "$AUTH_ONLY"
        ORDER_STATUS=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status', ''))" 2>/dev/null || echo "")

        if [ "$ORDER_STATUS" = "CONFIRMED" ]; then
            echo -e "  ${GREEN}PASS${NC} Order CONFIRMED (saga complete!)"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} Order status: ${ORDER_STATUS} (expected CONFIRMED)"
            FAIL=$((FAIL + 1))
        fi

        # Verify PAYMENT_CONFIRMED notification in logs
        sleep 3
        NOTIF_LOGS_AFTER=$(docker logs "$NOTIF_CONTAINER" 2>&1 | tail -200)

        if echo "$NOTIF_LOGS_AFTER" | grep -q "Payment Successful"; then
            echo -e "  ${GREEN}PASS${NC} PAYMENT_CONFIRMED notification logged"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} PAYMENT_CONFIRMED notification not found"
            FAIL=$((FAIL + 1))
        fi

        if echo "$NOTIF_LOGS_AFTER" | grep -q "Order Confirmed"; then
            echo -e "  ${GREEN}PASS${NC} ORDER_CONFIRMED notification logged"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} ORDER_CONFIRMED notification not found"
            FAIL=$((FAIL + 1))
        fi

        # Verify PAYMENT_CONFIRMED in Kafka
        KAFKA_CONTAINER="cartservice-kafka"
        if docker ps --format '{{.Names}}' | grep -q "$KAFKA_CONTAINER"; then
            CONFIRMED_EVENTS=$(docker exec "$KAFKA_CONTAINER" kafka-console-consumer \
                --bootstrap-server localhost:9092 \
                --topic payment-events \
                --from-beginning \
                --timeout-ms 5000 2>/dev/null || echo "")

            if echo "$CONFIRMED_EVENTS" | grep -q "PAYMENT_CONFIRMED"; then
                echo -e "  ${GREEN}PASS${NC} PAYMENT_CONFIRMED in payment-events topic"
                PASS=$((PASS + 1))
            else
                echo -e "  ${RED}FAIL${NC} PAYMENT_CONFIRMED not in Kafka"
                FAIL=$((FAIL + 1))
            fi
        fi
    else
        echo -e "  ${YELLOW}SKIP${NC} Payment skipped"
        SKIP=$((SKIP + 5))
    fi
else
    echo -e "  ${YELLOW}SKIP${NC} No payment link"
    SKIP=$((SKIP + 5))
fi

# --------------------------------------------------
section "8. Full Saga Summary"
# --------------------------------------------------

echo -e "  ${CYAN}Complete saga flow:${NC}"
echo -e "  ${CYAN}  1. Cart checkout → CHECKOUT_INITIATED${NC}"
echo -e "  ${CYAN}  2. Order service → ORDER_CREATED → notification: 'Order Placed'${NC}"
echo -e "  ${CYAN}  3. Payment gateway → Razorpay payment link (PENDING)${NC}"
echo -e "  ${CYAN}  4. User pays → Razorpay webhook → PAYMENT_CONFIRMED${NC}"
echo -e "  ${CYAN}  5. Payment gateway → notification: 'Payment Successful'${NC}"
echo -e "  ${CYAN}  6. Order service → ORDER_CONFIRMED → notification: 'Order Confirmed'${NC}"
echo -e "  ${CYAN}  7. All notifications logged to console (+ SES email if enabled)${NC}"

# --------------------------------------------------
echo ""
echo "=============================================="
printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d skipped${NC}\n" "$PASS" "$FAIL" "$SKIP"
echo "=============================================="

[ "$FAIL" -eq 0 ]

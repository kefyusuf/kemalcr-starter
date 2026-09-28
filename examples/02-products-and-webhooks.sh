#!/usr/bin/env bash
# Tutorial: product catalog + outbound webhook
# Usage: ./examples/02-products-and-webhooks.sh [BASE_URL]
set -euo pipefail

BASE="${1:-http://localhost:3000}"
EMAIL="catalog-$(date +%s)@example.com"
PASSWORD="Passw0rd!"

REGISTER=$(curl -sf -X POST "$BASE/v1/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Catalog User\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
TOKEN=$(echo "$REGISTER" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
test -n "$TOKEN" || { echo "register failed"; exit 1; }

auth() { curl -sS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; }

ORG=$(auth -X POST "$BASE/v1/organizations" -d '{"name":"Catalog Org","slug":"catalog-org"}')
ORG_ID=$(echo "$ORG" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

echo "==> Create product"
auth -X POST "$BASE/v1/organizations/$ORG_ID/products" \
  -d '{"sku":"SKU-1","name":"Widget","description":"Demo","price_cents":1999,"currency":"USD"}'
echo

echo "==> List products"
auth "$BASE/v1/organizations/$ORG_ID/products"
echo

echo "==> Create webhook (secret printed once — store it to verify X-Webhook-Signature)"
auth -X POST "$BASE/v1/organizations/$ORG_ID/webhooks" \
  -d '{"url":"https://example.com/hooks","description":"demo","event_types":[]}'
echo

echo "==> List webhook deliveries"
WEBHOOK_ID=$(auth "$BASE/v1/organizations/$ORG_ID/webhooks" | sed -n 's/.*"id":"\(whk_[^"]*\)".*/\1/p' | head -1)
if [ -n "$WEBHOOK_ID" ]; then
  auth "$BASE/v1/organizations/$ORG_ID/webhooks/$WEBHOOK_ID/deliveries"
  echo
fi

echo "==> Done"

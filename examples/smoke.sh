#!/usr/bin/env bash
# End-to-end smoke flow against a running stack (./scripts/dev).
# Usage: ./examples/smoke.sh [BASE_URL]
set -euo pipefail

BASE="${1:-http://localhost:3000}"
EMAIL="demo-$(date +%s)@example.com"
PASSWORD="Passw0rd!"

echo "==> Health"
curl -sf "$BASE/health" | tee /tmp/kemalcr-health.json
echo

echo "==> Register $EMAIL"
REGISTER=$(curl -sf -X POST "$BASE/v1/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Demo User\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
echo "$REGISTER" | head -c 200
echo
TOKEN=$(echo "$REGISTER" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
echo "access_token acquired"

auth() { curl -sS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; }

echo "==> Create organization"
ORG=$(auth -X POST "$BASE/v1/organizations" -d '{"name":"Demo Org","slug":"demo-org"}')
echo "$ORG"
ORG_ID=$(echo "$ORG" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

echo "==> Create product"
auth -X POST "$BASE/v1/organizations/$ORG_ID/products" \
  -d '{"sku":"SKU-DEMO","name":"Demo Product","price_cents":1999,"currency":"USD"}'
echo

echo "==> Create webhook endpoint (secret printed once)"
auth -X POST "$BASE/v1/organizations/$ORG_ID/webhooks" \
  -d '{"url":"https://example.com/hooks","description":"demo","event_types":[]}'
echo

echo "==> List products"
auth "$BASE/v1/organizations/$ORG_ID/products"
echo

echo "==> Password reset request (always 202)"
curl -sS -o /dev/null -w "%{http_code}\n" -X POST "$BASE/v1/auth/password-reset/request" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\"}"

echo "==> Done"

#!/usr/bin/env bash
# Tutorial: register → login → organization → me
# Usage: ./examples/01-auth-and-org.sh [BASE_URL]
set -euo pipefail

BASE="${1:-http://localhost:3000}"
EMAIL="tutorial-$(date +%s)@example.com"
PASSWORD="Passw0rd!"

echo "==> Register $EMAIL"
REGISTER=$(curl -sf -X POST "$BASE/v1/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Tutorial User\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
TOKEN=$(echo "$REGISTER" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
test -n "$TOKEN" || { echo "register failed: $REGISTER"; exit 1; }
echo "access_token ok"

auth() { curl -sS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; }

echo "==> GET /v1/me"
auth "$BASE/v1/me"
echo

echo "==> Create organization"
ORG=$(auth -X POST "$BASE/v1/organizations" -d '{"name":"Tutorial Org","slug":"tutorial-org"}')
echo "$ORG"
ORG_ID=$(echo "$ORG" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

echo "==> List memberships"
auth "$BASE/v1/organizations/$ORG_ID/memberships"
echo

echo "==> Login again (new token pair)"
curl -sf -X POST "$BASE/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" | head -c 200
echo
echo "==> Done"

#!/bin/bash
# Records real API responses from the local backend into CalibreKit test
# fixtures. Re-run whenever the API shape changes. Requires the local docker
# backend on :8000 with seeded demo data.
set -euo pipefail
cd "$(dirname "$0")/.."
FIXTURES=Packages/CalibreKit/Tests/CalibreKitTests/Fixtures
BASE=http://localhost:8000
# Test account registered against the local dev DB (register-or-login).
BUYER_EMAIL="iosbuyer.calibre@gmail.com"
BUYER_PASSWORD="CalibreiOS123!"
mkdir -p "$FIXTURES"

jar=$(mktemp)
trap 'rm -f "$jar"' EXIT

grab() { # name method path [data]
  local name=$1 method=$2 path=$3 data=${4:-}
  local args=(-s -m 20 -X "$method" -b "$jar" -c "$jar" -H "Accept: application/json")
  [ -n "$data" ] && args+=(-H "Content-Type: application/json" -d "$data")
  curl "${args[@]}" "$BASE$path" | python3 -m json.tool > "$FIXTURES/$name.json" \
    && echo "  $name.json" || echo "  FAILED: $name"
}

echo "Recording public fixtures…"
grab listings-page GET "/listings?page_size=4&view=full&include_total=true"
grab listings-card GET "/listings?page_size=4&view=card"
grab listings-metadata GET "/listings/metadata"
grab listings-home GET "/listings/home"

LISTING_ID=$(python3 -c "import json;print(json.load(open('$FIXTURES/listings-page.json'))['data']['results'][0]['id'])")
grab listing-detail GET "/listings/$LISTING_ID"

echo "Signing in demo buyer…"
grab auth-login POST "/auth/login" "{\"identifier\": \"$BUYER_EMAIL\", \"password\": \"$BUYER_PASSWORD\"}"

echo "Recording authenticated fixtures…"
grab auth-me GET "/auth/me"
grab account-profile GET "/account/profile"
grab account-addresses GET "/account/addresses"
grab cart GET "/cart"
grab watchlist GET "/watchlist"
grab account-offers GET "/account/offers"
grab buyer-orders GET "/buyer/orders?page_size=5"
grab account-dashboard GET "/account/dashboard"
grab seller-readiness GET "/stripe/seller-readiness"
grab account-listings GET "/account/listings"
grab watch-requests GET "/account/watch-requests"
grab support-thread GET "/support/thread"
grab notification-preferences GET "/account/notification-preferences"

echo "Done → $FIXTURES"

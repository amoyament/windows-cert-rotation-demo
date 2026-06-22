#!/usr/bin/env bash
# Send a test certificate expiry event to the EDA event stream
# Usage: source .env.demo && bash scripts/send_test_event.sh

set -euo pipefail

if [[ -z "${EDA_EVENT_STREAM_URL:-}" ]]; then
  echo "ERROR: EDA_EVENT_STREAM_URL is not set. Run: source .env.demo"
  exit 1
fi

if [[ -z "${WINDOWS_PRIVATE_IP:-}" ]]; then
  echo "ERROR: WINDOWS_PRIVATE_IP is not set. Run: source .env.demo"
  exit 1
fi

# Load thumbprint if available
OLD_THUMBPRINT="${OLD_CERT_THUMBPRINT:-REPLACE_WITH_THUMBPRINT}"

echo "Sending test cert expiry event to EDA..."
echo "  Event Stream URL: ${EDA_EVENT_STREAM_URL}"
echo "  Host: ${WINDOWS_PRIVATE_IP}"
echo "  Thumbprint: ${OLD_THUMBPRINT}"

curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -u "${EDA_WEBHOOK_USER:-webhook}:${EDA_WEBHOOK_PASS:-Demo-EDA-Cert-2026!}" \
  -H "Content-Type: application/json" \
  -d "{
    \"event_type\": \"cert_expiring\",
    \"host\": \"${WINDOWS_PRIVATE_IP}\",
    \"thumbprint\": \"${OLD_THUMBPRINT}\",
    \"days_left\": 3,
    \"cert_subject\": \"CN=demo.contoso.com\",
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }"

echo ""
echo "Event sent. Watch the AAP UI for the job to trigger."

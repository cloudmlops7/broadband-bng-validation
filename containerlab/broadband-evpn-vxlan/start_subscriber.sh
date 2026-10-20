#!/bin/bash
set -euo pipefail

SUBSCRIBER="subscriber1"
BNG="broadband-bng"
USER="user1"
EXPECTED_IP="10.10.10.10"

echo "=========================================="
echo " Starting PPPoE subscriber"
echo "=========================================="

# Subscriber eth1 must exist before PPPoE can start.
if ! docker exec "$SUBSCRIBER" ip link show eth1 >/dev/null 2>&1; then
    echo "ERROR: subscriber eth1 does not exist."
    echo "Run attach_broadband_endpoints.sh first."
    exit 1
fi

if ! docker exec "$SUBSCRIBER" ip link show eth1 | grep -q "LOWER_UP"; then
    echo "ERROR: subscriber eth1 is not LOWER_UP."
    exit 1
fi

echo "Subscriber eth1 is ready."

# Do not create a second PPP session.
if docker exec "$SUBSCRIBER" ip link show ppp0 >/dev/null 2>&1; then
    echo "PPP session already exists."
else
    echo "Starting pppd..."
    docker exec -d "$SUBSCRIBER" \
        pppd call broadband
fi

echo "Waiting for PPP session establishment..."

READY=0

for i in $(seq 1 20); do
    if docker exec "$SUBSCRIBER" \
        ip -4 addr show ppp0 2>/dev/null | grep -q "$EXPECTED_IP"; then

        READY=1
        break
    fi

    sleep 1
done

if [ "$READY" -ne 1 ]; then
    echo "ERROR: PPP session did not establish."

    echo
    echo "===== Subscriber PPP state ====="
    docker exec "$SUBSCRIBER" ip addr || true

    echo
    echo "===== BNG sessions ====="
    docker exec "$BNG" accel-cmd show sessions || true

    echo
    echo "===== Recent RADIUS log ====="
    docker logs radius-debug 2>&1 | tail -50 || true

    exit 1
fi

echo
echo "===== Subscriber PPP interface ====="
docker exec "$SUBSCRIBER" ip -4 addr show ppp0

echo
echo "===== BNG session ====="
docker exec "$BNG" accel-cmd show sessions

echo
echo "=========================================="
echo " PPPoE subscriber startup PASSED"
echo "=========================================="

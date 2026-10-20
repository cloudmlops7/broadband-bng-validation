#!/bin/bash
set -euo pipefail

BNG="broadband-bng"

echo "=========================================="
echo " Starting Accel-PPP BNG"
echo "=========================================="

BNG_PID=$(docker inspect -f '{{.State.Pid}}' "$BNG")

# eth1 must exist before Accel-PPP starts
if ! sudo nsenter -t "$BNG_PID" -n ip link show eth1 >/dev/null 2>&1; then
    echo "ERROR: BNG eth1 does not exist."
    echo "Run ./attach_broadband_endpoints.sh first."
    exit 1
fi

# eth1 must be operational
if ! sudo nsenter -t "$BNG_PID" -n ip link show eth1 | grep -q "LOWER_UP"; then
    echo "ERROR: BNG eth1 is not LOWER_UP."
    exit 1
fi

# Avoid starting a duplicate Accel-PPP process
if docker exec "$BNG" pgrep -x accel-pppd >/dev/null 2>&1; then
    echo "Accel-PPP is already running."
else
    echo "eth1 exists and is UP."
    echo "Starting Accel-PPP..."

    docker exec -d "$BNG" \
      /usr/sbin/accel-pppd \
      -c /etc/accel-ppp/accel-ppp.conf

    sleep 2
fi

# Verify process
if ! docker exec "$BNG" pgrep -x accel-pppd >/dev/null 2>&1; then
    echo "ERROR: Accel-PPP failed to start."
    exit 1
fi

echo
echo "Accel-PPP process:"
docker exec "$BNG" ps -ef | grep '[a]ccel-pppd'

echo
echo "PPPoE packet socket:"
sudo nsenter -t "$BNG_PID" -n ss -A packet -a -p | grep ppp_disc || {
    echo "ERROR: PPPoE discovery socket not found."
    exit 1
}

echo
echo "BNG startup validation PASSED."

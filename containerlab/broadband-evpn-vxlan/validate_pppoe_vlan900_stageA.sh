#!/bin/bash
set -euo pipefail

SUBSCRIBER="subscriber1"
BNG="broadband-bng"

EXPECTED_USER="user1"
EXPECTED_IP="10.10.10.10"
BNG_IP="10.10.10.1"

ACCESS_IF="eth1"
VLAN_ID="900"
VLAN_IF="${ACCESS_IF}.${VLAN_ID}"
VNI="10100"

echo "=========================================="
echo " PPPoE subscriber validation"
echo "=========================================="

# ----------------------------------------------------------
# 1. BNG subscriber session
# ----------------------------------------------------------

echo
echo "[1/5] Checking BNG subscriber session..."

SESSION_OUTPUT=$(docker exec "$BNG" accel-cmd show sessions)

echo "$SESSION_OUTPUT"

if ! echo "$SESSION_OUTPUT" | grep -q "$EXPECTED_USER"; then
    echo "ERROR: subscriber $EXPECTED_USER is not active."
    exit 1
fi

if ! echo "$SESSION_OUTPUT" | grep -q "$EXPECTED_IP"; then
    echo "ERROR: expected subscriber IP $EXPECTED_IP not found."
    exit 1
fi

echo "PASS: subscriber session active."

# ----------------------------------------------------------
# 2. Subscriber PPP interface / IPCP
# ----------------------------------------------------------

echo
echo "[2/5] Checking subscriber PPP interface..."

if ! docker exec "$SUBSCRIBER" \
    ip addr show ppp0 >/dev/null 2>&1; then
    echo "ERROR: subscriber ppp0 does not exist."
    exit 1
fi

PPP_OUTPUT=$(docker exec "$SUBSCRIBER" ip addr show ppp0)

echo "$PPP_OUTPUT"

if ! echo "$PPP_OUTPUT" | grep -q "$EXPECTED_IP"; then
    echo "ERROR: ppp0 does not contain $EXPECTED_IP."
    exit 1
fi

if ! echo "$PPP_OUTPUT" | grep -q "$BNG_IP"; then
    echo "ERROR: expected BNG PPP peer $BNG_IP not found."
    exit 1
fi

echo "PASS: PPP interface and IPCP addressing configured."

# ----------------------------------------------------------
# 3. Subscriber -> BNG data plane
# ----------------------------------------------------------

echo
echo "[3/5] Testing subscriber -> BNG data plane..."

if docker exec "$SUBSCRIBER" \
    ping -c 5 -W 2 "$BNG_IP"; then

    echo "PASS: subscriber can reach BNG PPP gateway."
else
    echo "ERROR: subscriber cannot reach $BNG_IP."
    exit 1
fi

# ----------------------------------------------------------
# 4. Physical EVPN access attachment
# ----------------------------------------------------------

echo
echo "[4/5] Checking EVPN access interfaces..."

SUB_ACCESS=$(
    docker exec "$SUBSCRIBER" \
        ip -br link show "$ACCESS_IF"
)

BNG_ACCESS=$(
    docker exec "$BNG" \
        ip -br link show "$ACCESS_IF"
)

echo "$SUB_ACCESS"
echo "$BNG_ACCESS"

if ! echo "$SUB_ACCESS" | grep -q "LOWER_UP"; then
    echo "ERROR: subscriber $ACCESS_IF is not operational."
    exit 1
fi

if ! echo "$BNG_ACCESS" | grep -q "LOWER_UP"; then
    echo "ERROR: BNG $ACCESS_IF is not operational."
    exit 1
fi

echo "PASS: physical EVPN access interfaces operational."

# ----------------------------------------------------------
# 5. VLAN service interface
# ----------------------------------------------------------

echo
echo "[5/5] Checking VLAN $VLAN_ID service interfaces..."

if ! docker exec "$SUBSCRIBER" \
    ip link show "$VLAN_IF" >/dev/null 2>&1; then
    echo "ERROR: subscriber $VLAN_IF does not exist."
    exit 1
fi

if ! docker exec "$BNG" \
    ip link show "$VLAN_IF" >/dev/null 2>&1; then
    echo "ERROR: BNG $VLAN_IF does not exist."
    exit 1
fi

SUB_VLAN=$(
    docker exec "$SUBSCRIBER" \
        ip -d link show "$VLAN_IF"
)

BNG_VLAN=$(
    docker exec "$BNG" \
        ip -d link show "$VLAN_IF"
)

echo
echo "Subscriber $VLAN_IF:"
echo "$SUB_VLAN"

echo
echo "BNG $VLAN_IF:"
echo "$BNG_VLAN"

if ! echo "$SUB_VLAN" |
    grep -q "vlan protocol 802.1Q id $VLAN_ID"; then

    echo "ERROR: subscriber $VLAN_IF is not VLAN $VLAN_ID."
    exit 1
fi

if ! echo "$BNG_VLAN" |
    grep -q "vlan protocol 802.1Q id $VLAN_ID"; then

    echo "ERROR: BNG $VLAN_IF is not VLAN $VLAN_ID."
    exit 1
fi

if ! echo "$SUB_VLAN" | grep -q "LOWER_UP"; then
    echo "ERROR: subscriber $VLAN_IF is not operational."
    exit 1
fi

if ! echo "$BNG_VLAN" | grep -q "LOWER_UP"; then
    echo "ERROR: BNG $VLAN_IF is not operational."
    exit 1
fi

echo "PASS: VLAN $VLAN_ID service interfaces operational."

# ----------------------------------------------------------
# Final result
# ----------------------------------------------------------

echo
echo "=========================================="
echo " PPPoE ACCEPTANCE TEST: PASS"
echo "=========================================="
echo "User        : $EXPECTED_USER"
echo "Subscriber  : $EXPECTED_IP"
echo "BNG         : $BNG_IP"
echo "Access VLAN : $VLAN_ID"
echo "Transport   : EVPN/VXLAN"
echo "VNI         : $VNI"
echo "AAA         : RADIUS"

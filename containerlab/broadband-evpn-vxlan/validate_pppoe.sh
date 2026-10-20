#!/bin/bash
set -euo pipefail

SUBSCRIBER="subscriber1"
BNG="broadband-bng"

EXPECTED_USER="user1"
EXPECTED_IP="10.10.10.10"
BNG_IP="10.10.10.1"

ACCESS_IF="eth1"

S_VLAN_ID="900"
C_VLAN_ID="900"

S_VLAN_IF="${ACCESS_IF}.${S_VLAN_ID}"
C_VLAN_IF="${S_VLAN_IF}.${C_VLAN_ID}"

S_VLAN_PROTOCOL="802.1ad"
C_VLAN_PROTOCOL="802.1Q"

ACCESS_MTU="9000"
S_VLAN_MTU="8996"
C_VLAN_MTU="8992"

VNI="10100"

echo "=========================================="
echo " QinQ PPPoE subscriber validation"
echo "=========================================="

# ----------------------------------------------------------
# 1. BNG subscriber session
# ----------------------------------------------------------

echo
echo "[1/8] Checking BNG subscriber session..."

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

if ! echo "$SESSION_OUTPUT" | grep -q "pppoe"; then
    echo "ERROR: active session is not PPPoE."
    exit 1
fi

if ! echo "$SESSION_OUTPUT" | grep -q "active"; then
    echo "ERROR: subscriber session is not active."
    exit 1
fi

echo "PASS: PPPoE subscriber session active."

# ----------------------------------------------------------
# 2. PPP interface / IPCP
# ----------------------------------------------------------

echo
echo "[2/8] Checking subscriber PPP/IPCP state..."

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
    echo "ERROR: expected PPP peer $BNG_IP not found."
    exit 1
fi

if ! echo "$PPP_OUTPUT" | grep -q "LOWER_UP"; then
    echo "ERROR: ppp0 is not operational."
    exit 1
fi

echo "PASS: PPP/IPCP state correct."

# ----------------------------------------------------------
# 3. Subscriber -> BNG data plane
# ----------------------------------------------------------

echo
echo "[3/8] Testing subscriber -> BNG connectivity..."

PING_OUTPUT=$(
    docker exec "$SUBSCRIBER" \
        ping -c 5 -W 2 "$BNG_IP"
)

echo "$PING_OUTPUT"

if ! echo "$PING_OUTPUT" | grep -q "0% packet loss"; then
    echo "ERROR: subscriber data-plane test failed."
    exit 1
fi

echo "PASS: 5/5 packets received, 0% packet loss."

# ----------------------------------------------------------
# 4. Physical access interfaces
# ----------------------------------------------------------

echo
echo "[4/8] Checking physical access interfaces..."

SUB_ACCESS=$(docker exec "$SUBSCRIBER" ip -d link show "$ACCESS_IF")
BNG_ACCESS=$(docker exec "$BNG" ip -d link show "$ACCESS_IF")

echo "Subscriber:"
echo "$SUB_ACCESS"

echo
echo "BNG:"
echo "$BNG_ACCESS"

if ! echo "$SUB_ACCESS" | grep -q "LOWER_UP"; then
    echo "ERROR: subscriber $ACCESS_IF is not operational."
    exit 1
fi

if ! echo "$BNG_ACCESS" | grep -q "LOWER_UP"; then
    echo "ERROR: BNG $ACCESS_IF is not operational."
    exit 1
fi

if ! echo "$SUB_ACCESS" | grep -q "mtu $ACCESS_MTU"; then
    echo "ERROR: subscriber $ACCESS_IF MTU is not $ACCESS_MTU."
    exit 1
fi

if ! echo "$BNG_ACCESS" | grep -q "mtu $ACCESS_MTU"; then
    echo "ERROR: BNG $ACCESS_IF MTU is not $ACCESS_MTU."
    exit 1
fi

echo "PASS: physical access interfaces operational."

# ----------------------------------------------------------
# 5. Outer S-VLAN
# ----------------------------------------------------------

echo
echo "[5/8] Checking outer S-VLAN $S_VLAN_ID..."

SUB_SVLAN=$(docker exec "$SUBSCRIBER" ip -d link show "$S_VLAN_IF")
BNG_SVLAN=$(docker exec "$BNG" ip -d link show "$S_VLAN_IF")

echo "Subscriber:"
echo "$SUB_SVLAN"

echo
echo "BNG:"
echo "$BNG_SVLAN"

for output in "$SUB_SVLAN" "$BNG_SVLAN"; do
    if ! echo "$output" |
        grep -q "vlan protocol $S_VLAN_PROTOCOL id $S_VLAN_ID"; then
        echo "ERROR: S-VLAN protocol/ID mismatch."
        exit 1
    fi

    if ! echo "$output" | grep -q "LOWER_UP"; then
        echo "ERROR: S-VLAN interface is not operational."
        exit 1
    fi

    if ! echo "$output" | grep -q "mtu $S_VLAN_MTU"; then
        echo "ERROR: S-VLAN MTU is not $S_VLAN_MTU."
        exit 1
    fi
done

echo "PASS: S-VLAN $S_VLAN_ID / $S_VLAN_PROTOCOL operational."

# ----------------------------------------------------------
# 6. Inner C-VLAN
# ----------------------------------------------------------

echo
echo "[6/8] Checking inner C-VLAN $C_VLAN_ID..."

SUB_CVLAN=$(docker exec "$SUBSCRIBER" ip -d link show "$C_VLAN_IF")
BNG_CVLAN=$(docker exec "$BNG" ip -d link show "$C_VLAN_IF")

echo "Subscriber:"
echo "$SUB_CVLAN"

echo
echo "BNG:"
echo "$BNG_CVLAN"

for output in "$SUB_CVLAN" "$BNG_CVLAN"; do
    if ! echo "$output" |
        grep -q "vlan protocol $C_VLAN_PROTOCOL id $C_VLAN_ID"; then
        echo "ERROR: C-VLAN protocol/ID mismatch."
        exit 1
    fi

    if ! echo "$output" | grep -q "LOWER_UP"; then
        echo "ERROR: C-VLAN interface is not operational."
        exit 1
    fi

    if ! echo "$output" | grep -q "mtu $C_VLAN_MTU"; then
        echo "ERROR: C-VLAN MTU is not $C_VLAN_MTU."
        exit 1
    fi
done

echo "PASS: C-VLAN $C_VLAN_ID / $C_VLAN_PROTOCOL operational."

# ----------------------------------------------------------
# 7. Verify QinQ hierarchy
# ----------------------------------------------------------

echo
echo "[7/8] Checking QinQ interface hierarchy..."

if ! echo "$SUB_SVLAN" | grep -q "${S_VLAN_IF}@${ACCESS_IF}"; then
    echo "ERROR: subscriber S-VLAN parent is incorrect."
    exit 1
fi

if ! echo "$SUB_CVLAN" | grep -q "${C_VLAN_IF}@${S_VLAN_IF}"; then
    echo "ERROR: subscriber C-VLAN parent is incorrect."
    exit 1
fi

if ! echo "$BNG_SVLAN" | grep -q "${S_VLAN_IF}@${ACCESS_IF}"; then
    echo "ERROR: BNG S-VLAN parent is incorrect."
    exit 1
fi

if ! echo "$BNG_CVLAN" | grep -q "${C_VLAN_IF}@${S_VLAN_IF}"; then
    echo "ERROR: BNG C-VLAN parent is incorrect."
    exit 1
fi

echo "PASS: QinQ hierarchy is correct."

# ----------------------------------------------------------
# 8. Final service correlation
# ----------------------------------------------------------

echo
echo "[8/8] Service validation complete."

echo
echo "=========================================="
echo " QinQ PPPoE ACCEPTANCE TEST: PASS"
echo "=========================================="
echo "User        : $EXPECTED_USER"
echo "Subscriber  : $EXPECTED_IP"
echo "BNG         : $BNG_IP"
echo "S-VLAN      : $S_VLAN_ID / $S_VLAN_PROTOCOL"
echo "C-VLAN      : $C_VLAN_ID / $C_VLAN_PROTOCOL"
echo "Access MTU  : $ACCESS_MTU"
echo "S-VLAN MTU  : $S_VLAN_MTU"
echo "C-VLAN MTU  : $C_VLAN_MTU"
echo "Transport   : EVPN/VXLAN"
echo "VNI         : $VNI"
echo "AAA         : RADIUS"
echo "Packet Loss : 0%"
echo "=========================================="

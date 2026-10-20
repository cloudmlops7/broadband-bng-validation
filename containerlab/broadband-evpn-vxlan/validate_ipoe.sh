#!/usr/bin/env bash

set -u

PASS=0
FAIL=0

check_pass() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

echo "============================================================"
echo " IPoE / DHCP QinQ VALIDATION"
echo "============================================================"

echo
echo "[1] Subscriber QinQ interfaces"

if docker exec ipoe-subscriber ip -d link show eth1.900 2>/dev/null \
    | grep -q "vlan protocol 802.1ad id 900"; then
    check_pass "Outer S-VLAN 900 / 802.1ad"
else
    check_fail "Outer S-VLAN 900 / 802.1ad"
fi

if docker exec ipoe-subscriber ip -d link show eth1.900.901 2>/dev/null \
    | grep -q "vlan protocol 802.1Q id 901"; then
    check_pass "Inner C-VLAN 901 / 802.1Q"
else
    check_fail "Inner C-VLAN 901 / 802.1Q"
fi

echo
echo "[2] Subscriber DHCP address"

SUB_IP=$(docker exec ipoe-subscriber \
    sh -c "ip -4 -o addr show dev eth1.900.901 | awk '{print \$4}' | cut -d/ -f1")

if [[ "$SUB_IP" == "10.20.20.10" ]]; then
    check_pass "DHCP subscriber IP = $SUB_IP"
else
    check_fail "Expected 10.20.20.10, found ${SUB_IP:-none}"
fi

echo
echo "[3] DHCP server"

if docker exec ipoe-dhcp-server pgrep dhcpd >/dev/null 2>&1; then
    check_pass "DHCP server running"
else
    check_fail "DHCP server not running"
fi

if docker exec ipoe-dhcp-server \
    grep -q "binding state active" /var/lib/dhcp/dhcpd.leases; then
    check_pass "Active DHCP lease present"
else
    check_fail "No active DHCP lease"
fi

echo
echo "[4] ISP service interface"

if docker exec ipoe-dhcp-server \
    ip -4 addr show eth1.900.901 | grep -q "10.20.20.1/24"; then
    check_pass "DHCP gateway = 10.20.20.1/24"
else
    check_fail "DHCP gateway missing"
fi

echo
echo "[5] End-to-end connectivity"

PING_OUT=$(docker exec ipoe-subscriber ping -c 5 -W 1 10.20.20.1 2>&1)

if echo "$PING_OUT" | grep -q "0% packet loss"; then
    check_pass "Subscriber -> DHCP gateway: 5 packets / 0% loss"
else
    check_fail "Subscriber -> DHCP gateway connectivity"
fi

echo
echo "============================================================"
echo " RESULTS"
echo "============================================================"
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
    echo
    echo "IPoE/DHCP VALIDATION: PASS"
    echo "Subscriber : ${SUB_IP}"
    echo "Gateway    : 10.20.20.1"
    echo "QinQ       : S900 / C901"
    echo "Transport  : EVPN/VXLAN"
    exit 0
else
    echo
    echo "IPoE/DHCP VALIDATION: FAIL"
    exit 1
fi

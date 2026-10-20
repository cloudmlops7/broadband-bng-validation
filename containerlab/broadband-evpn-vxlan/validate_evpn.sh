#!/bin/bash
set -euo pipefail

LEAF1="clab-broadband-evpn-leaf1"
LEAF2="clab-broadband-evpn-leaf2"

VNI="10100"

LEAF1_VTEP="11.11.11.11"
LEAF2_VTEP="22.22.22.22"

SUB_MAC="3e:4c:14:33:9f:15"
BNG_MAC="0e:62:73:e4:2d:d2"

echo "=========================================="
echo " EVPN/VXLAN transport validation"
echo "=========================================="

# ----------------------------------------------------------
# 1. Leaf1 EVPN BGP peers
# ----------------------------------------------------------

echo
echo "[1/6] Checking Leaf1 EVPN BGP peers..."

L1_BGP=$(docker exec "$LEAF1" \
    vtysh -c "show bgp l2vpn evpn summary")

echo "$L1_BGP"

for peer in 10.0.11.2 10.0.12.2; do
    LINE=$(echo "$L1_BGP" | awk -v p="$peer" '$1 == p')

    if [ -z "$LINE" ]; then
        echo "ERROR: Leaf1 EVPN peer $peer not found."
        exit 1
    fi

    # Established peers show a numeric prefix count in
    # the State/PfxRcd column rather than Idle/Active/etc.
    STATE=$(echo "$LINE" | awk '{print $(NF-2)}')

    if ! [[ "$STATE" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Leaf1 EVPN peer $peer is not established."
        exit 1
    fi
done

echo "PASS: Leaf1 EVPN peers established."

# ----------------------------------------------------------
# 2. Leaf2 EVPN BGP peers
# ----------------------------------------------------------

echo
echo "[2/6] Checking Leaf2 EVPN BGP peers..."

L2_BGP=$(docker exec "$LEAF2" \
    vtysh -c "show bgp l2vpn evpn summary")

echo "$L2_BGP"

for peer in 10.0.21.2 10.0.22.2; do
    LINE=$(echo "$L2_BGP" | awk -v p="$peer" '$1 == p')

    if [ -z "$LINE" ]; then
        echo "ERROR: Leaf2 EVPN peer $peer not found."
        exit 1
    fi

    STATE=$(echo "$LINE" | awk '{print $(NF-2)}')

    if ! [[ "$STATE" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Leaf2 EVPN peer $peer is not established."
        exit 1
    fi
done

echo "PASS: Leaf2 EVPN peers established."

# ----------------------------------------------------------
# 3. VNI state
# ----------------------------------------------------------

echo
echo "[3/6] Checking VNI $VNI..."

L1_VNI=$(docker exec "$LEAF1" \
    vtysh -c "show evpn vni")

L2_VNI=$(docker exec "$LEAF2" \
    vtysh -c "show evpn vni")

echo "Leaf1:"
echo "$L1_VNI"

echo
echo "Leaf2:"
echo "$L2_VNI"

if ! echo "$L1_VNI" |
    grep -Eq "^${VNI}[[:space:]]+L2[[:space:]]+vxlan${VNI}"; then
    echo "ERROR: VNI $VNI missing on Leaf1."
    exit 1
fi

if ! echo "$L2_VNI" |
    grep -Eq "^${VNI}[[:space:]]+L2[[:space:]]+vxlan${VNI}"; then
    echo "ERROR: VNI $VNI missing on Leaf2."
    exit 1
fi

# Both leaves must currently have one remote VTEP.
if ! echo "$L1_VNI" |
    grep -Eq "^${VNI}.*[[:space:]]1[[:space:]]+default"; then
    echo "ERROR: Leaf1 does not have expected remote VTEP."
    exit 1
fi

if ! echo "$L2_VNI" |
    grep -Eq "^${VNI}.*[[:space:]]1[[:space:]]+default"; then
    echo "ERROR: Leaf2 does not have expected remote VTEP."
    exit 1
fi

echo "PASS: VNI $VNI operational with remote VTEPs."

# ----------------------------------------------------------
# 4. Subscriber MAC forwarding
# ----------------------------------------------------------

echo
echo "[4/6] Checking subscriber MAC forwarding..."

L1_FDB=$(docker exec "$LEAF1" bridge fdb show br br100)
L2_FDB=$(docker exec "$LEAF2" bridge fdb show br br100)

if ! echo "$L1_FDB" |
    grep -q "$SUB_MAC dev eth3 master br100"; then
    echo "ERROR: subscriber MAC is not local on Leaf1 eth3."
    exit 1
fi

if ! echo "$L2_FDB" |
    grep "$SUB_MAC" |
    grep -q "dev vxlan${VNI} dst ${LEAF1_VTEP}"; then
    echo "ERROR: subscriber MAC is not remote via Leaf1 VTEP."
    exit 1
fi

echo "PASS: subscriber MAC local Leaf1 -> remote Leaf2."

# ----------------------------------------------------------
# 5. BNG MAC forwarding
# ----------------------------------------------------------

echo
echo "[5/6] Checking BNG MAC forwarding..."

if ! echo "$L2_FDB" |
    grep -q "$BNG_MAC dev eth3 master br100"; then
    echo "ERROR: BNG MAC is not local on Leaf2 eth3."
    exit 1
fi

if ! echo "$L1_FDB" |
    grep "$BNG_MAC" |
    grep -q "dev vxlan${VNI} dst ${LEAF2_VTEP}"; then
    echo "ERROR: BNG MAC is not remote via Leaf2 VTEP."
    exit 1
fi

echo "PASS: BNG MAC local Leaf2 -> remote Leaf1."

# ----------------------------------------------------------
# 6. BUM replication
# ----------------------------------------------------------

echo
echo "[6/6] Checking VXLAN BUM replication entries..."

if ! echo "$L1_FDB" |
    grep "00:00:00:00:00:00" |
    grep -q "dst ${LEAF2_VTEP}"; then
    echo "ERROR: Leaf1 BUM replication entry missing."
    exit 1
fi

if ! echo "$L2_FDB" |
    grep "00:00:00:00:00:00" |
    grep -q "dst ${LEAF1_VTEP}"; then
    echo "ERROR: Leaf2 BUM replication entry missing."
    exit 1
fi

echo "PASS: VXLAN BUM replication entries present."

echo
echo "=========================================="
echo " EVPN/VXLAN ACCEPTANCE TEST: PASS"
echo "=========================================="
echo "Leaf1 VTEP   : $LEAF1_VTEP"
echo "Leaf2 VTEP   : $LEAF2_VTEP"
echo "VNI          : $VNI"
echo "Subscriber   : $SUB_MAC"
echo "BNG          : $BNG_MAC"
echo "EVPN peers   : 4 established"
echo "Remote VTEPs : present"
echo "MAC learning : local + remote verified"
echo "BUM          : verified"
echo "=========================================="

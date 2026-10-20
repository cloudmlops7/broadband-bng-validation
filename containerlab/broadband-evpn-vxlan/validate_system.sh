#!/bin/bash
set -euo pipefail

echo "============================================================"
echo " BROADBAND BNG END-TO-END SYSTEM ACCEPTANCE"
echo "============================================================"
echo

START_TIME=$(date +%s)

# ----------------------------------------------------------
# 1. EVPN/VXLAN transport
# ----------------------------------------------------------

echo "############################################################"
echo "# PHASE 1: EVPN/VXLAN TRANSPORT"
echo "############################################################"
echo

if ./validate_evpn.sh; then
    echo
    echo "PHASE 1 RESULT: PASS"
else
    echo
    echo "PHASE 1 RESULT: FAIL"
    exit 1
fi

echo
echo "############################################################"
echo "# PHASE 2: QinQ + PPPoE SUBSCRIBER SERVICE"
echo "############################################################"
echo

# ----------------------------------------------------------
# 2. QinQ / PPPoE / subscriber service
# ----------------------------------------------------------

if ./validate_pppoe.sh; then
    echo
    echo "PHASE 2 RESULT: PASS"
else
    echo
    echo "PHASE 2 RESULT: FAIL"
    exit 1
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo
echo "============================================================"
echo " BROADBAND BNG SYSTEM ACCEPTANCE: PASS"
echo "============================================================"
echo "Access       : QinQ"
echo "S-VLAN       : 900 / 802.1ad"
echo "C-VLAN       : 900 / 802.1Q"
echo "Transport    : EVPN/VXLAN"
echo "VNI          : 10100"
echo "Subscriber   : PPPoE"
echo "AAA          : RADIUS"
echo "Subscriber IP: 10.10.10.10"
echo "BNG IP       : 10.10.10.1"
echo "Packet Loss  : 0%"
echo "Test Duration: ${DURATION}s"
echo "============================================================"

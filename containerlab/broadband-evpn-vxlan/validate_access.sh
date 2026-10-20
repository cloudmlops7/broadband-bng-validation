#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="voltha"
ONU_SN="BBSM000a0001"

EXPECTED_PON="0"
EXPECTED_ONU_ID="1"
EXPECTED_STAG="900"
EXPECTED_CTAG="900"
EXPECTED_GEM="1024"

pass() {
    echo "[PASS] $1"
}

fail() {
    echo "[FAIL] $1"
    exit 1
}

echo "============================================================"
echo " VOLTHA / BBSIM ACCESS ACCEPTANCE"
echo "============================================================"

echo
echo "[1/5] Checking VOLTHA/BBSim Kubernetes components"

for pattern in \
    voltha-rw-core \
    adapter-openolt \
    adapter-openonu \
    bbsim0
do
    kubectl -n "$NAMESPACE" get pods --no-headers \
        | grep "$pattern" \
        | grep -q "Running" \
        || fail "Component $pattern is not Running"

    pass "$pattern is Running"
done

echo
echo "[2/5] Checking VOLTHA OLT state"

OLT_LINE=$(voltctl device list | grep 'BBSIM_OLT_10' || true)

[[ -n "$OLT_LINE" ]] \
    || fail "OLT BBSIM_OLT_10 not found in VOLTHA"

echo "$OLT_LINE" | grep -q 'ENABLED' \
    || fail "OLT is not ENABLED"

echo "$OLT_LINE" | grep -q 'ACTIVE' \
    || fail "OLT is not ACTIVE"

echo "$OLT_LINE" | grep -q 'REACHABLE' \
    || fail "OLT is not REACHABLE"

pass "OLT BBSIM_OLT_10 is ENABLED / ACTIVE / REACHABLE"

echo
echo "[3/5] Checking VOLTHA ONU state"

ONU_LINE=$(voltctl device list | grep "$ONU_SN" || true)

[[ -n "$ONU_LINE" ]] \
    || fail "ONU $ONU_SN not found in VOLTHA"

echo "$ONU_LINE" | grep -q 'ENABLED' \
    || fail "ONU is not ENABLED"

echo "$ONU_LINE" | grep -q 'ACTIVE' \
    || fail "ONU is not ACTIVE"

echo "$ONU_LINE" | grep -q 'REACHABLE' \
    || fail "ONU is not REACHABLE"

echo "$ONU_LINE" | grep -q 'omci-flows-pushed' \
    || fail "ONU OMCI flows have not reached pushed state"

pass "ONU $ONU_SN is ENABLED / ACTIVE / REACHABLE"
pass "ONU service provisioning reached omci-flows-pushed"

echo
echo "[4/5] Checking BBSim OLT/ONU/UNI state"

BBSIM_OLT=$(
    kubectl -n "$NAMESPACE" exec deploy/bbsim0 -- \
        bbsimctl olt get 2>/dev/null
)

echo "$BBSIM_OLT" | grep 'BBSIM_OLT_10' \
    | grep -q 'up.*enabled' \
    || fail "BBSim OLT is not up/enabled"

pass "BBSim OLT 10 is up / enabled"

BBSIM_ONU=$(
    kubectl -n "$NAMESPACE" exec deploy/bbsim0 -- \
        bbsimctl onu get -v "$ONU_SN" 2>/dev/null
)

echo "$BBSIM_ONU" | grep -q \
    "PONPORTID.*ID.*SERIALNUMBER" \
    || fail "Unable to retrieve BBSim ONU detail"

echo "$BBSIM_ONU" | grep "$ONU_SN" \
    | grep -q "^${EXPECTED_PON}[[:space:]]*${EXPECTED_ONU_ID}[[:space:]]" \
    || fail "Expected PON $EXPECTED_PON / ONU $EXPECTED_ONU_ID not found"

echo "$BBSIM_ONU" | grep -q \
    'MeID:257 OperState:"up" PortNo:256' \
    || fail "UNI 0 is not operational"

pass "PON $EXPECTED_PON / ONU $EXPECTED_ONU_ID is present"
pass "UNI 0 is operational (PortNo 256)"

echo
echo "[5/5] Checking HSIA service state"

SERVICES=$(
    kubectl -n "$NAMESPACE" exec deploy/bbsim0 -- \
        bbsimctl onu services "$ONU_SN" 2>/dev/null
)

SERVICE_LINE=$(
    echo "$SERVICES" \
        | awk -v sn="$ONU_SN" '$1 == sn && $2 == 0 {print}'
)

[[ -n "$SERVICE_LINE" ]] \
    || fail "HSIA service for UNI 0 not found"

echo "$SERVICE_LINE" | awk '{exit !($3=="initialized")}' \
    || fail "UNI 0 service is not initialized"

echo "$SERVICE_LINE" | awk -v v="$EXPECTED_STAG" \
    '{exit !($6==v)}' \
    || fail "Expected S-VLAN $EXPECTED_STAG not found"

echo "$SERVICE_LINE" | awk -v v="$EXPECTED_CTAG" \
    '{exit !($9==v)}' \
    || fail "Expected C-VLAN $EXPECTED_CTAG not found"

echo "$SERVICE_LINE" | awk -v v="$EXPECTED_GEM" \
    '{exit !($19==v)}' \
    || fail "Expected GEM Port $EXPECTED_GEM not found"

echo "$SERVICE_LINE" | grep -q 'eap_response_success_received' \
    || fail "EAPOL authentication did not complete successfully"

echo "$SERVICE_LINE" | grep -q 'dhcp_ack_received' \
    || fail "DHCP ACK was not received"

pass "HSIA service initialized"
pass "S-VLAN $EXPECTED_STAG"
pass "C-VLAN $EXPECTED_CTAG"
pass "GEM Port $EXPECTED_GEM"
pass "EAPOL authentication successful"
pass "DHCP ACK received"

echo
echo "============================================================"
echo " VOLTHA / BBSIM ACCESS ACCEPTANCE: PASS"
echo "============================================================"
echo "OLT          : BBSIM_OLT_10"
echo "PON          : $EXPECTED_PON"
echo "ONU          : $EXPECTED_ONU_ID / $ONU_SN"
echo "UNI          : 0 / PortNo 256"
echo "Service      : HSIA"
echo "S-VLAN       : $EXPECTED_STAG"
echo "C-VLAN       : $EXPECTED_CTAG"
echo "GEM Port     : $EXPECTED_GEM"
echo "EAPOL        : SUCCESS"
echo "DHCP         : ACK RECEIVED"
echo "============================================================"

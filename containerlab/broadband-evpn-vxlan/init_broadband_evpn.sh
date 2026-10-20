#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo " Broadband EVPN/VXLAN initialization"
echo "=========================================="

# ----------------------------------------------------------
# 1. Verify EVPN fabric containers
# ----------------------------------------------------------

for C in \
    clab-broadband-evpn-spine1 \
    clab-broadband-evpn-spine2 \
    clab-broadband-evpn-leaf1 \
    clab-broadband-evpn-leaf2
do
    if [ "$(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null || true)" != "true" ]; then
        echo "ERROR: $C is not running."
        echo "Deploy the Containerlab topology first."
        exit 1
    fi
done

echo "EVPN fabric containers are running."

# ----------------------------------------------------------
# 2. Initialize network fabric
# ----------------------------------------------------------

echo
echo "Initializing spines..."
docker exec clab-broadband-evpn-spine1 sh /opt/spine1.sh
docker exec clab-broadband-evpn-spine2 sh /opt/spine2.sh

echo
echo "Initializing leaves..."
docker exec clab-broadband-evpn-leaf1 sh /opt/leaf1.sh
docker exec clab-broadband-evpn-leaf2 sh /opt/leaf2.sh

# ----------------------------------------------------------
# 3. Verify EVPN BGP state
# ----------------------------------------------------------

echo
echo "===== Leaf1 BGP summary ====="
docker exec clab-broadband-evpn-leaf1 \
    vtysh -c 'show bgp summary'

echo
echo "===== Leaf2 BGP summary ====="
docker exec clab-broadband-evpn-leaf2 \
    vtysh -c 'show bgp summary'

# ----------------------------------------------------------
# 4. Attach subscriber and BNG
# ----------------------------------------------------------

echo
echo "Attaching broadband endpoints..."
"$SCRIPT_DIR/attach_broadband_endpoints.sh"

# ----------------------------------------------------------
# 5. Start/verify Accel-PPP
# ----------------------------------------------------------

echo
echo "Starting/verifying BNG..."
"$SCRIPT_DIR/start_bng.sh"

echo
echo "=========================================="
echo " Broadband initialization PASSED"
echo "=========================================="

#!/bin/bash
set -euo pipefail

SUBSCRIBER="subscriber1"
BNG="broadband-bng"
LEAF1="clab-broadband-evpn-leaf1"
LEAF2="clab-broadband-evpn-leaf2"

echo "=========================================="
echo " Broadband endpoint attachment"
echo "=========================================="

# ----------------------------------------------------------
# 1. Verify required containers
# ----------------------------------------------------------

for C in "$SUBSCRIBER" "$BNG" "$LEAF1" "$LEAF2"; do
    if ! docker inspect "$C" >/dev/null 2>&1; then
        echo "ERROR: container $C does not exist"
        exit 1
    fi

    if [ "$(docker inspect -f '{{.State.Running}}' "$C")" != "true" ]; then
        echo "ERROR: container $C is not running"
        exit 1
    fi
done

echo "Required containers are running."

SUB_PID=$(docker inspect -f '{{.State.Pid}}' "$SUBSCRIBER")
BNG_PID=$(docker inspect -f '{{.State.Pid}}' "$BNG")
L1_PID=$(docker inspect -f '{{.State.Pid}}' "$LEAF1")
L2_PID=$(docker inspect -f '{{.State.Pid}}' "$LEAF2")

# ----------------------------------------------------------
# Helper functions
# ----------------------------------------------------------

link_exists() {
    local pid="$1"
    local intf="$2"

    sudo nsenter -t "$pid" -n ip link show "$intf" >/dev/null 2>&1
}

delete_link() {
    local pid="$1"
    local intf="$2"

    if link_exists "$pid" "$intf"; then
        echo "Removing stale interface $intf..."
        sudo nsenter -t "$pid" -n ip link del "$intf" 2>/dev/null || true
    fi
}

attachment_healthy() {
    local endpoint_pid="$1"
    local endpoint_if="$2"
    local leaf_pid="$3"
    local leaf_if="$4"

    # Both interfaces must exist.
    link_exists "$endpoint_pid" "$endpoint_if" || return 1
    link_exists "$leaf_pid" "$leaf_if" || return 1

    local endpoint_line
    local leaf_line
    local endpoint_index
    local endpoint_peer
    local leaf_index
    local leaf_peer

    endpoint_line=$(
        sudo nsenter -t "$endpoint_pid" -n \
            ip -o link show "$endpoint_if" 2>/dev/null
    ) || return 1

    leaf_line=$(
        sudo nsenter -t "$leaf_pid" -n \
            ip -o link show "$leaf_if" 2>/dev/null
    ) || return 1

    # Example:
    # 198: eth1@if197: ...
    # 197: eth3@if198: ...

    endpoint_index=$(echo "$endpoint_line" |
        sed -n 's/^\([0-9]\+\):.*/\1/p')

    endpoint_peer=$(echo "$endpoint_line" |
        sed -n 's/^[0-9]\+: [^@]*@if\([0-9]\+\):.*/\1/p')

    leaf_index=$(echo "$leaf_line" |
        sed -n 's/^\([0-9]\+\):.*/\1/p')

    leaf_peer=$(echo "$leaf_line" |
        sed -n 's/^[0-9]\+: [^@]*@if\([0-9]\+\):.*/\1/p')

    # Never declare healthy if parsing failed.
    [ -n "$endpoint_index" ] || return 1
    [ -n "$endpoint_peer" ] || return 1
    [ -n "$leaf_index" ] || return 1
    [ -n "$leaf_peer" ] || return 1

    # A valid veth pair must point to each other's ifindex.
    [ "$endpoint_peer" = "$leaf_index" ] &&
    [ "$leaf_peer" = "$endpoint_index" ]
}
# ----------------------------------------------------------
# 2. Subscriber -> Leaf1
# ----------------------------------------------------------

ensure_vlan_interface() {
    local pid="$1"
    local parent_if="$2"
    local vlan_if="$3"
    local vlan_id="$4"
    local protocol="$5"
    local mtu="$6"
    local description="$7"

    echo "Checking $description..."

    # Parent interface must exist.
    if ! link_exists "$pid" "$parent_if"; then
        echo "ERROR: parent interface $parent_if does not exist."
        exit 1
    fi

    # If the VLAN interface exists, verify VLAN ID AND protocol.
    if link_exists "$pid" "$vlan_if"; then
        if sudo nsenter -t "$pid" -n \
            ip -d link show "$vlan_if" | \
            grep -q "vlan protocol $protocol id $vlan_id"; then

            echo "$vlan_if already exists: $protocol VLAN $vlan_id."
        else
            echo "WARNING: $vlan_if has incorrect VLAN configuration."
            echo "Recreating $vlan_if..."

            sudo nsenter -t "$pid" -n \
                ip link del "$vlan_if"
        fi
    fi

    # Create VLAN interface when absent.
    if ! link_exists "$pid" "$vlan_if"; then
        echo "Creating $vlan_if on $parent_if:"
        echo "  protocol = $protocol"
        echo "  VLAN ID  = $vlan_id"
        echo "  MTU      = $mtu"

        sudo nsenter -t "$pid" -n \
            ip link add link "$parent_if" \
            name "$vlan_if" \
            type vlan protocol "$protocol" id "$vlan_id"
    fi

    sudo nsenter -t "$pid" -n \
        ip link set "$vlan_if" mtu "$mtu"

    sudo nsenter -t "$pid" -n \
        ip link set "$vlan_if" up

    echo "$description ready."
}
create_attachment() {
    local endpoint_pid="$1"
    local leaf_pid="$2"
    local endpoint_temp="$3"
    local leaf_temp="$4"
    local description="$5"

    echo "Creating $description..."

    # Defensive cleanup of temporary host-side names.
    sudo ip link del "$endpoint_temp" 2>/dev/null || true
    sudo ip link del "$leaf_temp" 2>/dev/null || true

    sudo ip link add "$endpoint_temp" type veth peer name "$leaf_temp"

    sudo ip link set "$endpoint_temp" netns "$endpoint_pid"
    sudo ip link set "$leaf_temp" netns "$leaf_pid"

    sudo nsenter -t "$endpoint_pid" -n \
        ip link set "$endpoint_temp" name eth1

    sudo nsenter -t "$leaf_pid" -n \
        ip link set "$leaf_temp" name eth3

    sudo nsenter -t "$endpoint_pid" -n \
        ip link set eth1 mtu 9000

    sudo nsenter -t "$leaf_pid" -n \
        ip link set eth3 mtu 9000

    sudo nsenter -t "$endpoint_pid" -n \
        ip link set eth1 up

    sudo nsenter -t "$leaf_pid" -n \
        ip link set eth3 up

    sudo nsenter -t "$leaf_pid" -n \
        ip link set eth3 master br100
}

# ----------------------------------------------------------
# 2. Subscriber -> Leaf1
# ----------------------------------------------------------

if attachment_healthy "$SUB_PID" eth1 "$L1_PID" eth3; then
    echo "Subscriber1 <-> Leaf1 attachment is healthy."
else
    echo "Subscriber1 <-> Leaf1 attachment missing or stale."

    delete_link "$SUB_PID" eth1
    delete_link "$L1_PID" eth3

    create_attachment \
        "$SUB_PID" \
        "$L1_PID" \
        sub-veth \
        l1-veth \
        "subscriber1 <-> Leaf1 attachment"
fi

# ----------------------------------------------------------
# 3. BNG -> Leaf2
# ----------------------------------------------------------

if attachment_healthy "$BNG_PID" eth1 "$L2_PID" eth3; then
    echo "BNG <-> Leaf2 attachment is healthy."
else
    echo "BNG <-> Leaf2 attachment missing or stale."

    delete_link "$BNG_PID" eth1
    delete_link "$L2_PID" eth3

    create_attachment \
        "$BNG_PID" \
        "$L2_PID" \
        bng-veth \
        l2-veth \
        "BNG <-> Leaf2 attachment"
fi

# ----------------------------------------------------------
# 4. Create VLAN 900 service interfaces
# ----------------------------------------------------------

# ----------------------------------------------------------
# 4. Create QinQ service interfaces
#
# Physical eth1
#   |
#   +-- eth1.900
#   |     S-Tag 900
#   |     protocol 802.1ad
#   |     MTU 8996
#   |
#   +-- eth1.900.900
#         C-Tag 900
#         protocol 802.1Q
#         MTU 8992
# ----------------------------------------------------------

# Subscriber outer S-tag
ensure_vlan_interface \
    "$SUB_PID" \
    eth1 \
    eth1.900 \
    900 \
    802.1ad \
    8996 \
    "Subscriber S-VLAN 900 interface"

# Subscriber inner C-tag
ensure_vlan_interface \
    "$SUB_PID" \
    eth1.900 \
    eth1.900.900 \
    900 \
    802.1Q \
    8992 \
    "Subscriber C-VLAN 900 interface"

# BNG outer S-tag
ensure_vlan_interface \
    "$BNG_PID" \
    eth1 \
    eth1.900 \
    900 \
    802.1ad \
    8996 \
    "BNG S-VLAN 900 interface"

# BNG inner C-tag
ensure_vlan_interface \
    "$BNG_PID" \
    eth1.900 \
    eth1.900.900 \
    900 \
    802.1Q \
    8992 \
    "BNG C-VLAN 900 interface"
	
# ----------------------------------------------------------
# 5. Verify bridge attachment
# ----------------------------------------------------------

echo
echo "Leaf1 access port:"
sudo nsenter -t "$L1_PID" -n bridge link show dev eth3

echo
echo "Leaf2 access port:"
sudo nsenter -t "$L2_PID" -n bridge link show dev eth3

echo
echo "Subscriber access interface:"
sudo nsenter -t "$SUB_PID" -n ip -br link show eth1

echo
echo "BNG access interface:"
sudo nsenter -t "$BNG_PID" -n ip -br link show eth1

echo
echo "=========================================="
echo " Broadband endpoint attachment PASSED"
echo "=========================================="

echo
echo "Subscriber QinQ interfaces:"
sudo nsenter -t "$SUB_PID" -n ip -d link show eth1.900
sudo nsenter -t "$SUB_PID" -n ip -d link show eth1.900.900

echo
echo "BNG QinQ interfaces:"
sudo nsenter -t "$BNG_PID" -n ip -d link show eth1.900
sudo nsenter -t "$BNG_PID" -n ip -d link show eth1.900.900

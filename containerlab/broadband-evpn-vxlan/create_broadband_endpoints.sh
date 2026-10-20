#!/bin/bash
set -euo pipefail

NETWORK="bng-access"
SUBNET="172.30.0.0/24"

BNG="broadband-bng"
BNG_IMAGE="broadband-accel-ppp:lab"
BNG_IP="172.30.0.2"

SUBSCRIBER="subscriber1"
SUBSCRIBER_IMAGE="broadband-subscriber:lab"
SUBSCRIBER_IP="172.30.0.10"

PROJECT_ROOT="$HOME/projects/broadband-bng-validation"

BNG_CONFIG="$PROJECT_ROOT/bng/accel-ppp/config"
BNG_LOGS="$PROJECT_ROOT/bng/accel-ppp/logs"

echo "=========================================="
echo " Creating broadband endpoint containers"
echo "=========================================="

# ----------------------------------------------------------
# 1. Docker management/backend network
# ----------------------------------------------------------

if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    echo "Network $NETWORK already exists."
else
    echo "Creating $NETWORK ($SUBNET)..."

    docker network create \
        --subnet "$SUBNET" \
        "$NETWORK"
fi

# ----------------------------------------------------------
# 2. BNG container
#
# IMPORTANT:
# Accel-PPP must NOT start here.
# eth1 will be attached first by attach_broadband_endpoints.sh.
# ----------------------------------------------------------

if docker inspect "$BNG" >/dev/null 2>&1; then
    echo "BNG container $BNG already exists."
else
    echo "Creating BNG container..."

    docker run -d \
        --name "$BNG" \
        --network "$NETWORK" \
        --ip "$BNG_IP" \
        --privileged \
        -v "$BNG_CONFIG:/etc/accel-ppp:ro" \
        -v "$BNG_LOGS:/var/log/accel-ppp" \
        --entrypoint /bin/sh \
        "$BNG_IMAGE" \
        -c 'sleep infinity'
fi

# ----------------------------------------------------------
# 3. Subscriber container
# ----------------------------------------------------------

if docker inspect "$SUBSCRIBER" >/dev/null 2>&1; then
    echo "Subscriber container $SUBSCRIBER already exists."
else
    echo "Creating subscriber container..."

    docker run -d \
        --name "$SUBSCRIBER" \
        --network "$NETWORK" \
        --ip "$SUBSCRIBER_IP" \
        --cap-add NET_ADMIN \
        --device /dev/ppp:/dev/ppp \
        "$SUBSCRIBER_IMAGE" \
        sleep infinity
fi

# ----------------------------------------------------------
# 4. Verify management/backend connectivity
# ----------------------------------------------------------

echo
echo "BNG management interface:"
docker exec "$BNG" ip -br addr show eth0

echo
echo "Subscriber management interface:"
docker exec "$SUBSCRIBER" ip -br addr show eth0

echo
echo "=========================================="
echo " Broadband endpoint creation PASSED"
echo "=========================================="

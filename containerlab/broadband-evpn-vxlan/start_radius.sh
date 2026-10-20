#!/bin/bash
set -euo pipefail

RADIUS="radius-debug"
NETWORK="bng-access"
RADIUS_IP="172.30.0.3"

PROJECT_ROOT="$HOME/projects/broadband-bng-validation"
RADIUS_CONFIG="$PROJECT_ROOT/bng/radius/config"

echo "=========================================="
echo " Starting FreeRADIUS"
echo "=========================================="

# Verify Docker network
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    echo "ERROR: Docker network $NETWORK does not exist."
    echo "Run ./create_broadband_endpoints.sh first."
    exit 1
fi

# Reuse existing RADIUS container if running
if docker inspect "$RADIUS" >/dev/null 2>&1; then

    if [ "$(docker inspect -f '{{.State.Running}}' "$RADIUS")" = "true" ]; then
        echo "FreeRADIUS container is already running."
    else
        echo "Starting existing FreeRADIUS container..."
        docker start "$RADIUS" >/dev/null
    fi

else
    echo "Creating FreeRADIUS container..."

    docker run -d \
        --name "$RADIUS" \
        --network "$NETWORK" \
        --ip "$RADIUS_IP" \
        -v "$RADIUS_CONFIG/clients.conf:/etc/freeradius/clients.conf:ro" \
        -v "$RADIUS_CONFIG/authorize:/etc/freeradius/mods-config/files/authorize:ro" \
        freeradius/freeradius-server:latest \
        freeradius -X
fi

echo
echo "Waiting for FreeRADIUS..."

READY=0

for i in $(seq 1 15); do
    if docker logs "$RADIUS" 2>&1 | grep -q "Ready to process requests"; then
        READY=1
        break
    fi

    sleep 1
done

if [ "$READY" -ne 1 ]; then
    echo "ERROR: FreeRADIUS did not become ready."
    docker logs "$RADIUS" 2>&1 | tail -50
    exit 1
fi

echo "FreeRADIUS is ready."

echo
echo "RADIUS container:"
docker inspect "$RADIUS" \
    --format 'IP={{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

echo
echo "=========================================="
echo " RADIUS startup validation PASSED"
echo "=========================================="

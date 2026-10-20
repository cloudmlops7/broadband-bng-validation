FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        isc-dhcp-client \
        iproute2 \
        iputils-ping \
        tcpdump \
        procps && \
    rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]

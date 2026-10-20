FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ppp \
        pppoe \
        iproute2 \
        iputils-ping \
        procps && \
    rm -rf /var/lib/apt/lists/*

COPY broadband /etc/ppp/peers/broadband

CMD ["sleep", "infinity"]

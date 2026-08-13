# CSE644 Assignment 02, Requirement 3 - HAProxy edge component with the proxy
# config baked in, reaching the Nginx app only through its Kubernetes Service.

FROM haproxy:3.0-alpine

ARG BUILD_DATE="unknown"

LABEL org.opencontainers.image.title="cse644-k8s-haproxy" \
      org.opencontainers.image.description="HAProxy edge component reaching the Nginx app via Kubernetes Service discovery (CSE644 Assignment 02)." \
      org.opencontainers.image.authors="Tray Branch" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="haproxy:3.0-alpine" \
      edu.cse644.assignment="02"

COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

# Validate the config at BUILD time (the backend hostname is allowed to be
# unresolvable here thanks to init-addr in haproxy.cfg).
USER root
RUN haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

EXPOSE 80 8404

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD sh -c 'wget -qO- http://127.0.0.1:8404/ >/dev/null 2>&1 || exit 1'

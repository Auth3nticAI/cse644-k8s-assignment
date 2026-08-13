# =============================================================================
# CSE644 Cloud Computing - Assignment 02
# Customized web application (Nginx), built to run as a Kubernetes workload.
#
# Build:
#   docker build -t auth3nticai/cse644-k8s-nginx:v1 apps/nginx-web
# =============================================================================

# Pinned to a specific minor version rather than :latest so the build is
# reproducible and the assignment's "no floating tags" rule is satisfied both
# here and in the Kubernetes manifests that reference this image.
FROM nginx:1.27-alpine

ARG BUILD_DATE="unknown"
ARG STUDENT="Tray Branch"
ARG IMAGE_TAG="auth3nticai/cse644-k8s-nginx:v1"
ARG BASE_IMAGE="nginx:1.27-alpine"

LABEL org.opencontainers.image.title="cse644-k8s-nginx" \
      org.opencontainers.image.description="Nginx customized for CSE644 Assignment 02, run as a Kubernetes Deployment." \
      org.opencontainers.image.authors="Tray Branch" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      edu.cse644.assignment="02"

# 1. Custom server config: adds /healthz and the X-CSE644-Served-By header.
#    The header echoes $hostname, which inside Kubernetes is the Pod name -
#    that is what makes "multiple running instances" visible from curl output.
COPY default.conf /etc/nginx/conf.d/default.conf

# 2. Custom web page, replacing nginx's stock index.html.
COPY site/ /usr/share/nginx/html/

# 3. Bake build metadata into the page in a single layer.
RUN set -eux; \
    sed -i \
      -e "s|__BUILD_DATE__|${BUILD_DATE}|g" \
      -e "s|__STUDENT__|${STUDENT}|g" \
      -e "s|__IMAGE_TAG__|${IMAGE_TAG}|g" \
      -e "s|__BASE_IMAGE__|${BASE_IMAGE}|g" \
      /usr/share/nginx/html/index.html; \
    ! grep -q '__[A-Z_]*__' /usr/share/nginx/html/index.html; \
    nginx -t

EXPOSE 80

# BusyBox wget ships in alpine. Also doubles as the manifest for the
# Kubernetes readiness/liveness probes described in the README.
HEALTHCHECK --interval=10s --timeout=3s --start-period=2s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]

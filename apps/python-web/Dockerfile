# =============================================================================
# CSE644 Cloud Computing - Assignment 02
# Flask web app on port 8888, run as a Kubernetes Deployment with a
# PersistentVolumeClaim mounted at /data, a ConfigMap, and a Secret.
#
# Build:
#   docker build -t auth3nticai/cse644-k8s-python:v1 apps/python-web
# =============================================================================

FROM python:3.12-slim

ARG BUILD_DATE="unknown"
ARG STUDENT="Tray Branch"

LABEL org.opencontainers.image.title="cse644-k8s-python" \
      org.opencontainers.image.description="Flask web app on port 8888 for CSE644 Assignment 02, run as a Kubernetes Deployment." \
      org.opencontainers.image.authors="Tray Branch" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="python:3.12-slim" \
      edu.cse644.assignment="02"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8888 \
    STUDENT="${STUDENT}" \
    DATA_DIR=/data \
    APP_GREETING="Hello from CSE644!" \
    APP_ENVIRONMENT="unset"

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

COPY app.py ./

# /data is where a PersistentVolumeClaim gets mounted in Kubernetes. Creating
# it (and giving appuser ownership) here means the image also runs correctly
# stand-alone with `docker run`, without a volume attached.
RUN useradd --create-home --shell /usr/sbin/nologin appuser \
 && mkdir -p /data \
 && chown -R appuser:appuser /app /data
USER appuser
VOLUME ["/data"]

EXPOSE 8888

# python:3.12-slim ships neither curl nor wget, so the health probe uses the
# stdlib rather than installing an extra package into the image.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8888/healthz', timeout=2).status==200 else 1)"

CMD ["gunicorn", \
     "--bind", "0.0.0.0:8888", \
     "--workers", "2", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]

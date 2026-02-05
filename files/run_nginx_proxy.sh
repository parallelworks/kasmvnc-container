#!/bin/bash

#======================================
#  Nginx Proxy Only Mode
#======================================
#
# Lightweight proxy that connects to an existing KasmVNC instance.
# Use this when KasmVNC is already running on the host or elsewhere.
#
# Environment Variables:
#   KASM_HOST     - Host where KasmVNC is running (default: 127.0.0.1)
#   KASM_PORT     - KasmVNC websocket port (default: 8443)
#   NGINX_PORT    - Port for Nginx to listen on (default: 8080)
#   BASE_PATH     - URL base path for reverse proxy (default: /)
#
# Example:
#   KASM_PORT=8443 BASE_PATH=/desktop/ ./run_nginx_proxy.sh
#

# Fix locale warnings
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Configuration
KASM_HOST="${KASM_HOST:-127.0.0.1}"
KASM_PORT="${KASM_PORT:-8443}"
NGINX_PORT="${NGINX_PORT:-8080}"
BASE_PATH="${BASE_PATH:-/}"

# Ensure base path starts with / and doesn't end with / (unless it's just /)
if [[ "$BASE_PATH" != /* ]]; then
    BASE_PATH="/$BASE_PATH"
fi
if [[ "$BASE_PATH" != "/" && "$BASE_PATH" == */ ]]; then
    BASE_PATH="${BASE_PATH%/}"
fi

echo "==========================================="
echo "  Nginx Proxy Mode (KasmVNC on host)"
echo "==========================================="
echo "[INFO] KasmVNC backend: ${KASM_HOST}:${KASM_PORT}"
echo "[INFO] Nginx port: ${NGINX_PORT}"
echo "[INFO] Base path: ${BASE_PATH}"
echo ""

# Create Nginx temp directories
mkdir -p /tmp/nginx_client_body /tmp/nginx_proxy /tmp/nginx_fastcgi /tmp/nginx_uwsgi /tmp/nginx_scgi

# Generate Nginx config
# Completely standalone - no system includes
cat > /tmp/nginx_proxy.conf << EOF
worker_processes 1;
pid /tmp/nginx.pid;
error_log /tmp/nginx_error.log debug;

events {
    worker_connections 1024;
}

http {
    # Inline mime types - no system includes
    default_type application/octet-stream;
    types {
        text/html html htm;
        text/css css;
        text/javascript js;
        application/javascript js;
        application/json json;
        image/png png;
        image/jpeg jpg jpeg;
        image/gif gif;
        image/svg+xml svg;
    }

    access_log /tmp/nginx_access.log;

    # Temp paths for non-root operation
    client_body_temp_path /tmp/nginx_client_body;
    proxy_temp_path /tmp/nginx_proxy;
    fastcgi_temp_path /tmp/nginx_fastcgi;
    uwsgi_temp_path /tmp/nginx_uwsgi;
    scgi_temp_path /tmp/nginx_scgi;

    # WebSocket support
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        '' close;
    }

    server {
        listen ${NGINX_PORT};
        server_name _;

        # Health check endpoint
        location /health {
            return 200 'Proxy OK - Config loaded';
            add_header Content-Type text/plain;
        }

        # Root proxy to KasmVNC (for assets, websockets, etc.)
        location / {
            proxy_pass https://${KASM_HOST}:${KASM_PORT}/;
            proxy_ssl_verify off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 61s;
            proxy_buffering off;
        }
EOF

# Add redirect for base path without trailing slash
if [ "$BASE_PATH" != "/" ]; then
    cat >> /tmp/nginx_proxy.conf << EOF

        # Redirect exact path to path with trailing slash
        location = ${BASE_PATH} {
            return 301 \$scheme://\$host\$request_uri/;
        }
EOF
fi

# Add the BASE_PATH location block (only if BASE_PATH is not "/")
if [ "$BASE_PATH" != "/" ]; then
    LOCATION_PATH="${BASE_PATH}/"

    cat >> /tmp/nginx_proxy.conf << EOF

        # KasmVNC proxy at BASE_PATH
        location ${LOCATION_PATH} {
            proxy_pass https://${KASM_HOST}:${KASM_PORT}/;

            # SSL backend settings
            proxy_ssl_verify off;

            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;

            # Headers
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            # Timeouts for long-running connections
            proxy_read_timeout 61s;
            proxy_buffering off;
        }
EOF
fi

# Close server and http blocks
cat >> /tmp/nginx_proxy.conf << EOF
    }
}
EOF

echo "[INFO] Generated Nginx config at /tmp/nginx_proxy.conf"

# Test if KasmVNC is reachable (optional check)
if command -v curl &> /dev/null; then
    if curl -sk --connect-timeout 2 "https://${KASM_HOST}:${KASM_PORT}/" > /dev/null 2>&1; then
        echo "[INFO] KasmVNC backend is reachable"
    else
        echo "[WARN] Could not reach KasmVNC at https://${KASM_HOST}:${KASM_PORT}/"
        echo "[WARN] Make sure KasmVNC is running. Continuing anyway..."
    fi
fi

# Kill any existing nginx processes first
echo "[INFO] Killing any existing nginx processes..."
pkill nginx 2>/dev/null || true
killall nginx 2>/dev/null || true
sleep 2

# Verify config was written
echo "[INFO] Config file contents:"
echo "---"
head -30 /tmp/nginx_proxy.conf
echo "---"

# Test nginx config
echo "[INFO] Testing nginx config..."
nginx -t -c /tmp/nginx_proxy.conf 2>&1

# Start Nginx with explicit paths
echo "[INFO] Starting Nginx reverse proxy..."
nginx -c /tmp/nginx_proxy.conf

sleep 1
if pgrep -u $(id -u) nginx > /dev/null; then
    echo "[INFO] Nginx started successfully"
    echo ""
    echo "==========================================="
    echo "  Proxy Ready"
    echo "==========================================="
    echo "Access KasmVNC at: http://localhost:${NGINX_PORT}${BASE_PATH}/"
    echo ""
else
    echo "[ERROR] Failed to start Nginx"
    cat /tmp/nginx_error.log 2>/dev/null
    exit 1
fi

# Keep running and monitor
while true; do
    if ! pgrep -u $(id -u) nginx > /dev/null; then
        echo "[ERROR] Nginx stopped unexpectedly"
        cat /tmp/nginx_error.log 2>/dev/null
        exit 1
    fi
    sleep 10
done

#!/bin/bash

#======================================
#  Exec KasmVNC server with Nginx proxy
#======================================

# Fix locale warnings
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# CRITICAL: Force XDG_RUNTIME_DIR to a writable location for Singularity read-only filesystems
# This MUST be set before VNC server starts so all child processes inherit it
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
echo "[INFO] XDG_RUNTIME_DIR set to $XDG_RUNTIME_DIR"

# Set Kasm port (internal) - the websocket port for the VNC connection
# Accept either KASM_PORT or BASE_PORT (KASM_PORT takes precedence)
KASM_PORT="${KASM_PORT:-${BASE_PORT:-8590}}"
export KASM_PORT

# Find an available display number (or use VNC_DISPLAY if set)
if [ -n "$VNC_DISPLAY" ]; then
    DESKTOP_NUMBER="$VNC_DISPLAY"
else
    # Auto-find available display by checking lock files, sockets, and running processes
    DESKTOP_NUMBER=1
    while [ $DESKTOP_NUMBER -le 99 ]; do
        DISPLAY_IN_USE=0

        # Check lock file
        [ -f "/tmp/.X${DESKTOP_NUMBER}-lock" ] && DISPLAY_IN_USE=1

        # Check X11 socket
        [ -S "/tmp/.X11-unix/X${DESKTOP_NUMBER}" ] && DISPLAY_IN_USE=1

        # Check for running Xvnc process on this display
        pgrep -f "Xvnc.*:${DESKTOP_NUMBER}\b" > /dev/null 2>&1 && DISPLAY_IN_USE=1

        # Check for any X server on this display
        pgrep -f "[X].*:${DESKTOP_NUMBER}\b" > /dev/null 2>&1 && DISPLAY_IN_USE=1

        if [ $DISPLAY_IN_USE -eq 0 ]; then
            break
        fi

        DESKTOP_NUMBER=$((DESKTOP_NUMBER + 1))
    done

    if [ $DESKTOP_NUMBER -gt 99 ]; then
        echo "[ERROR] Could not find available display (tried :1 to :99)"
        exit 1
    fi
fi

# Set Nginx port (external)
export NGINX_PORT="${NGINX_PORT:-8080}"

# Set base path (default: /)
export BASE_PATH="${BASE_PATH:-/}"

# Set VNC resolution (default: 1920x1080)
export VNC_RESOLUTION="${VNC_RESOLUTION:-1920x1080}"

# Ensure base path starts with / and doesn't end with / (unless it's just /)
if [[ "$BASE_PATH" != /* ]]; then
    BASE_PATH="/$BASE_PATH"
fi
if [[ "$BASE_PATH" != "/" && "$BASE_PATH" == */ ]]; then
    BASE_PATH="${BASE_PATH%/}"
fi

echo "[INFO] Kasm VNC port: $KASM_PORT (internal websocket)"
echo "[INFO] VNC display: :$DESKTOP_NUMBER"
echo "[INFO] Nginx port: $NGINX_PORT (external)"
echo "[INFO] Base path: $BASE_PATH"
echo "[INFO] VNC resolution: $VNC_RESOLUTION"

# Aggressive cleanup of ALL stale VNC sessions for this user
echo "[INFO] Cleaning up stale VNC sessions and config files..."

# Kill all existing vncserver processes for this user
pkill -u $(id -u) -f "Xvnc" 2>/dev/null || true
pkill -u $(id -u) -f "vncserver" 2>/dev/null || true

# Clean up all VNC lock files we might own
rm -f /tmp/.X*-lock 2>/dev/null || true
rm -f /tmp/.X11-unix/X* 2>/dev/null || true
rm -f "$HOME/.vnc"/*.pid 2>/dev/null || true
rm -f "$HOME/.vnc"/*.log 2>/dev/null || true

# Clean up old VNC config files that might conflict with our setup
# These will be regenerated fresh each time to ensure consistent behavior
rm -f "$HOME/.vnc/kasmvnc.yaml" 2>/dev/null || true
rm -f "$HOME/.vnc/xstartup" 2>/dev/null || true
rm -f "$HOME/.vnc/xstartup.turbovnc" 2>/dev/null || true
rm -f "$HOME/.vnc/kasm-xstartup" 2>/dev/null || true
rm -f "$HOME/.vnc/passwd" 2>/dev/null || true
rm -f "$HOME/.kasmpasswd" 2>/dev/null || true
rm -rf "$HOME/.vnc/ssl" 2>/dev/null || true

# Also try the vncserver -kill command for our display
vncserver -kill :${DESKTOP_NUMBER} 2>/dev/null || true

# Give processes time to die
sleep 1

# Ensure .vnc directory exists (fresh)
mkdir -p "$HOME/.vnc"

# Get the external hostname for WebSocket connection
# Can be set via KASM_HOST env var, otherwise try to detect
if [ -z "$KASM_HOST" ]; then
    KASM_HOST=$(hostname -f 2>/dev/null || hostname)
fi

# Build the full WebSocket host path (e.g., activate.parallel.works/me/session/user/kasmpath/)
# Ensure base path ends with /
WEBSOCKET_PATH="${BASE_PATH}"
if [[ "$WEBSOCKET_PATH" != */ ]]; then
    WEBSOCKET_PATH="${WEBSOCKET_PATH}/"
fi
KASM_WEBSOCKET_HOST="${KASM_HOST}${WEBSOCKET_PATH}"

echo "[INFO] WebSocket host: $KASM_WEBSOCKET_HOST"

# Generate self-signed SSL cert (KasmVNC requires cert files even when SSL is disabled on some systems)
SSL_DIR="$HOME/.vnc/ssl"
mkdir -p "$SSL_DIR"
SSL_AVAILABLE="false"
if [ ! -f "$SSL_DIR/self.pem" ]; then
    if command -v openssl &> /dev/null; then
        # Try multiple methods - some systems have FIPS restrictions
        # Method 1: Standard RSA (works on most systems)
        if openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$SSL_DIR/self.pem" -out "$SSL_DIR/self.pem" \
            -subj "/C=US/ST=State/L=City/O=Org/CN=localhost" 2>/dev/null; then
            echo "[INFO] Generated self-signed SSL certificate (RSA)"
            SSL_AVAILABLE="true"
        # Method 2: EC keys (FIPS-compatible on some systems)
        elif openssl req -x509 -nodes -days 365 -newkey ec \
            -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout "$SSL_DIR/self.pem" -out "$SSL_DIR/self.pem" \
            -subj "/C=US/ST=State/L=City/O=Org/CN=localhost" 2>/dev/null; then
            echo "[INFO] Generated self-signed SSL certificate (EC)"
            SSL_AVAILABLE="true"
        # Method 3: Try with explicit default provider (bypass FIPS)
        elif openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -provider default \
            -keyout "$SSL_DIR/self.pem" -out "$SSL_DIR/self.pem" \
            -subj "/C=US/ST=State/L=City/O=Org/CN=localhost" 2>/dev/null; then
            echo "[INFO] Generated self-signed SSL certificate (default provider)"
            SSL_AVAILABLE="true"
        else
            echo "[WARN] Failed to generate SSL certificate (all methods failed)"
            echo "[WARN] This may be due to FIPS restrictions on the host system"
        fi
    else
        echo "[WARN] openssl not found, skipping SSL certificate generation"
    fi
else
    echo "[INFO] Using existing SSL certificate"
    SSL_AVAILABLE="true"
fi

# Verify the certificate file actually exists and is readable
if [ "$SSL_AVAILABLE" = "true" ] && [ ! -f "$SSL_DIR/self.pem" ]; then
    echo "[WARN] SSL certificate file not found after generation"
    SSL_AVAILABLE="false"
fi

# Generate kasmvnc.yaml for reverse proxy mode
# Only include SSL config if certificate is available
if [ "$SSL_AVAILABLE" = "true" ]; then
    cat > "$HOME/.vnc/kasmvnc.yaml" << EOF
network:
  interface: 127.0.0.1
  ssl:
    require_ssl: false
    pem_certificate: $SSL_DIR/self.pem
    pem_key: $SSL_DIR/self.pem
  udp:
    public_ip: 127.0.0.1
${KASMVNC_YAML_EXTRA}
EOF
else
    cat > "$HOME/.vnc/kasmvnc.yaml" << EOF
network:
  interface: 127.0.0.1
  ssl:
    require_ssl: false
  udp:
    public_ip: 127.0.0.1
${KASMVNC_YAML_EXTRA}
EOF
fi
echo "[INFO] Generated kasmvnc.yaml for reverse proxy mode (SSL: $SSL_AVAILABLE)"

# Generate xstartup for XFCE desktop
cat > "$HOME/.vnc/xstartup" << 'EOF'
#!/bin/bash
# KasmVNC xstartup - XFCE Desktop

# CRITICAL: Force XDG_RUNTIME_DIR to writable location (Singularity read-only fix)
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Force shell to bash (Apptainer sets a weird default shell)
export SHELL=/bin/bash

# Force X11 backends (not Wayland)
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export MOZ_ENABLE_WAYLAND=0

# Software rendering fallback (for compatibility)
export LIBGL_ALWAYS_SOFTWARE=1

# Desktop environment variables
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
export XDG_CONFIG_DIRS=/etc/xdg
export XDG_DATA_DIRS=/usr/share:/usr/local/share

# Kill any stale XFCE processes
killall -q xfce4-session xfwm4 xfce4-panel xfdesktop thunar 2>/dev/null || true

# Fix for LDAP/NIS users not in /etc/passwd - create temp passwd entry
if ! getent passwd $(id -u) > /dev/null 2>&1; then
    echo "[INFO] User not in passwd database, creating temporary entry for dbus"
    NSS_WRAPPER_DIR="/tmp/nss_wrapper_$(id -u)"
    mkdir -p "$NSS_WRAPPER_DIR"
    echo "$(id -un):x:$(id -u):$(id -g):$(id -un):$HOME:/bin/bash" > "$NSS_WRAPPER_DIR/passwd"
    grep "^root:" /etc/passwd >> "$NSS_WRAPPER_DIR/passwd" 2>/dev/null || echo "root:x:0:0:root:/root:/bin/bash" >> "$NSS_WRAPPER_DIR/passwd"
    echo "$(id -gn):x:$(id -g):" > "$NSS_WRAPPER_DIR/group"
    grep "^root:" /etc/group >> "$NSS_WRAPPER_DIR/group" 2>/dev/null || echo "root:x:0:" >> "$NSS_WRAPPER_DIR/group"
    export NSS_WRAPPER_PASSWD="$NSS_WRAPPER_DIR/passwd"
    export NSS_WRAPPER_GROUP="$NSS_WRAPPER_DIR/group"
    for wrapper_path in /usr/lib/x86_64-linux-gnu/libnss_wrapper.so /usr/lib/libnss_wrapper.so /usr/lib64/libnss_wrapper.so; do
        if [ -f "$wrapper_path" ]; then
            export LD_PRELOAD="$wrapper_path"
            break
        fi
    done
fi

# Start XFCE with dbus-run-session wrapper and apply theme settings
exec dbus-run-session -- bash -c '
# Set Adwaita-dark theme (runs after XFCE starts to ensure xfconf is available)
(
    sleep 3
    xfconf-query -c xsettings -p /Net/ThemeName -s "Adwaita-dark" 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/IconThemeName -s "Adwaita" 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/theme -s "Adwaita-dark" 2>/dev/null || true

    # Set dark teal solid background color (RGB: 27, 42, 53 = #1b2a35)
    # Find the actual monitor name from xfconf (VNC creates dynamic names like "screen")
    MONITOR=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -oP "monitor[^/]+" | head -1)
    if [ -z "$MONITOR" ]; then
        MONITOR="monitorscreen"
    fi
    BACKDROP_PATH="/backdrop/screen0/${MONITOR}/workspace0"

    # Set solid color mode (color-style=0) and no image (image-style=0)
    xfconf-query -c xfce4-desktop -p "${BACKDROP_PATH}/color-style" -n -t int -s 0 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p "${BACKDROP_PATH}/image-style" -n -t int -s 0 2>/dev/null || true
    # Clear any existing image path
    xfconf-query -c xfce4-desktop -p "${BACKDROP_PATH}/last-image" -r 2>/dev/null || true
    # Set the solid color (dark teal)
    xfconf-query -c xfce4-desktop -p "${BACKDROP_PATH}/rgba1" -n -t double -t double -t double -t double -s 0.105882 -s 0.164706 -s 0.207843 -s 1.0 2>/dev/null || true
) &
startxfce4
'
EOF
chmod +x "$HOME/.vnc/xstartup"
echo "[INFO] Generated xstartup for XFCE desktop"

# Create marker file to skip KasmVNC's DE selection menu
touch "$HOME/.vnc/.de-was-selected"

# We must set a password even if KASM does not use it for user auth.
# Use hashlib instead of deprecated crypt module for Python 3.13+ compatibility
VNC_PW='placeholder'
PASSWD_PATH="$HOME/.kasmpasswd"
VNC_PW_HASH=$(python3 -c "
import hashlib
import base64
pw = '${VNC_PW}'
salt = b'kasm'
hash_bytes = hashlib.pbkdf2_hmac('sha256', pw.encode(), salt, 5000)
print('\$5\$kasm\$' + base64.b64encode(hash_bytes).decode()[:43])
" 2>/dev/null || python3 -c "import crypt; print(crypt.crypt('${VNC_PW}', '\$5\$kasm\$'));")
echo "kasm_user:${VNC_PW_HASH}:ow" > $PASSWD_PATH
chmod 600 $PASSWD_PATH

# This is used inside our custom KASM build to allow a random socket to support Singularity
if [ "x$KASMSOCK" == "xTrue" ]; then
    export SOCKET_PORT=$(( $RANDOM % 50 + 1 ))
fi

# Create Nginx temp directories
mkdir -p /tmp/nginx_client_body /tmp/nginx_proxy /tmp/nginx_fastcgi /tmp/nginx_uwsgi /tmp/nginx_scgi

# Generate Nginx config from template with environment variable substitution
envsubst '${BASE_PATH} ${KASM_PORT} ${NGINX_PORT}' < /etc/nginx/nginx.conf.template > /tmp/nginx.conf

# Add redirect from BASE_PATH (no trailing slash) to BASE_PATH/ (with slash)
# This allows URLs like /me/session/user/kasmpath to work without requiring trailing slash
if [ "$BASE_PATH" != "/" ]; then
    sed -i "/location ${BASE_PATH//\//\\/} {/i\\
        # Redirect exact path to path with trailing slash\\
        location = ${BASE_PATH} {\\
            return 301 \$scheme://\$host\$request_uri/;\\
        }\\
" /tmp/nginx.conf
    echo "[INFO] Added redirect for ${BASE_PATH} -> ${BASE_PATH}/"
fi

# Start Kasm VNC (explicitly using our custom xstartup for Cinnamon)
echo "[INFO] Starting Kasm VNC server on display :${DESKTOP_NUMBER}..."

# Build vncserver command - add SSL flags based on availability
VNC_CMD="/usr/bin/vncserver :$DESKTOP_NUMBER \
    -xstartup $HOME/.vnc/xstartup \
    -depth 24 \
    -geometry $VNC_RESOLUTION \
    -websocketPort $KASM_PORT \
    -httpd /usr/share/kasmvnc/www \
    -disableBasicAuth \
    -FrameRate=24 \
    -interface 127.0.0.1"

# If SSL is not available, explicitly disable it
if [ "$SSL_AVAILABLE" != "true" ]; then
    echo "[INFO] SSL not available, starting VNC without SSL"
    VNC_CMD="$VNC_CMD -sslOnly 0"
fi

eval $VNC_CMD

# Check if VNC started successfully
sleep 2
if ! pgrep -f "Xvnc.*:${DESKTOP_NUMBER}" > /dev/null; then
    echo "[ERROR] Failed to start Kasm VNC server"
    cat "$HOME/.vnc"/*.log 2>/dev/null
    exit 1
fi
echo "[INFO] Kasm VNC server started successfully"

# Start Nginx
echo "[INFO] Starting Nginx reverse proxy on port ${NGINX_PORT}..."
nginx -c /tmp/nginx.conf &
NGINX_PID=$!

sleep 1
if ! kill -0 $NGINX_PID 2>/dev/null; then
    echo "[ERROR] Failed to start Nginx"
    exit 1
fi
echo "[INFO] Nginx started successfully (PID: $NGINX_PID)"

echo "[INFO] Services ready. Access via port $NGINX_PORT at path $BASE_PATH"

# Check if both services are running
while true
do
    if ! pgrep -f "Xvnc.*:${DESKTOP_NUMBER}" > /dev/null; then
        echo "[ERROR] Kasm VNC server stopped unexpectedly"
        kill $NGINX_PID 2>/dev/null
        exit 1
    fi

    if ! kill -0 $NGINX_PID 2>/dev/null; then
        echo "[ERROR] Nginx stopped unexpectedly"
        exit 1
    fi

    # Sleep 10 secs before re-checking
    sleep 10
done

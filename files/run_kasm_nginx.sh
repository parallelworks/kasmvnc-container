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

# Use a fixed display number to avoid conflicts
# Display number is independent of the websocket port
DESKTOP_NUMBER="${VNC_DISPLAY:-1}"

# Set Nginx port (external)
export NGINX_PORT="${NGINX_PORT:-8080}"

# Set base path (default: /)
export BASE_PATH="${BASE_PATH:-/}"

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

# Aggressive cleanup of ALL stale VNC sessions for this user
echo "[INFO] Cleaning up stale VNC sessions..."

# Kill all existing vncserver processes for this user
pkill -u $(id -u) -f "Xvnc" 2>/dev/null || true
pkill -u $(id -u) -f "vncserver" 2>/dev/null || true

# Clean up all VNC lock files we might own
rm -f /tmp/.X*-lock 2>/dev/null || true
rm -f /tmp/.X11-unix/X* 2>/dev/null || true
rm -f "$HOME/.vnc"/*.pid 2>/dev/null || true
rm -f "$HOME/.vnc"/*.log 2>/dev/null || true

# Also try the vncserver -kill command for our display
vncserver -kill :${DESKTOP_NUMBER} 2>/dev/null || true

# Give processes time to die
sleep 1

# Ensure .vnc directory exists
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

# Generate kasmvnc.yaml for reverse proxy mode
cat > "$HOME/.vnc/kasmvnc.yaml" << EOF
network:
  interface: 127.0.0.1
  ssl:
    require_ssl: false
  udp:
    public_ip: 127.0.0.1
${KASMVNC_YAML_EXTRA}
EOF
echo "[INFO] Generated kasmvnc.yaml for reverse proxy mode"

# Generate xstartup for Cinnamon desktop
cat > "$HOME/.vnc/xstartup" << 'EOF'
#!/bin/bash
# KasmVNC xstartup - Cinnamon Desktop

# CRITICAL: Force XDG_RUNTIME_DIR to writable location (Singularity read-only fix)
# Do NOT use conditional ${VAR:-default} - forcibly override any existing value
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Also set ICEAUTHORITY to writable location (cinnamon-session requirement)
export ICEAUTHORITY="$XDG_RUNTIME_DIR/ICEauthority"

# Force shell to bash (Apptainer sets a weird default shell)
export SHELL=/bin/bash

# Force X11 backends (not Wayland)
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export CLUTTER_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export MOZ_ENABLE_WAYLAND=0

# Software rendering fallback (for compatibility)
export LIBGL_ALWAYS_SOFTWARE=1

# Desktop environment variables
export XDG_CURRENT_DESKTOP=X-Cinnamon
export DESKTOP_SESSION=cinnamon
export XDG_CONFIG_DIRS=/etc/xdg
export XDG_DATA_DIRS=/usr/share:/usr/local/share

# Kill any stale Cinnamon processes
killall -q cinnamon cinnamon-session cinnamon-panel muffin nemo nemo-desktop 2>/dev/null || true

# Start Cinnamon with dbus-run-session wrapper
# Use bash -c to set theme defaults before starting cinnamon-session
exec dbus-run-session -- bash -c '
# Set default theme and background (Adapta-Nokto dark theme)
gsettings set org.cinnamon.theme name "Adapta-Nokto" 2>/dev/null || true
gsettings set org.cinnamon.desktop.interface gtk-theme "Adapta-Nokto" 2>/dev/null || true
gsettings set org.cinnamon.desktop.wm.preferences theme "Adapta-Nokto" 2>/dev/null || true
gsettings set org.cinnamon.desktop.interface icon-theme "Adwaita" 2>/dev/null || true
gsettings set org.cinnamon.desktop.background picture-uri "file:///usr/share/backgrounds/tealized.jpg" 2>/dev/null || true
gsettings set org.cinnamon.desktop.background picture-options "zoom" 2>/dev/null || true

# Pin Firefox and Terminal to panel (add panel-launchers applet)
gsettings set org.cinnamon favorite-apps "[\x27firefox.desktop\x27, \x27org.gnome.Terminal.desktop\x27, \x27nemo.desktop\x27]" 2>/dev/null || true
gsettings set org.cinnamon enabled-applets "[\x27panel1:left:0:menu@cinnamon.org:0\x27, \x27panel1:left:1:panel-launchers@cinnamon.org:1\x27, \x27panel1:left:2:separator@cinnamon.org:2\x27, \x27panel1:left:3:grouped-window-list@cinnamon.org:3\x27, \x27panel1:right:0:systray@cinnamon.org:4\x27, \x27panel1:right:1:xapp-status@cinnamon.org:5\x27, \x27panel1:right:2:notifications@cinnamon.org:6\x27, \x27panel1:right:3:removable-drives@cinnamon.org:7\x27, \x27panel1:right:4:network@cinnamon.org:8\x27, \x27panel1:right:5:sound@cinnamon.org:9\x27, \x27panel1:right:6:power@cinnamon.org:10\x27, \x27panel1:right:7:calendar@cinnamon.org:11\x27]" 2>/dev/null || true
# Start Cinnamon
exec cinnamon-session
'
EOF
chmod +x "$HOME/.vnc/xstartup"
echo "[INFO] Generated xstartup for Cinnamon desktop"

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
/usr/bin/vncserver :$DESKTOP_NUMBER \
    -xstartup "$HOME/.vnc/xstartup" \
    -depth 24 \
    -geometry 1280x1050 \
    -websocketPort $KASM_PORT \
    -httpd /usr/share/kasmvnc/www \
    -disableBasicAuth \
    -FrameRate=24 \
    -interface 127.0.0.1

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

#!/bin/bash

#========================
#  Exec KasmVNC server
#========================

# Fix locale warnings
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# CRITICAL: Force XDG_RUNTIME_DIR to a writable location for Singularity read-only filesystems
# This MUST be set before VNC server starts so all child processes inherit it
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
echo "[INFO] XDG_RUNTIME_DIR set to $XDG_RUNTIME_DIR"

# Set websocket port (independent of display number)
# Accept either KASM_PORT or BASE_PORT (KASM_PORT takes precedence)
BASE_PORT="${KASM_PORT:-${BASE_PORT:-8590}}"

# Use a fixed display number to avoid conflicts
DESKTOP_NUMBER="${VNC_DISPLAY:-1}"

echo "[INFO] Kasm VNC port: $BASE_PORT (websocket)"
echo "[INFO] VNC display: :$DESKTOP_NUMBER"

# Clean up only our display to allow concurrent sessions
echo "[INFO] Cleaning up VNC display :${DESKTOP_NUMBER}..."

# Kill only the VNC process on our display
pkill -u $(id -u) -f "Xvnc.*:${DESKTOP_NUMBER}( |$)" 2>/dev/null || true
vncserver -kill :${DESKTOP_NUMBER} 2>/dev/null || true

# Clean up only our display's lock files
rm -f "/tmp/.X${DESKTOP_NUMBER}-lock" 2>/dev/null || true
rm -f "/tmp/.X11-unix/X${DESKTOP_NUMBER}" 2>/dev/null || true

# Give processes time to die
sleep 1

# We must set a password even if KASM does not use it for user auth.
# Use hashlib instead of deprecated crypt module for Python 3.13+ compatibility
VNC_PW='placeholder'
mkdir -p "$HOME/.vnc"
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

# Generate xstartup for Cinnamon desktop (with Singularity compatibility)
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
exec dbus-run-session -- cinnamon-session
EOF
chmod +x "$HOME/.vnc/xstartup"
echo "[INFO] Generated xstartup for Cinnamon desktop"

# Start Kasm VNC (explicitly using our custom xstartup)
echo "[INFO] Starting Kasm VNC server..."
/usr/bin/vncserver :$DESKTOP_NUMBER \
    -xstartup "$HOME/.vnc/xstartup" \
    -depth 24 \
    -geometry 1280x1050 \
    -websocketPort $BASE_PORT \
    -httpd /usr/share/kasmvnc/www \
    -disableBasicAuth \
    -FrameRate=24 \
    -interface 0.0.0.0

# Check if VNC started successfully
sleep 2
if ! pgrep -f "Xvnc.*:${DESKTOP_NUMBER}" > /dev/null; then
    echo "[ERROR] Failed to start Kasm VNC server"
    cat "$HOME/.vnc"/*.log 2>/dev/null
    exit 1
fi
echo "[INFO] Kasm VNC server started successfully on port $BASE_PORT"

# Check if the VNC server is running. If not, exit.
while true
do
    if ! pgrep -f "Xvnc.*:${DESKTOP_NUMBER}" > /dev/null; then
        echo "[ERROR] Kasm VNC server stopped unexpectedly"
        exit 1
    fi

    # Sleep 10 secs before re-checking
    sleep 10
done

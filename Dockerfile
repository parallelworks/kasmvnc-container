FROM ubuntu:24.04
LABEL maintainer="Parallel Works <support@parallelworks.com>"

#----------------------
# Base System Setup
#----------------------

# Set non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# Update and install base utilities
RUN apt-get update && apt-get install -y \
    sudo nano emacs vim screen telnet iputils-ping curl wget unzip git-core \
    python3-pip python3-venv \
    libnss-wrapper \
    csh tcsh ksh \
    gdb \
    && apt-get clean

#------------------------
# HPC/CAE Software Dependencies
#------------------------

# Enable 32-bit architecture for legacy libraries
RUN dpkg --add-architecture i386 && apt-get update

# Install HPC/CAE dependencies (for ANSYS, STAR-CCM+, etc.)
RUN apt-get install -y \
    libelf1 libelf-dev \
    libglapi-mesa libglapi-mesa:i386 \
    libglu1-mesa libglu1-mesa:i386 \
    libjpeg8:i386 libjpeg-turbo8:i386 \
    libpng16-16:i386 \
    libexpat1:i386 \
    libc6:i386 libc6-dev:i386 \
    libxp6:i386 2>/dev/null || true \
    && apt-get clean

# pstack: Create pstack using gdb (gstack doesn't exist on Ubuntu)
RUN printf '#!/bin/bash\ngdb -batch -ex "thread apply all bt" -p "$1" 2>/dev/null\n' > /usr/bin/pstack && \
    chmod +x /usr/bin/pstack

# Create symlinks for legacy library compatibility
# libpng12 -> libpng16 (most apps work with this)
RUN ln -sf /usr/lib/x86_64-linux-gnu/libpng16.so.16 /usr/lib/x86_64-linux-gnu/libpng12.so.0 2>/dev/null || true && \
    ln -sf /usr/lib/i386-linux-gnu/libpng16.so.16 /usr/lib/i386-linux-gnu/libpng12.so.0 2>/dev/null || true

# Change APT user to allow some container runtimes properly work (i.e. Podman)
RUN groupadd -g 600 _apt && usermod -g 600 _apt

#------------------------
# "Meta" user
#------------------------

# Remove default ubuntu user if it exists (Ubuntu 24.04 creates one with UID/GID 1000)
# Keep this for forward compatibility even on 22.04
RUN userdel -r ubuntu 2>/dev/null || true && groupdel ubuntu 2>/dev/null || true

# Add group and user with UID/GID 1000
RUN groupadd -g 1000 metauser || groupmod -n metauser $(getent group 1000 | cut -d: -f1)
RUN useradd metauser -d /home/metauser -u 1000 -g 1000 -m -s /bin/bash

# Add metauser to sudoers with no password
RUN adduser metauser sudo
COPY files/sudoers /etc/sudoers

# Prepare for user-space logs
RUN mkdir /home/metauser/.logs && chown metauser:metauser /home/metauser/.logs

#------------------------
# Kasm VNC 1.4.0 + XFCE Desktop
#------------------------

# Install X11, VNC dependencies, and XFCE desktop
# XFCE is lightweight and works without system D-Bus (ideal for containers)
RUN apt-get update && apt-get install -y \
    xvfb \
    xterm \
    net-tools \
    python3 \
    libdatetime-perl \
    dbus-x11 \
    at-spi2-core \
    xfce4 \
    xfce4-terminal \
    xfce4-whiskermenu-plugin \
    xfce4-pulseaudio-plugin \
    xfce4-screenshooter \
    xfce4-taskmanager \
    thunar \
    thunar-archive-plugin \
    mousepad \
    ristretto \
    adwaita-icon-theme \
    gnome-themes-extra \
    arc-theme \
    papirus-icon-theme \
    xdg-utils \
    evince \
    file-roller \
    htop \
    openssh-client \
    software-properties-common \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Firefox from Mozilla PPA (not snap - snaps don't work in containers)
RUN add-apt-repository -y ppa:mozillateam/ppa && \
    echo 'Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001' > /etc/apt/preferences.d/mozilla-firefox && \
    apt-get update && apt-get install -y firefox && \
    rm -rf /var/lib/apt/lists/*

# Disable autostart items that don't work in containers (no system D-Bus)
RUN rm -f /etc/xdg/autostart/blueman.desktop \
          /etc/xdg/autostart/print-applet.desktop \
          /etc/xdg/autostart/system-config-printer-applet.desktop \
          /etc/xdg/autostart/gnome-keyring-pkcs11.desktop \
          /etc/xdg/autostart/gnome-keyring-secrets.desktop \
          /etc/xdg/autostart/gnome-keyring-ssh.desktop \
          /etc/xdg/autostart/xfce4-screensaver.desktop \
          /etc/xdg/autostart/xscreensaver.desktop \
    2>/dev/null || true

# Copy custom background
COPY files/backgrounds/tealized.jpg /usr/share/backgrounds/tealized.jpg

# Download and install KasmVNC 1.4.0 for Ubuntu 24.04 (noble)
RUN cd /tmp && \
    wget https://github.com/kasmtech/KasmVNC/releases/download/v1.4.0/kasmvncserver_noble_1.4.0_amd64.deb && \
    apt-get update && apt-get install -y ./kasmvncserver_noble_1.4.0_amd64.deb && \
    rm kasmvncserver_noble_1.4.0_amd64.deb && \
    rm -rf /var/lib/apt/lists/*

#------------------------
# Nginx Reverse Proxy
#------------------------

# Install Nginx and gettext (for envsubst)
RUN apt-get update && apt-get install -y nginx gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Copy Nginx config template
COPY files/nginx.conf /etc/nginx/nginx.conf.template

#------------------------
# Startup Scripts
#------------------------

# Copy startup scripts
COPY files/run_kasm.sh /usr/local/bin/run_kasm.sh
COPY files/run_kasm_nginx.sh /usr/local/bin/run_kasm_nginx.sh
COPY files/run_nginx_proxy.sh /usr/local/bin/run_nginx_proxy.sh
RUN chmod 755 /usr/local/bin/run_kasm.sh /usr/local/bin/run_kasm_nginx.sh /usr/local/bin/run_nginx_proxy.sh

# Entrypoint script (UID-aware for Singularity)
COPY files/base_entrypoint.sh /usr/bin/base_entrypoint.sh
RUN chmod 755 /usr/bin/base_entrypoint.sh
ENTRYPOINT ["/usr/bin/base_entrypoint.sh"]

# Source container environment for all shell types
# Override Apptainer's PS1 and SHELL for both login and non-login shells
RUN echo '[ -f /tmp/env.sh ] && . /tmp/env.sh' > /etc/profile.d/container-env.sh && \
    echo 'export SHELL=/bin/bash' >> /etc/profile.d/container-env.sh && \
    echo 'PS1='"'"'\u@\h:\w\$ '"'" >> /etc/profile.d/container-env.sh && \
    chmod 644 /etc/profile.d/container-env.sh && \
    echo '[ -f /tmp/env.sh ] && . /tmp/env.sh' >> /etc/bash.bashrc && \
    echo 'export SHELL=/bin/bash' >> /etc/bash.bashrc && \
    echo 'PS1='"'"'\u@\h:\w\$ '"'" >> /etc/bash.bashrc && \
    echo 'SHELL=/bin/bash' >> /etc/environment

#------------------------
# User Home Setup
#------------------------

# Rename metauser home as "vanilla" template
RUN mv /home/metauser /metauser_home_vanilla

# VNC configuration directory
RUN mkdir -p /metauser_home_vanilla/.vnc
COPY files/xstartup /metauser_home_vanilla/.vnc/xstartup
COPY files/kasmvnc.yaml /metauser_home_vanilla/.vnc/kasmvnc.yaml
RUN chmod 755 /metauser_home_vanilla/.vnc/xstartup

# Configure XFCE settings via xfconf XML files
# Set dark theme (Arc-Dark), Papirus icons, and background
RUN mkdir -p /metauser_home_vanilla/.config/xfce4/xfconf/xfce-perchannel-xml && \
    echo '<?xml version="1.0" encoding="UTF-8"?>\n\
<channel name="xsettings" version="1.0">\n\
  <property name="Net" type="empty">\n\
    <property name="ThemeName" type="string" value="Arc-Dark"/>\n\
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>\n\
  </property>\n\
  <property name="Gtk" type="empty">\n\
    <property name="FontName" type="string" value="Sans 10"/>\n\
  </property>\n\
</channel>' > /metauser_home_vanilla/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml && \
    echo '<?xml version="1.0" encoding="UTF-8"?>\n\
<channel name="xfwm4" version="1.0">\n\
  <property name="general" type="empty">\n\
    <property name="theme" type="string" value="Arc-Dark"/>\n\
  </property>\n\
</channel>' > /metauser_home_vanilla/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml && \
    echo '<?xml version="1.0" encoding="UTF-8"?>\n\
<channel name="xfce4-desktop" version="1.0">\n\
  <property name="backdrop" type="empty">\n\
    <property name="screen0" type="empty">\n\
      <property name="monitorscreen" type="empty">\n\
        <property name="workspace0" type="empty">\n\
          <property name="last-image" type="string" value="/usr/share/backgrounds/tealized.jpg"/>\n\
          <property name="image-style" type="int" value="5"/>\n\
        </property>\n\
      </property>\n\
    </property>\n\
  </property>\n\
</channel>' > /metauser_home_vanilla/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml && \
    chown -R 1000:1000 /metauser_home_vanilla/.config

# Create .bashrc with PS1 override for the vanilla home
RUN echo '# Source global definitions' > /metauser_home_vanilla/.bashrc && \
    echo '[ -f /etc/bashrc ] && . /etc/bashrc' >> /metauser_home_vanilla/.bashrc && \
    echo '[ -f /etc/bash.bashrc ] && . /etc/bash.bashrc' >> /metauser_home_vanilla/.bashrc && \
    echo '' >> /metauser_home_vanilla/.bashrc && \
    echo '# Force bash shell and normal prompt (override Apptainer)' >> /metauser_home_vanilla/.bashrc && \
    echo 'export SHELL=/bin/bash' >> /metauser_home_vanilla/.bashrc && \
    echo 'PS1='"'"'\u@\h:\w\$ '"'" >> /metauser_home_vanilla/.bashrc && \
    chown 1000:1000 /metauser_home_vanilla/.bashrc

# Create a bash wrapper that forces correct PS1 and environment
RUN cat > /usr/local/bin/container-bash << 'BASHWRAPPER'
#!/bin/bash
export SHELL=/bin/bash
export PS1='\u@\h:\w\$ '
exec /bin/bash --login "$@"
BASHWRAPPER
RUN chmod 755 /usr/local/bin/container-bash

# Configure xfce4-terminal to use bash properly
RUN mkdir -p /metauser_home_vanilla/.config/xfce4/terminal && \
    echo '[Configuration]\nFontName=Monospace 11\nMiscAlwaysShowTabs=FALSE\nMiscBell=FALSE\nMiscConfirmClose=TRUE\nColorForeground=#f8f8f2\nColorBackground=#282a36\nColorPalette=#21222c;#ff5555;#50fa7b;#f1fa8c;#bd93f9;#ff79c6;#8be9fd;#f8f8f2;#6272a4;#ff6e6e;#69ff94;#ffffa5;#d6acff;#ff92df;#a4ffff;#ffffff\nCommandLoginShell=TRUE\n' > /metauser_home_vanilla/.config/xfce4/terminal/terminalrc && \
    chown -R 1000:1000 /metauser_home_vanilla/.config/xfce4/terminal

# Fix home permissions (for Singularity compatibility)
RUN chmod 777 /home

#------------------------
# Environment Configuration
#------------------------

# Default entrypoint command (Nginx reverse proxy version)
ENV DEFAULT_ENTRYPOINT_COMMAND="/usr/local/bin/run_kasm_nginx.sh"

# Nginx/proxy configuration defaults
ENV NGINX_PORT=8080
ENV BASE_PATH=/
ENV BASE_PORT=8590
ENV KASM_PORT=8590

# Container identification
ENV CONTAINER_NAME='kasmvnc-xfce'

# Switch to non-root user
USER metauser

# Expose Nginx port
EXPOSE 8080

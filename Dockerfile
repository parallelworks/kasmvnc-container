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
    && apt-get clean

# Change APT user to allow some container runtimes properly work (i.e. Podman)
RUN groupadd -g 600 _apt && usermod -g 600 _apt

#------------------------
# "Meta" user
#------------------------

# Remove default ubuntu user if it exists (Ubuntu 24.04 creates one with UID/GID 1000)
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
# Kasm VNC 1.4.0 + Cinnamon Desktop
#------------------------

# Install X11, VNC dependencies, and Cinnamon desktop
RUN apt-get update && apt-get install -y \
    xvfb \
    xterm \
    net-tools \
    python3 \
    libdatetime-perl \
    dbus-x11 \
    at-spi2-core \
    cinnamon \
    cinnamon-session \
    cinnamon-settings-daemon \
    muffin \
    nemo \
    gnome-terminal \
    gedit \
    adwaita-icon-theme \
    gnome-themes-extra \
    xdg-utils \
    evince \
    file-roller \
    eog \
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
          /etc/xdg/autostart/org.gnome.SettingsDaemon.*.desktop \
          /etc/xdg/autostart/cinnamon-screensaver.desktop \
    2>/dev/null || true

# Install Adapta-Nokto theme from Cinnamon Spices
RUN cd /tmp && \
    wget -q https://cinnamon-spices.linuxmint.com/files/themes/Adapta-Nokto.zip && \
    unzip -q Adapta-Nokto.zip -d /usr/share/themes/ && \
    rm Adapta-Nokto.zip

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
RUN chmod 755 /usr/local/bin/run_kasm.sh /usr/local/bin/run_kasm_nginx.sh

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

# Configure gnome-terminal, desktop background, and dark mode via dconf
RUN mkdir -p /metauser_home_vanilla/.config/dconf && \
    mkdir -p /tmp/dconf-build && \
    echo '[org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9]' > /tmp/dconf-build/user.txt && \
    echo 'use-custom-command=true' >> /tmp/dconf-build/user.txt && \
    echo "custom-command='/bin/bash'" >> /tmp/dconf-build/user.txt && \
    echo 'login-shell=false' >> /tmp/dconf-build/user.txt && \
    echo '' >> /tmp/dconf-build/user.txt && \
    echo '[org/gnome/terminal/legacy/profiles:]' >> /tmp/dconf-build/user.txt && \
    echo "default='b1dcc9dd-5262-4d8d-a863-c897e6d979b9'" >> /tmp/dconf-build/user.txt && \
    echo "list=['b1dcc9dd-5262-4d8d-a863-c897e6d979b9']" >> /tmp/dconf-build/user.txt && \
    echo '' >> /tmp/dconf-build/user.txt && \
    echo '[org/cinnamon/desktop/background]' >> /tmp/dconf-build/user.txt && \
    echo "picture-uri='file:///usr/share/desktop-base/futureprototype-theme/wallpaper/contents/images/1920x1080.svg'" >> /tmp/dconf-build/user.txt && \
    echo "picture-options='zoom'" >> /tmp/dconf-build/user.txt && \
    echo '' >> /tmp/dconf-build/user.txt && \
    echo '[org/cinnamon/desktop/interface]' >> /tmp/dconf-build/user.txt && \
    echo "gtk-theme='Adapta-Nokto'" >> /tmp/dconf-build/user.txt && \
    echo "icon-theme='Adwaita'" >> /tmp/dconf-build/user.txt && \
    echo '' >> /tmp/dconf-build/user.txt && \
    echo '[org/cinnamon/desktop/wm/preferences]' >> /tmp/dconf-build/user.txt && \
    echo "theme='Adapta-Nokto'" >> /tmp/dconf-build/user.txt && \
    echo '' >> /tmp/dconf-build/user.txt && \
    echo '[org/cinnamon/theme]' >> /tmp/dconf-build/user.txt && \
    echo "name='Adapta-Nokto'" >> /tmp/dconf-build/user.txt && \
    dconf compile /metauser_home_vanilla/.config/dconf/user /tmp/dconf-build/ && \
    rm -rf /tmp/dconf-build

# Create .bashrc with PS1 override for the vanilla home
RUN echo '# Source global definitions' > /metauser_home_vanilla/.bashrc && \
    echo '[ -f /etc/bashrc ] && . /etc/bashrc' >> /metauser_home_vanilla/.bashrc && \
    echo '[ -f /etc/bash.bashrc ] && . /etc/bash.bashrc' >> /metauser_home_vanilla/.bashrc && \
    echo '' >> /metauser_home_vanilla/.bashrc && \
    echo '# Force bash shell and normal prompt (override Apptainer)' >> /metauser_home_vanilla/.bashrc && \
    echo 'export SHELL=/bin/bash' >> /metauser_home_vanilla/.bashrc && \
    echo 'PS1='"'"'\u@\h:\w\$ '"'" >> /metauser_home_vanilla/.bashrc && \
    chown 1000:1000 /metauser_home_vanilla/.bashrc

# Force gnome-terminal to always run /bin/bash (bypass $SHELL entirely)
# Replace the desktop file to ensure bash is always used
RUN cat > /usr/share/applications/org.gnome.Terminal.desktop << 'TERMEOF'
[Desktop Entry]
Name=Terminal
Comment=Use the command line
Keywords=shell;prompt;command;commandline;cmd;
TryExec=gnome-terminal
Exec=gnome-terminal -- /bin/bash
Icon=org.gnome.Terminal
Type=Application
Categories=GNOME;GTK;System;TerminalEmulator;
StartupNotify=true
X-GNOME-SingleWindow=false

[Desktop Action new-window]
Name=New Window
Exec=gnome-terminal --window -- /bin/bash

[Desktop Action preferences]
Name=Preferences
Exec=gnome-terminal --preferences
TERMEOF

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
ENV CONTAINER_NAME='kasmvnc-cinnamon'

# Switch to non-root user
USER metauser

# Expose Nginx port
EXPOSE 8080

#!/bin/bash

 # Exit on any error. More complex thing could be done in future
# (see https://stackoverflow.com/questions/4381618/exit-a-script-on-error)
set -e


if [ "x$SAFE_MODE" == "xTrue" ]; then

    echo ""
    echo "[INFO] Not executing entrypoint as we are in safe mode, just opening a Bash shell."
    exec /bin/bash

else

	echo ""
	echo "[INFO] Executing entrypoint..."

		
    #---------------------
    #   Setup home (UID-aware)
    #---------------------

	# Detect actual running user
	# Priority: USER/LOGNAME env vars (often preserved by Singularity), then whoami, then UID
	ACTUAL_UID=$(id -u)
	ACTUAL_GID=$(id -g)

	# Try to get username - prefer env vars which Singularity often preserves from host
	if [ -n "$USER" ] && [ "$USER" != "root" ]; then
		ACTUAL_USER="$USER"
	elif [ -n "$LOGNAME" ] && [ "$LOGNAME" != "root" ]; then
		ACTUAL_USER="$LOGNAME"
	else
		# Fall back to whoami (may show "metauser" or "I have no name!")
		ACTUAL_USER=$(whoami 2>/dev/null || echo "user${ACTUAL_UID}")
		# If whoami failed or returned something unhelpful, use UID-based name
		if [ "$ACTUAL_USER" = "I have no name!" ] || [ -z "$ACTUAL_USER" ]; then
			ACTUAL_USER="user${ACTUAL_UID}"
		fi
	fi

	# Try to get the user's default home from passwd (works when /etc/passwd is bind-mounted)
	PASSWD_HOME=$(getent passwd "$ACTUAL_USER" 2>/dev/null | cut -d: -f6 || echo "")

	echo "[INFO] Running as user: ${ACTUAL_USER} (UID=${ACTUAL_UID}, GID=${ACTUAL_GID})"

	# Determine the best home directory location
	# Priority:
	# 1. User's actual home if it exists and is writable (Singularity with bind-mounted home)
	# 2. /home/<username> if we can create/write to it (Docker mode)
	# 3. /tmp/<username>_home as fallback (Singularity read-only mode)

	USER_HOME=""

	# Option 1: Check if user's passwd home exists and is writable
	if [ -n "$PASSWD_HOME" ] && [ -d "$PASSWD_HOME" ] && [ -w "$PASSWD_HOME" ]; then
		USER_HOME="$PASSWD_HOME"
		echo "[INFO] Using existing home directory: ${USER_HOME}"
	# Option 2: Try to create /home/<username> (Docker mode or writable /home)
	elif mkdir -p "/home/${ACTUAL_USER}" 2>/dev/null; then
		USER_HOME="/home/${ACTUAL_USER}"
		echo "[INFO] Created home directory: ${USER_HOME}"
	# Option 3: Fall back to /tmp (Singularity read-only mode)
	else
		USER_HOME="/tmp/${ACTUAL_USER}_home"
		mkdir -p "${USER_HOME}"
		echo "[INFO] Using temporary home directory: ${USER_HOME} (read-only filesystem detected)"
	fi

	# Initialize home with vanilla configs if needed
	# Skip if home already has content (e.g., user's real home on HPC)
	if [ -f "${USER_HOME}/.container_initialized" ]; then
		echo "[INFO] Container configs already initialized in ${USER_HOME}"
	elif [ -f "${USER_HOME}/.bashrc" ] && [ "$PASSWD_HOME" = "$USER_HOME" ]; then
		# User's real home with existing configs - only copy missing container-specific files
		echo "[INFO] Existing home detected, adding container-specific configs only"

		# Copy VNC config if not present
		if [ -d "/metauser_home_vanilla/.vnc" ] && [ ! -d "${USER_HOME}/.vnc" ]; then
			cp -a /metauser_home_vanilla/.vnc "${USER_HOME}/"
		fi

		# Copy dconf config (gnome-terminal bash fix) if not present
		if [ -d "/metauser_home_vanilla/.config/dconf" ] && [ ! -d "${USER_HOME}/.config/dconf" ]; then
			mkdir -p "${USER_HOME}/.config"
			cp -a /metauser_home_vanilla/.config/dconf "${USER_HOME}/.config/"
		fi

		# Mark as initialized (use different marker to not interfere with user's files)
		touch "${USER_HOME}/.container_initialized"
	else
		echo "[INFO] Initializing home with container defaults at ${USER_HOME}"

		# Copy over vanilla home contents
		for x in /metauser_home_vanilla/* /metauser_home_vanilla/.[!.]* /metauser_home_vanilla/..?*; do
			if [ -e "$x" ]; then cp -a "$x" "${USER_HOME}/" 2>/dev/null || true; fi
		done

		# Mark as initialized
		touch "${USER_HOME}/.container_initialized"
	fi

	# Set HOME environment variable
	echo "[INFO] Setting HOME=${USER_HOME}"
	export HOME="${USER_HOME}"
	cd "${USER_HOME}" || cd /tmp

		
    #---------------------
    #   Save env
    #---------------------
	# Save full environment to /tmp/env.sh so host vars (from Singularity/Enroot)
	# propagate to VNC desktop sessions and terminals
	echo "[INFO] Saving environment to /tmp/env.sh"

	# Use env -0 and process safely to handle special characters in values
	: > /tmp/env.sh
	echo "# Container environment - sourced by new shells" >> /tmp/env.sh
	while IFS='=' read -r -d '' key value; do
		# Skip internal/readonly vars and vars that could cause issues
		case "$key" in
			BASH_FUNC_*|BASHOPTS|BASH_*|SHELLOPTS|FUNCNAME|GROUPS|DIRSTACK|_|SHLVL|PWD|OLDPWD|TERM|SSH_*) continue ;;
		esac
		# Use printf to safely handle values with quotes/special chars
		printf 'export %s=%q\n' "$key" "$value" >> /tmp/env.sh
	done < <(env -0 2>/dev/null || true)

		
    #---------------------
    #   Storage link
    #---------------------
    if [ -e "/storages" ] && [ ! -e "${USER_HOME}/storages" ]; then
	    echo "[INFO] Creating link from ${USER_HOME}/storages to /storages."
	    ln -s /storages "${USER_HOME}/storages" 2>/dev/null || true
    fi


    #---------------------
    #   Prompt - normal looking (no container indicators)
    #---------------------
	# Set PS1 to look like a normal shell - use HOSTNAME env var (preserved by Singularity)
	# or fall back to hostname command
	REAL_HOSTNAME="${HOSTNAME:-$(hostname -s 2>/dev/null || echo localhost)}"
	export PS1="${ACTUAL_USER}@${REAL_HOSTNAME}:\\w\$ "

	# Save to /tmp/env.sh for new terminal sessions
	echo "export PS1='${ACTUAL_USER}@${REAL_HOSTNAME}:\\w\$ '" >> /tmp/env.sh

    #---------------------
    #   Shell configuration
    #---------------------
	# Set SHELL to bash (gnome-terminal config is pre-compiled in dconf database)
	export SHELL=/bin/bash
	echo "export SHELL=/bin/bash" >> /tmp/env.sh
	
	
    #---------------------
    #  Entrypoint command
    #---------------------
	
	if [ "$@x" == "x" ]; then
	    echo -n "[INFO] Executing default entrypoint command: "
	    echo $DEFAULT_ENTRYPOINT_COMMAND
	    exec $DEFAULT_ENTRYPOINT_COMMAND
	else
	    echo -n "[INFO] Executing entrypoint command: "
	    echo $@
	    exec $@
	fi 

fi


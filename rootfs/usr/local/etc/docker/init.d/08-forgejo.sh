#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609030601-git
# @@Author           :  Jason Hempstead
# @@Contact          :  jason@casjaysdev.pro
# @@License          :  LICENSE.md
# @@ReadME           :  08-forgejo.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, May 24, 2026 11:59 EDT
# @@File             :  08-forgejo.sh
# @@Description      :
# @@Changelog        :  New script
# @@TODO             :  Better documentation
# @@Other            :
# @@Resource         :
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  other/start-service
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202609030601-git"
set -e
# - - - - - - - - - - - - - - - - - - - - - - - - -
# run trap command on exit
trap '__trap_err_handler' ERR
trap 'retVal=$?;if [ "$SERVICE_IS_RUNNING" != "yes" ] && [ -f "$SERVICE_PID_FILE" ]; then rm -Rf "$SERVICE_PID_FILE"; fi;exit $retVal' SIGINT SIGTERM
trap 'retVal=$?;if [ "$SERVICE_IS_RUNNING" != "yes" ] && [ -f "$SERVICE_PID_FILE" ]; then rm -Rf "$SERVICE_PID_FILE"; fi;exit $retVal' SIGPWR 2>/dev/null || true
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ERR trap handler - smart about critical vs non-critical errors
__trap_err_handler() {
  local retVal=$?
  local command="$BASH_COMMAND"
  # Ignore SIGPIPE and user interrupts
  [ $retVal -eq 130 ] || [ $retVal -eq 141 ] && return $retVal
  # Non-critical: file operations, text processing, user/group operations
  if [[ "$command" =~ (mkdir|touch|chmod|chown|chgrp|ln|cp|mv|rm|echo|printf|cat|tee|sed|awk|grep|find|sort|uniq|adduser|addgroup|usermod|groupmod|id|getent) ]]; then
    return 0
  fi
  # Non-critical: conditional checks that might fail
  if [[ "$command" =~ (test|\[|\[\[|kill -0|pgrep|pidof|ps) ]]; then
    return 0
  fi
  # Critical error - but only fail if service hasn't started yet
  if [ "$SERVICE_IS_RUNNING" != "yes" ]; then
    if [ -z "$NO_COLOR" ]; then
      echo "❌ Critical error (exit $retVal): $command" >&2
    else
      echo "Critical error (exit $retVal): $command" >&2
    fi
    kill -TERM 1 2>/dev/null || exit $retVal
  fi
  return 0
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
SCRIPT_FILE="$0"
SERVICE_NAME="forgejo"
SCRIPT_NAME="${SCRIPT_FILE##*/}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Function to exit appropriately based on context
__script_exit() {
	local exit_code="${1:-0}"
	if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
		# Script is being sourced - use return
		return "$exit_code"
	else
		# Script is being executed - use exit
		exit "$exit_code"
	fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Exit if service is disabled
if [ -n "$FORGEJO_APPNAME_ENABLED" ]; then
  if [ "$FORGEJO_APPNAME_ENABLED" != "yes" ]; then
    export SERVICE_DISABLED="$SERVICE_NAME"
    __script_exit 0
  fi
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# setup debugging - https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
[ -f "/config/.debug" ] && [ -z "$DEBUGGER_OPTIONS" ] && export DEBUGGER_OPTIONS="$(<"/config/.debug")" || DEBUGGER_OPTIONS="${DEBUGGER_OPTIONS:-}"
if [ "$DEBUGGER" = "on" ] || [ -f "/config/.debug" ]; then
  echo "Enabling debugging"
  set -o pipefail
  [ -n "$DEBUGGER_OPTIONS" ] && set -"$DEBUGGER_OPTIONS"
  export DEBUGGER="on"
else
  set -o pipefail
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
export PATH="/usr/local/etc/docker/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# import the functions file
if [ -f "/usr/local/etc/docker/functions/entrypoint.sh" ]; then
	. "/usr/local/etc/docker/functions/entrypoint.sh"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# import variables
for set_env in "/root/env.sh" "/usr/local/etc/docker/env"/*.sh "/config/env"/*.sh; do
  if [ -f "$set_env" ]; then
    . "$set_env"
  fi
done
# - - - - - - - - - - - - - - - - - - - - - - - - -
# exit if __start_init_scripts function hasn't been Initialized
if [ ! -f "/run/.start_init_scripts.pid" ]; then
	echo "__start_init_scripts function hasn't been Initialized" >&2
	SERVICE_IS_RUNNING="no"
	__script_exit 1
fi
# Clean up any stale PID file for this service on startup
if [ -n "$SERVICE_NAME" ] && [ -f "/run/init.d/$SERVICE_NAME.pid" ]; then
  old_pid=$(<"/run/init.d/$SERVICE_NAME.pid") 2>/dev/null
  if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
    if [ -z "$NO_COLOR" ]; then
      echo "🧹 Removing stale PID file for $SERVICE_NAME"
    else
      echo "Removing stale PID file for $SERVICE_NAME"
    fi
    rm -f "/run/init.d/$SERVICE_NAME.pid"
  fi
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Custom functions

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Script to execute
START_SCRIPT="/usr/local/etc/docker/exec/$SERVICE_NAME"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Reset environment before executing service
RESET_ENV="no"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set webroot
WWW_ROOT_DIR="/usr/local/share/httpd/default"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Default predefined variables
# set data directory
DATA_DIR="/data/forgejo"
# set config directory
CONF_DIR="/config/forgejo"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set the containers etc directory
ETC_DIR="/etc/forgejo"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set the var dir
VAR_DIR=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set the temp dir
TMP_DIR="/tmp/forgejo"
# set scripts pid dir
RUN_DIR="/run/forgejo"
# set log directory
LOG_DIR="/data/logs/forgejo"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set the working dir
WORK_DIR="/data/forgejo"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# port which service is listening on
SERVICE_PORT="80"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# User to use to launch service - IE: postgres
# forgejo must run as git user, not root
RUNAS_USER="git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# User and group in which the service switches to - IE: nginx,apache,mysql,postgres
# execute command as another user
SERVICE_USER="git"
# Set the service group
SERVICE_GROUP="git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set password length
RANDOM_PASS_USER=""
RANDOM_PASS_ROOT=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set user and group ID
# set the user id
SERVICE_UID="0"
# set the group id
SERVICE_GID="0"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# execute command variables - keep single quotes variables will be expanded later
# command to execute
EXEC_CMD_BIN='forgejo'
# command arguments
EXEC_CMD_ARGS='web '
# command arguments
EXEC_CMD_ARGS+='--port $SERVICE_PORT --config $CONF_DIR/app.ini '
# command arguments
EXEC_CMD_ARGS+='--custom-path $CONF_DIR/custom --work-path $DATA_DIR '
# execute script before
EXEC_PRE_SCRIPT=''
# Set to no if the service is not running otherwise leave blank
SERVICE_USES_PID=''
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Is this service a web server
IS_WEB_SERVER="no"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Is this service a database server
IS_DATABASE_SERVICE="no"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Does this service use a database server
USES_DATABASE_SERVICE="no"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set defualt type - [custom,sqlite,redis,postgres,mariadb,mysql,couchdb,mongodb,supabase]
DATABASE_SERVICE_TYPE="sqlite"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Show message before execute
PRE_EXEC_MESSAGE=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set the wait time to execute __post_execute function - minutes
POST_EXECUTE_WAIT_TIME="1"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Update path var
PATH="$PATH:."
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Lets get containers ip address
IP4_ADDRESS="$(__get_ip4)"
IP6_ADDRESS="$(__get_ip6)"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Where to save passwords to
# directory to save username/password for root user
ROOT_FILE_PREFIX="/config/secure/auth/root"
# directory to save username/password for normal user
USER_FILE_PREFIX="/config/secure/auth/user"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# root/admin user info password/random]
# root user name
root_user_name="${FORGEJO_ROOT_USER_NAME:-}"
# root user password
root_user_pass="${FORGEJO_ROOT_PASS_WORD:-}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Normal user info [password/random]
# normal user name
user_name="${FORGEJO_USER_NAME:-}"
# normal user password
user_pass="${FORGEJO_USER_PASS_WORD:-}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Load variables from config
# Generated by my dockermgr script
[ -f "/config/env/forgejo.script.sh" ] && . "/config/env/forgejo.script.sh"
# Overwrite the variabes
[ -f "/config/env/forgejo.sh" ] && . "/config/env/forgejo.sh"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Additional predefined variables

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Additional variables
DATABASE_DIR="${DATABASE_DIR_SQLITE:-$DATA_DIR/db/sqlite}"
FORGEJO_SQL_NAME="${FORGEJO_SQL_NAME:-}"
FORGEJO_SQL_HOST="${FORGEJO_SQL_HOST:-localhost}"
FORGEJO_WORK_DIR="${FORGEJO_WORK_DIR:-$WORK_DIR}"
TZ="${FORGEJO_TZ:-${TZ:-America/New_York}}"
# Map container-generic protocol env vars to SERVICE_PROTOCOL
SERVICE_PROTOCOL="${FORGEJO_PROTO:-${CONTAINER_PROTOCOL:-${CONTAINER_WEB_SERVER_PROTOCOL:-${SERVICE_PROTOCOL:-http}}}}"
# Map container-generic port env vars to SERVICE_PORT
SERVICE_PORT="${WEB_PORT:-${ENV_PORTS:-${SERVICE_PORT:-80}}}"
EMAIL_RELAY="${FORGEJO_EMAIL_RELAY:-${EMAIL_RELAY:-172.17.0.1}}"
SERVER_SITE_TITLE="${FORGEJO_NAME:-${SERVER_SITE_TITLE:-SelfHosted GIT Server}}"
SERVER_ADMIN="${FORGEJO_ADMIN:-${SERVER_ADMIN:-administrator@${HOSTNAME}}}"
FORGEJO_SERVER="${ENV_FORGEJO_SERVER:-$FORGEJO_SERVER}"
FORGEJO_EMAIL_CONFIRM="${FORGEJO_EMAIL_CONFIRM:-false}"
FORGEJO_SQL_DB_HOST="${FORGEJO_SQL_DB_HOST:-localhost}"
FORGEJO_SQL_USER="${ENV_FORGEJO_SQL_USER:-$FORGEJO_SQL_USER}"
FORGEJO_SQL_PASS="${ENV_FORGEJO_SQL_PASS:-$FORGEJO_SQL_PASS}"
# Map CONTAINER_DEFAULT_DATABASE_TYPE to forgejo's DB_TYPE value
if [ -n "$CONTAINER_DEFAULT_DATABASE_TYPE" ]; then
    DATABASE_SERVICE_TYPE="$CONTAINER_DEFAULT_DATABASE_TYPE"
    case "$CONTAINER_DEFAULT_DATABASE_TYPE" in
        sqlite|sqlite3) FORGEJO_SQL_TYPE="${FORGEJO_SQL_TYPE:-sqlite3}" ;;
        postgres|postgresql) FORGEJO_SQL_TYPE="${FORGEJO_SQL_TYPE:-postgres}" ;;
        mysql|mariadb) FORGEJO_SQL_TYPE="${FORGEJO_SQL_TYPE:-mysql}" ;;
        mssql) FORGEJO_SQL_TYPE="${FORGEJO_SQL_TYPE:-mssql}" ;;
    esac
fi
FORGEJO_SQL_TYPE="${ENV_FORGEJO_SQL_TYPE:-${FORGEJO_SQL_TYPE:-sqlite3}}"
HOSTNAME="${FORGEJO_SERVER:-${FORGEJO_HOSTNAME:-${FULL_DOMAIN_NAME:-$(hostname -f 2>/dev/null || echo "$HOSTNAME")}}}"
SERVER_NAME="${DOMAIN:-$HOSTNAME}"
SERVER_PROTO="${SERVICE_PROTOCOL:-http}"
# Feed SERVER_NAME back into FULL_DOMAIN_NAME so __initialize_replace_variables
# uses DOMAIN (if set) rather than falling back to the raw HOSTNAME.
export FULL_DOMAIN_NAME="$SERVER_NAME"
FORGEJO_SECRET_KEY="${FORGEJO_SECRET_KEY:-$(__random_password 32)}"
FORGEJO_LFS_JWT_SECRET="${FORGEJO_LFS_JWT_SECRET:-$($EXEC_CMD_BIN generate secret LFS_JWT_SECRET)}"
FORGEJO_INTERNAL_TOKEN="${FORGEJO_INTERNAL_TOKEN:-$($EXEC_CMD_BIN generate secret INTERNAL_TOKEN)}"
FORGEJO_RANDOM_COOKIE_KEY="${FORGEJO_RANDOM_COOKIE_KEY:-$(__random_password 16)}"
[ "$FORGEJO_EMAIL_CONFIRM" = "yes" ] && FORGEJO_EMAIL_CONFIRM="true"
export CUSTOM_PATH="$CONF_DIR/custom" WORK_DIR="${FORGEJO_WORK_DIR:-$DATA_DIR}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Specifiy custom directories to be created
ADD_APPLICATION_FILES=""
ADD_APPLICATION_DIRS=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
APPLICATION_FILES="$LOG_DIR/$SERVICE_NAME.log"
APPLICATION_DIRS="$ETC_DIR $CONF_DIR $DATA_DIR $LOG_DIR $TMP_DIR $RUN_DIR $VAR_DIR"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Additional config dirs - will be Copied to /etc/$name
ADDITIONAL_CONFIG_DIRS=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# define variables that need to be loaded into the service - escape quotes - var=\"value\",other=\"test\"
CMD_ENV=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Overwrite based on file/directory

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Per Application Variables or imports

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Custom commands to run before copying to /config
__run_precopy() {
	# Define environment
	local hostname=${HOSTNAME}
	[ -d "/run/healthcheck" ] || mkdir -p "/run/healthcheck"
	# Re-apply custom resolv.conf — Docker rewrites /etc/resolv.conf asynchronously
	# during container startup, after the entrypoint's initial copy. Applying it here
	# (in the init.d phase) ensures it takes effect after Docker finishes network setup.
	[ -f "/usr/local/etc/resolv.conf" ] && cp -f "/usr/local/etc/resolv.conf" "/etc/resolv.conf" 2>/dev/null || true
	# Seed /config/$SERVICE_NAME from the baked /etc copy on first initialisation only.
	# The marker file $CONF_DIR/.initialized is written after substitution completes;
	# delete it to force a re-seed (e.g. after intentional config reset).
	# Then replace the /etc/$SERVICE_NAME directory with a symlink to /config/$SERVICE_NAME
	# so both paths always resolve to the same processed config.
	if [ -d "$ETC_DIR" ] && ! [ -L "$ETC_DIR" ]; then
		if [ ! -f "$CONF_DIR/.initialized" ]; then
			mkdir -p "$CONF_DIR"
			cp -Rf "$ETC_DIR/." "$CONF_DIR/" 2>/dev/null || true
		fi
		rm -Rf "$ETC_DIR"
		ln -sf "$CONF_DIR" "$ETC_DIR"
	fi
	# allow custom functions
	if builtin type -t __run_precopy_local | grep -q -- 'function'; then __run_precopy_local; fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Custom prerun functions - IE setup WWW_ROOT_DIR
__execute_prerun() {
	# Define environment
	local hostname=${HOSTNAME}
	# Define actions/commands

	# allow custom functions
	if builtin type -t __execute_prerun_local | grep -q -- 'function'; then __execute_prerun_local; fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Run any pre-execution checks
__run_pre_execute_checks() {
	# Set variables
	local exitStatus=0
	# message to show at start
	local pre_execute_checks_MessageST="Running preexecute check for $SERVICE_NAME"
	# message to show at completion
	local pre_execute_checks_MessageEnd="Finished preexecute check for $SERVICE_NAME"
	__banner "$pre_execute_checks_MessageST"
	# Put command to execute in parentheses
	{
		true
	}
	exitStatus=$?
	__banner "$pre_execute_checks_MessageEnd: Status $exitStatus"

	# show exit message
	if [ $exitStatus -ne 0 ]; then
		echo "The pre-execution check has failed" >&2
		[ -f "$SERVICE_PID_FILE" ] && rm -Rf "$SERVICE_PID_FILE"
		__script_exit 1
	fi
	# allow custom functions
	if builtin type -t __run_pre_execute_checks_local | grep -q -- 'function'; then __run_pre_execute_checks_local; fi
	# exit function
	return $exitStatus
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# use this function to update config files - IE: change port
__update_conf_files() {
	# default exit code
	local exitCode=0
	# set hostname
	local sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}"
	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# delete files
	#__rm ""

	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# custom commands
	__is_dir_empty "/config/ssh" && COPY_SSHD_CONF="yes"

	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# replace variables
	__replace "REPLACE_SSH_CONF_DIR" "/config/ssh" "/etc/ssh/sshd_config"
	__replace "REPLACE_SSH_DATA_DIR" "$DATA_DIR/ssh" "/etc/ssh/sshd_config"
	__replace "REPLACE_RANDOM_COOKIE_KEY" "$FORGEJO_RANDOM_COOKIE_KEY" "$CONF_DIR/app.ini"

	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# define actions
	[ -d "/config/ssh" ] || mkdir -p "/config/ssh"
	[ -d "$DATA_DIR/ssh" ] || mkdir -p "$DATA_DIR/ssh"
	[ "$COPY_SSHD_CONF" = "yes" ] && copy "/etc/ssh/sshd_config" "/config/ssh/"
	if [ ! -f "/config/ssh/ssh_host_ed25519_key" ]; then
		echo "Generating /config/ssh/ssh_host_ed25519_key..."
		ssh-keygen -t ed25519 -f /config/ssh/ssh_host_ed25519_key -N "" >/dev/null && __symlink "/config/ssh/ssh_host_ed25519_key" "$DATA_DIR/ssh/ssh_host_ed25519_key"
	fi
	if [ ! -f "/config/ssh/ssh_host_rsa_key" ]; then
		echo "Generating /config/ssh/ssh_host_rsa_key..."
		ssh-keygen -t rsa -b 3072 -f /config/ssh/ssh_host_rsa_key -N "" >/dev/null && __symlink "/config/ssh/ssh_host_rsa_key" "$DATA_DIR/ssh/ssh_host_rsa_key"
	fi
	if [ ! -f "/config/ssh/ssh_host_ecdsa_key" ]; then
		echo "Generating /config/ssh/ssh_host_ecdsa_key..."
		ssh-keygen -t ecdsa -b 256 -f /config/ssh/ssh_host_ecdsa_key -N "" >/dev/null && __symlink "/config/ssh/ssh_host_ecdsa_key" "$DATA_DIR/ssh/ssh_host_ecdsa_key"
	fi
	chmod 0700 "$DATA_DIR/ssh" /config/ssh
	find "$DATA_DIR/ssh" /config/ssh -maxdepth 1 -type f -exec chmod 0600 {} \;
	[ -d "$DATA_DIR/ssh" ] || mkdir -p "$DATA_DIR/ssh"
	[ -d "$CONF_DIR/custom" ] || mkdir -p "$CONF_DIR/custom"
	if [ -n "$CONF_DIR" ] && [ -f "$CONF_DIR/app.ini" ]; then
		sed -i "s|REPLACE_SQL_NAME|$FORGEJO_SQL_NAME|g" "$CONF_DIR/app.ini"
		sed -i "s|REPLACE_SQL_USER|$FORGEJO_SQL_USER|g" "$CONF_DIR/app.ini"
		sed -i "s|REPLACE_SQL_PASS|$FORGEJO_SQL_PASS|g" "$CONF_DIR/app.ini"
		sed -i "s|REPLACE_SQL_TYPE|${FORGEJO_SQL_TYPE}|g" "$CONF_DIR/app.ini"
		sed -i "s|REPLACE_SQL_HOST|$FORGEJO_SQL_DB_HOST|g" "$CONF_DIR/app.ini"
		sed -i "s|REPLACE_DATABASE_DIR|$DATABASE_DIR|g" "$CONF_DIR/app.ini"
		sed -i "s|REPLACE_SECRET_KEY|$FORGEJO_SECRET_KEY|g" "$CONF_DIR/app.ini"
		sed -i "s|REPLACE_FORGEJO_EMAIL_CONFIRM|$FORGEJO_EMAIL_CONFIRM|g" "$CONF_DIR/app.ini"
		sed -i "s|REPLACE_FORGEJO_INTERNAL_TOKEN|$FORGEJO_INTERNAL_TOKEN|g" "$CONF_DIR/app.ini"
		sed -i "s|REPLACE_FORGEJO_LFS_JWT_SECRET|$FORGEJO_LFS_JWT_SECRET|g" "$CONF_DIR/app.ini"
	fi
	# Re-stamp dynamic values and remove deprecated settings on every startup.
	for _ini_file in "$CONF_DIR/app.ini"; do
		[ -f "$_ini_file" ] || continue
		# Sync ROOT_URL, DOMAIN, and SSH_DOMAIN — prefer DOMAIN env var over raw hostname
		sed -i "s|^ROOT_URL[[:space:]]*=.*|ROOT_URL = ${SERVICE_PROTOCOL:-http}://${SERVER_NAME}|" "$_ini_file"
		sed -i "s|^DOMAIN[[:space:]]*=.*|DOMAIN = ${SERVER_NAME}|" "$_ini_file"
		sed -i "s|^SSH_DOMAIN[[:space:]]*=.*|SSH_DOMAIN = ${SERVER_NAME}|" "$_ini_file"
		# Remove deprecated [cors].X_FRAME_OPTIONS (moved to [security] in Gitea v1.26)
		awk 'BEGIN{in_s=0}/^\[/{in_s=0}/^\[cors\]/{in_s=1}in_s&&/^X_FRAME_OPTIONS/{next}{print}' \
			"$_ini_file" > /tmp/_forgejo_conf.ini && mv /tmp/_forgejo_conf.ini "$_ini_file"
		# Remove deprecated [picture].DISABLE_GRAVATAR (moved to admin panel in Gitea v1.18)
		awk 'BEGIN{in_s=0}/^\[/{in_s=0}/^\[picture\]/{in_s=1}in_s&&/^DISABLE_GRAVATAR/{next}{print}' \
			"$_ini_file" > /tmp/_forgejo_conf.ini && mv /tmp/_forgejo_conf.ini "$_ini_file"
		# Remove deprecated [picture].ENABLE_FEDERATED_AVATAR (moved to admin panel in Gitea v1.18)
		awk 'BEGIN{in_s=0}/^\[/{in_s=0}/^\[picture\]/{in_s=1}in_s&&/^ENABLE_FEDERATED_AVATAR/{next}{print}' \
			"$_ini_file" > /tmp/_forgejo_conf.ini && mv /tmp/_forgejo_conf.ini "$_ini_file"
	done
	unset _ini_file
	if [ -n "$DATA_DIR" ] && [ -d "$DATA_DIR" ]; then
		find "$DATA_DIR" -type d -exec chmod 0777 {} \;
		chown -Rf $SERVICE_USER:$SERVICE_GROUP "$DATA_DIR" 2>/dev/null
	fi
	[ -d "$DATABASE_DIR" ] && chown -Rf $SERVICE_USER:$SERVICE_GROUP "$DATABASE_DIR" 2>/dev/null
	# Mark config as fully initialised so __run_precopy skips re-seeding on restart
	touch "$CONF_DIR/.initialized" 2>/dev/null || true

	# allow custom functions
	if builtin type -t __update_conf_files_local | grep -q -- 'function'; then __update_conf_files_local; fi
	# exit function
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# function to run before executing
__pre_execute() {
	# default exit code
	local exitCode=0
	# set hostname
	local sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}"
	# execute if directories is empty
	# __is_dir_empty "$CONF_DIR" && true
	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# define actions to run after copying to /config

	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# unset unneeded variables
	unset sysname
	# Lets wait a few seconds before continuing
	sleep 2
	# allow custom functions
	if builtin type -t __pre_execute_local | grep -q -- 'function'; then __pre_execute_local; fi
	# exit function
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# function to run after executing
__post_execute() {
	# init pid var
	local pid=""
	# set default exit code
	local retVal=0
	# how long to wait before executing
	local ctime=${POST_EXECUTE_WAIT_TIME:-1}
	# convert minutes to seconds
	local waitTime=$((ctime * 60))
	# message to show at start
	local postMessageST="Running post commands for $SERVICE_NAME"
	# message to show at completion
	local postMessageEnd="Finished post commands for $SERVICE_NAME"
	# wait
	sleep $waitTime
	# execute commands after waiting
	(
		# show message
		__banner "$postMessageST"
		# commands to execute
		sleep 5
		# show exit message
		__banner "$postMessageEnd: Status $retVal"
	) 2>"/dev/stderr" | tee -p -a "/data/logs/init.txt" &
	# fire-and-forget: backgrounded subshell always succeeds at launch
	retVal=0
	# allow custom functions
	if builtin type -t __post_execute_local | grep -q -- 'function'; then __post_execute_local; fi
	# exit function
	return $retVal
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# use this function to update config files - IE: change port
__pre_message() {
	local exitCode=0
	[ -n "$PRE_EXEC_MESSAGE" ] && eval echo "$PRE_EXEC_MESSAGE"
	# execute commands

	# allow custom functions
	if builtin type -t __pre_message_local | grep -q -- 'function'; then __pre_message_local; fi
	# exit function
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# use this function to setup ssl support
__update_ssl_conf() {
	local exitCode=0
	# set hostname
	local sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}"
	# execute commands

	# allow custom functions
	if builtin type -t __update_ssl_conf_local | grep -q -- 'function'; then __update_ssl_conf_local; fi
	# set exitCode
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__create_service_env() {
	local exitCode=0
	if [ ! -f "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" ]; then
		cat <<EOF | tee -p "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" &>/dev/null
# - - - - - - - - - - - - - - - - - - - - - - - - -
# root/admin user info [password/random]
#ENV_ROOT_USER_NAME="${ENV_ROOT_USER_NAME:-$FORGEJO_ROOT_USER_NAME}"   # root user name
#ENV_ROOT_USER_PASS="${ENV_ROOT_USER_NAME:-$FORGEJO_ROOT_PASS_WORD}"   # root user password
#root_user_name="${ENV_ROOT_USER_NAME:-$root_user_name}"                              #
#root_user_pass="${ENV_ROOT_USER_PASS:-$root_user_pass}"                              #
# - - - - - - - - - - - - - - - - - - - - - - - - -
#Normal user info [password/random]
#ENV_USER_NAME="${ENV_USER_NAME:-$FORGEJO_USER_NAME}"                  #
#ENV_USER_PASS="${ENV_USER_PASS:-$FORGEJO_USER_PASS_WORD}"             #
#user_name="${ENV_USER_NAME:-$user_name}"                                             # normal user name
#user_pass="${ENV_USER_PASS:-$user_pass}"                                             # normal user password

EOF
	fi
	if [ ! -f "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.local.sh" ]; then
		cat <<'EOF' >"/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.local.sh"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Local overrides - sourced after the main env file.
# Redefine any of these functions to customise behaviour.
# - - - - - - - - - - - - - - - - - - - - - - - - -
__run_precopy_local() { true; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
__execute_prerun_local() { true; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
__run_pre_execute_checks_local() { true; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
__update_conf_files_local() { true; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
__pre_execute_local() { true; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
__post_execute_local() { true; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
__pre_message_local() { true; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
__update_ssl_conf_local() { true; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
EOF
	fi
	__file_exists_with_content "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" || exitCode=$((exitCode + 1))
	__file_exists_with_content "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.local.sh" || exitCode=$((exitCode + 1))
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# script to start server
__run_start_script() {
  local runExitCode=0
  # expand variables
  local workdir="$(eval echo "${WORK_DIR:-}")"
  # expand variables
  local cmd="$(eval echo "${EXEC_CMD_BIN:-}")"
  # expand variables
  local args="$(eval echo "${EXEC_CMD_ARGS:-}")"
  # expand variables
  local name="$(eval echo "${EXEC_CMD_NAME:-}")"
  # expand variables
  local pre="$(eval echo "${EXEC_PRE_SCRIPT:-}")"
  # expand variables
  local extra_env="$(eval echo "${CMD_ENV//,/ }")"
  # expand variables
  local lc_type="$(eval echo "${LANG:-${LC_ALL:-$LC_CTYPE}}")"
  # expand variables
  local home="$(eval echo "${workdir//\/root/\/tmp\/docker}")"
  # expand variables
  local path="$(eval echo "$PATH")"
  # expand variables
  local message="$(eval echo "")"
  local sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}"
  if [ -f "$CONF_DIR/$SERVICE_NAME.exec_cmd.sh" ]; then
    . "$CONF_DIR/$SERVICE_NAME.exec_cmd.sh"
  fi
  #
  if [ -z "$cmd" ]; then
    __post_execute 2>"/dev/stderr" | tee -p -a "/data/logs/init.txt"
    retVal=$?
    __log_info "Initialization of $SCRIPT_NAME has completed"
    __script_exit $retVal
  else
    # ensure the command exists
    if [ ! -x "$cmd" ]; then
      __log_error "$name is not a valid executable"
      return 2
    fi
    # check and exit if already running (respects SERVICE_USES_PID in __proc_check)
    if __proc_check "$name" || __proc_check "$cmd"; then
      __log_debug "Service $name is already running"
      return 0
    else
      # - - - - - - - - - - - - - - - - - - - - - - - - -
      # show message if env exists
      if [ -n "$cmd" ]; then
        if [ -n "$SERVICE_USER" ]; then
          __log_info "Setting up $cmd to run as $SERVICE_USER"
        else
          SERVICE_USER="root"
        fi
        if [ -n "$SERVICE_PORT" ]; then
          __log_info "$name will be running on port $SERVICE_PORT"
        else
          SERVICE_PORT=""
        fi
      fi
      if [ -n "$pre" ] && command -v "$pre" &>/dev/null; then
        export cmd_exec="$pre $cmd $args"
        message="Starting service: $name $args through $pre"
      else
        export cmd_exec="$cmd $args"
        message="Starting service: $name $args"
      fi
      if [ -n "$su_exec" ]; then
        __log_debug "Using $su_exec" | tee -a -p "/data/logs/init.txt"
      fi
      __log_info "$message" | tee -a -p "/data/logs/init.txt"
      __su_cmd touch "$SERVICE_PID_FILE"
      # W14: invalidate cached START_SCRIPT if key variables changed
      local _script_hash_src="$cmd $args $SERVICE_USER $RESET_ENV $su_exec"
      local _script_hash
      _script_hash=$(printf '%s' "$_script_hash_src" | md5sum 2>/dev/null | cut -c1-8 || true)
      if [ -f "${START_SCRIPT}.hash" ] && [ -f "$START_SCRIPT" ]; then
        if [ "$(cat "${START_SCRIPT}.hash" 2>/dev/null)" != "$_script_hash" ]; then
          rm -f "$START_SCRIPT" "${START_SCRIPT}.hash"
        fi
      fi
      if [ "$RESET_ENV" = "yes" ]; then
        # RESET_ENV=yes intentionally strips all inherited vars; only explicit vars are passed
        if [ ! -f "$START_SCRIPT" ]; then
          # Use printf %q to safely quote each env component for embedding in the script
          local _q_home _q_lc _q_path _q_sysname _q_svcuser _q_su _q_cmd _q_args _q_extra
          _q_home=$(printf '%q' "$home")
          _q_lc=$(printf '%q' "$lc_type")
          _q_path=$(printf '%q' "$path")
          _q_sysname=$(printf '%q' "$sysname")
          _q_svcuser=$(printf '%q' "${SERVICE_USER:-$RUNAS_USER}")
          _q_su="${su_exec:+$(printf '%q ' $su_exec)}"
          _q_cmd=$(printf '%q' "$cmd")
          _q_args=$(printf '%q ' $args)
          _q_extra=$(printf '%q ' $extra_env)
          {
            printf '#!/usr/bin/env bash\n'
            printf "trap 'exitCode=\$?;[ \$exitCode -ne 0 ] && [ -f \"\$SERVICE_PID_FILE\" ] && rm -Rf \"\$SERVICE_PID_FILE\";exit \$exitCode' EXIT\n"
            printf 'set -Eeo pipefail\n'
            printf '# Setting up %s to run as %s with env\n' "$cmd" "${SERVICE_USER:-root}"
            printf 'retVal=10\n'
            printf 'SERVICE_NAME=%q\n' "$SERVICE_NAME"
            printf 'SERVICE_PID_FILE=%q\n' "$SERVICE_PID_FILE"
            printf 'LOG_DIR=%q\n' "$LOG_DIR"
            printf '%senv -i HOME=%s LC_CTYPE=%s PATH=%s HOSTNAME=%s USER=%s %s %s %s 2>>"/dev/stderr" >>"$LOG_DIR/$SERVICE_NAME.log" &\n' \
              "$_q_su" "$_q_home" "$_q_lc" "$_q_path" "$_q_sysname" "$_q_svcuser" "$_q_extra" "$_q_cmd" "$_q_args"
            printf 'execPid=$!\n'
            printf 'sleep 1\n'
            printf 'if [ -n "$execPid" ] && kill -0 "$execPid" 2>/dev/null; then\n'
            printf '  echo "$execPid" >"$SERVICE_PID_FILE"\n'
            printf '  retVal=0\n'
            printf '  printf '"'"'%%s\n'"'"' "$SERVICE_NAME: $execPid" >"/run/healthcheck/$SERVICE_NAME"\n'
            printf 'else\n'
            printf '  retVal=10\n'
            printf '  echo "Failed to start service %s" >&2\n' "$cmd"
            printf 'fi\n'
            printf 'exit $retVal\n'
          } >"$START_SCRIPT"
          printf '%s' "$_script_hash" >"${START_SCRIPT}.hash"
        fi
      else
        if [ ! -f "$START_SCRIPT" ]; then
          local _q_su _q_cmd _q_args _q_path _q_home
          _q_su="${su_exec:+$(printf '%q ' $su_exec)}"
          _q_cmd=$(printf '%q' "$cmd")
          _q_args=$(printf '%q ' $args)
          _q_path=$(printf '%q' "$path")
          _q_home=$(printf '%q' "$home")
          {
            printf '#!/usr/bin/env bash\n'
            printf "trap 'exitCode=\$?;[ \$exitCode -ne 0 ] && [ -f \"\$SERVICE_PID_FILE\" ] && rm -Rf \"\$SERVICE_PID_FILE\";exit \$exitCode' EXIT\n"
            printf 'set -Eeo pipefail\n'
            printf '# Setting up %s to run as %s\n' "$cmd" "${SERVICE_USER:-root}"
            printf 'export PATH=%s\n' "$_q_path"
            printf 'export HOME=%s\n' "$_q_home"
            printf 'retVal=10\n'
            printf 'SERVICE_NAME=%q\n' "$SERVICE_NAME"
            printf 'SERVICE_PID_FILE=%q\n' "$SERVICE_PID_FILE"
            printf 'LOG_DIR=%q\n' "$LOG_DIR"
            printf '%s%s %s 2>>"/dev/stderr" >>"$LOG_DIR/$SERVICE_NAME.log" &\n' \
              "$_q_su" "$_q_cmd" "$_q_args"
            printf 'execPid=$!\n'
            printf 'sleep 1\n'
            printf 'if [ -n "$execPid" ] && kill -0 "$execPid" 2>/dev/null; then\n'
            printf '  echo "$execPid" >"$SERVICE_PID_FILE"\n'
            printf '  retVal=0\n'
            printf 'else\n'
            printf '  retVal=10\n'
            printf '  echo "Failed to start service %s" >&2\n' "$cmd"
            printf 'fi\n'
            printf 'exit $retVal\n'
          } >"$START_SCRIPT"
          printf '%s' "$_script_hash" >"${START_SCRIPT}.hash"
        fi
      fi
    fi
    if [ ! -x "$START_SCRIPT" ]; then
      chmod 755 -Rf "$START_SCRIPT"
    fi
    if [ "$CONTAINER_INIT" != "yes" ]; then
      # W15: launch as bash, not sh, since the generated script uses bash-specific features
      bash "$START_SCRIPT"
      runExitCode=$?
    fi
  fi
  return $runExitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# username and password actions
__run_secure_function() {
	local filesperms
	if [ -n "$user_name" ] || [ -n "$user_pass" ]; then
		for filesperms in "${USER_FILE_PREFIX}"/*; do
			if [ -e "$filesperms" ]; then
				chmod -Rf 600 "$filesperms"
				chown -Rf $SERVICE_USER:$SERVICE_USER "$filesperms" 2>/dev/null
			fi
		done 2>/dev/null | tee -p -a "/data/logs/init.txt"
	fi
	if [ -n "$root_user_name" ] || [ -n "$root_user_pass" ]; then
		for filesperms in "${ROOT_FILE_PREFIX}"/*; do
			if [ -e "$filesperms" ]; then
				chmod -Rf 600 "$filesperms"
				chown -Rf $SERVICE_USER:$SERVICE_USER "$filesperms" 2>/dev/null
			fi
		done 2>/dev/null | tee -p -a "/data/logs/init.txt"
	fi
	unset filesperms
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow ENV_ variable - Import env file
__file_exists_with_content "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" && . "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh"
__file_exists_with_content "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.local.sh" && . "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.local.sh"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# default exit code
SERVICE_EXIT_CODE=0
# application specific
# set the binary name
EXEC_CMD_NAME="${EXEC_CMD_BIN##*/}"
# set the pid file location
SERVICE_PID_FILE="/run/init.d/$EXEC_CMD_NAME.pid"
# check if running
SERVICE_PID_NUMBER="$(__pgrep "$EXEC_CMD_NAME" || echo '')"
# set full path
EXEC_CMD_BIN="$(type -P "$EXEC_CMD_BIN" || echo "$EXEC_CMD_BIN")"
# set full path
EXEC_PRE_SCRIPT="$(type -P "$EXEC_PRE_SCRIPT" || echo "$EXEC_PRE_SCRIPT")"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Only run check when explicitly requested
if [ "$1" = "check" ] && __check_service "$1"; then
  SERVICE_IS_RUNNING=yes
elif [ "$1" = "check" ]; then
  SERVICE_IS_RUNNING="no"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ensure needed directories exists
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
[ -d "$RUN_DIR" ] || mkdir -p "$RUN_DIR"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# create auth directories
[ -n "$USER_FILE_PREFIX" ] && { [ -d "$USER_FILE_PREFIX" ] || mkdir -p "$USER_FILE_PREFIX"; }
[ -n "$ROOT_FILE_PREFIX" ] && { [ -d "$ROOT_FILE_PREFIX" ] || mkdir -p "$ROOT_FILE_PREFIX"; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
[ -n "$RUNAS_USER" ] || RUNAS_USER="root"
[ -n "$SERVICE_USER" ] || SERVICE_USER="$RUNAS_USER"
[ -n "$SERVICE_GROUP" ] || SERVICE_GROUP="${SERVICE_USER:-$RUNAS_USER}"
[ "$IS_WEB_SERVER" = "yes" ] && RESET_ENV="yes" && __is_htdocs_mounted
[ "$IS_WEB_SERVER" = "yes" ] && [ -z "$SERVICE_PORT" ] && SERVICE_PORT="80"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Database env
if [ "$IS_DATABASE_SERVICE" = "yes" ] || [ "$USES_DATABASE_SERVICE" = "yes" ]; then
	RESET_ENV="no"
	DATABASE_CREATE="${ENV_DATABASE_CREATE:-$DATABASE_CREATE}"
	DATABASE_USER_NORMAL="${ENV_DATABASE_USER:-${DATABASE_USER_NORMAL:-$user_name}}"
	DATABASE_PASS_NORMAL="${ENV_DATABASE_PASSWORD:-${DATABASE_PASS_NORMAL:-$user_pass}}"
	DATABASE_USER_ROOT="${ENV_DATABASE_ROOT_USER:-${DATABASE_USER_ROOT:-$root_user_name}}"
	DATABASE_PASS_ROOT="${ENV_DATABASE_ROOT_PASSWORD:-${DATABASE_PASS_ROOT:-$root_user_pass}}"
	if [ -n "$DATABASE_PASS_NORMAL" ] && [ ! -f "${USER_FILE_PREFIX}/db_pass_user" ]; then
		echo "$DATABASE_PASS_NORMAL" >"${USER_FILE_PREFIX}/db_pass_user"
	fi
	if [ -n "$DATABASE_PASS_ROOT" ] && [ ! -f "${ROOT_FILE_PREFIX}/db_pass_root" ]; then
		echo "$DATABASE_PASS_ROOT" >"${ROOT_FILE_PREFIX}/db_pass_root"
	fi
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# [DATABASE_DIR_[SQLITE,REDIS,POSTGRES,MARIADB,COUCHDB,MONGODB,SUPABASE]]
if [ "$DATABASE_SERVICE_TYPE" = "custom" ]; then
	DATABASE_DIR="${DATABASE_DIR_CUSTOM:-/data/db/custom}"
	DATABASE_BASE_DIR="${DATABASE_DIR_CUSTOM:-/data/db/custom}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_CUSTOM:-/usr/local/share/httpd/admin/databases}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_CUSTOM:-/admin/dbadmin}"
elif [ "$SERVICE_NAME" = "redis" ] || [ "$DATABASE_SERVICE_TYPE" = "redis" ]; then
	DATABASE_DIR="${DATABASE_DIR_REDIS:-/data/db/redis}"
	DATABASE_BASE_DIR="${DATABASE_DIR_REDIS:-/data/db/redis}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_REDIS:-/usr/local/share/httpd/admin/redis}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_REDIS:-/admin/redis}"
elif [ "$SERVICE_NAME" = "postgres" ] || [ "$DATABASE_SERVICE_TYPE" = "postgres" ]; then
	DATABASE_DIR="${DATABASE_DIR_POSTGRES:-/data/db/postgres}"
	DATABASE_BASE_DIR="${DATABASE_DIR_POSTGRES:-/data/db/postgres}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_POSTGRES:-/usr/local/share/httpd/admin/postgres}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_POSTGRES:-/admin/postgres}"
elif [ "$SERVICE_NAME" = "mariadb" ] || [ "$DATABASE_SERVICE_TYPE" = "mariadb" ]; then
	DATABASE_DIR="${DATABASE_DIR_MARIADB:-/data/db/mariadb}"
	DATABASE_BASE_DIR="${DATABASE_DIR_MARIADB:-/data/db/mariadb}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_MARIADB:-/usr/local/share/httpd/admin/mysql}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_MARIADB:-/admin/mysql}"
elif [ "$SERVICE_NAME" = "mysql" ] || [ "$DATABASE_SERVICE_TYPE" = "mysql" ]; then
	DATABASE_DIR="${DATABASE_DIR_MYSQL:-/data/db/mysql}"
	DATABASE_BASE_DIR="${DATABASE_DIR_MYSQL:-/data/db/mysql}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_MYSQL:-/usr/local/share/httpd/admin/mysql}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_MYSQL:-/admin/mysql}"
elif [ "$SERVICE_NAME" = "couchdb" ] || [ "$DATABASE_SERVICE_TYPE" = "couchdb" ]; then
	DATABASE_DIR="${DATABASE_DIR_COUCHDB:-/data/db/couchdb}"
	DATABASE_BASE_DIR="${DATABASE_DIR_COUCHDB:-/data/db/couchdb}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_COUCHDB:-/usr/local/share/httpd/admin/couchdb}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_COUCHDB:-/admin/couchdb}"
elif [ "$SERVICE_NAME" = "mongodb" ] || [ "$DATABASE_SERVICE_TYPE" = "mongodb" ]; then
	DATABASE_DIR="${DATABASE_DIR_MONGODB:-/data/db/mongodb}"
	DATABASE_BASE_DIR="${DATABASE_DIR_MONGODB:-/data/db/mongodb}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_MONGODB:-/usr/local/share/httpd/admin/mongodb}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_MONGODB:-/admin/mongodb}"
elif [ "$SERVICE_NAME" = "supabase" ] || [ "$DATABASE_SERVICE_TYPE" = "supabase" ]; then
	DATABASE_DIR="${DATABASE_DIR_SUPABASE:-/data/db/supabase}"
	DATABASE_BASE_DIR="${DATABASE_DIR_SUPABASE:-/data/db/supabase}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_SUPABASE:-/usr/local/share/httpd/admin/supabase}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_SUPBASE:-/admin/supabase}"
elif [ "$SERVICE_NAME" = "sqlite" ] || [ "$DATABASE_SERVICE_TYPE" = "sqlite" ]; then
	DATABASE_DIR="${DATABASE_DIR_SQLITE:-/data/db/sqlite}/$SERVER_NAME"
	DATABASE_BASE_DIR="${DATABASE_DIR_SQLITE:-/data/db/sqlite}/$SERVER_NAME"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_SQLITE:-/usr/local/share/httpd/admin/sqlite}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_SQLITE:-/admin/sqlite}"
	[ -d "$DATABASE_DIR" ] || mkdir -p "$DATABASE_DIR"
	chmod 777 "$DATABASE_DIR"
fi
# Override: pin to a predictable path — respect DATABASE_DIR_SQLITE if set, otherwise use DATA_DIR
DATABASE_DIR="${DATABASE_DIR_SQLITE:-$DATA_DIR/db/sqlite}"
[ -d "$DATABASE_DIR" ] || mkdir -p "$DATABASE_DIR"
[ -n "$DATABASE_ADMIN_WWW_ROOT" ] && { [ ! -d "$DATABASE_ADMIN_WWW_ROOT" ] || mkdir -p "${DATABASE_ADMIN_WWW_ROOT}"; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow variables via imports - Overwrite existing
[ -f "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" ] && . "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set password to random if variable is random
[ "$user_pass" = "random" ] && user_pass="$(__random_password ${RANDOM_PASS_USER:-16})"
# - - - - - - - - - - - - - - - - - - - - - - - - -
[ "$root_user_pass" = "random" ] && root_user_pass="$(__random_password ${RANDOM_PASS_ROOT:-16})"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow setting initial users and passwords via environment and save to file
[ -n "$user_name" ] && echo "$user_name" >"${USER_FILE_PREFIX}/${SERVICE_NAME}_name"
[ -n "$user_pass" ] && echo "$user_pass" >"${USER_FILE_PREFIX}/${SERVICE_NAME}_pass"
[ -n "$root_user_name" ] && echo "$root_user_name" >"${ROOT_FILE_PREFIX}/${SERVICE_NAME}_name"
[ -n "$root_user_pass" ] && echo "$root_user_pass" >"${ROOT_FILE_PREFIX}/${SERVICE_NAME}_pass"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# create needed dirs
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
[ -d "$RUN_DIR" ] || mkdir -p "$RUN_DIR"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow per init script usernames and passwords
__file_exists_with_content "${USER_FILE_PREFIX}/${SERVICE_NAME}_name" && user_name="$(<"${USER_FILE_PREFIX}/${SERVICE_NAME}_name")"
__file_exists_with_content "${USER_FILE_PREFIX}/${SERVICE_NAME}_pass" && user_pass="$(<"${USER_FILE_PREFIX}/${SERVICE_NAME}_pass")"
__file_exists_with_content "${ROOT_FILE_PREFIX}/${SERVICE_NAME}_name" && root_user_name="$(<"${ROOT_FILE_PREFIX}/${SERVICE_NAME}_name")"
__file_exists_with_content "${ROOT_FILE_PREFIX}/${SERVICE_NAME}_pass" && root_user_pass="$(<"${ROOT_FILE_PREFIX}/${SERVICE_NAME}_pass")"
__file_exists_with_content "${USER_FILE_PREFIX}/db_pass_user" && DATABASE_PASS_NORMAL="$(<"${USER_FILE_PREFIX}/db_pass_user")"
__file_exists_with_content "${ROOT_FILE_PREFIX}/db_pass_root" && DATABASE_PASS_ROOT="$(<"${ROOT_FILE_PREFIX}/db_pass_root")"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set hostname for script
sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
__create_service_env
# - - - - - - - - - - - - - - - - - - - - - - - - -
# pre-run function
__execute_prerun
# - - - - - - - - - - - - - - - - - - - - - - - - -
# create user if needed
__create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "${WORK_DIR:-/home/$SERVICE_USER}" "${SERVICE_UID:-}" "${SERVICE_GID:-}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Modify user if needed
__set_user_group_id $SERVICE_USER ${SERVICE_UID:-} ${SERVICE_GID:-}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Create base directories
__setup_directories
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set switch user command
__switch_to_user
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Initialize the home/working dir
__init_working_dir
# - - - - - - - - - - - - - - - - - - - - - - - - -
# show init message
__pre_message
# - - - - - - - - - - - - - - - - - - - - - - - - -
#
__initialize_db_users
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Initialize ssl
__update_ssl_conf
__update_ssl_certs
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set permissions in ${USER_FILE_PREFIX} and ${ROOT_FILE_PREFIX}
__run_secure_function
# - - - - - - - - - - - - - - - - - - - - - - - - -
__run_precopy
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Replace variables
__initialize_replace_variables "$CONF_DIR" "$ADDITIONAL_CONFIG_DIRS" "$WWW_ROOT_DIR"
# - - - - - - - - - - - - - - - - - - - - - - - - -
#
__initialize_database
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Updating config files
__update_conf_files
# - - - - - - - - - - - - - - - - - - - - - - - - -
# run the pre execute commands
__pre_execute
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set permissions
__fix_permissions "$SERVICE_USER" "$SERVICE_GROUP"
# - - - - - - - - - - - - - - - - - - - - - - - - -
#
__run_pre_execute_checks 2>/dev/stderr | tee -a -p "/data/logs/entrypoint.log" "/data/logs/init.txt" || return 20
# - - - - - - - - - - - - - - - - - - - - - - - - -
__run_start_script 2>>/dev/stderr | tee -p -a "/data/logs/entrypoint.log"
errorCode=${PIPESTATUS[0]}
if [ -n "$EXEC_CMD_BIN" ]; then
  if [ "$errorCode" -eq 0 ]; then
    SERVICE_EXIT_CODE=0
    SERVICE_IS_RUNNING="yes"
  else
    SERVICE_EXIT_CODE=$errorCode
    SERVICE_IS_RUNNING="${SERVICE_IS_RUNNING:-no}"
    if [ ! -s "$SERVICE_PID_FILE" ]; then
      rm -Rf "$SERVICE_PID_FILE"
    fi
  fi
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# start the post execute function in background
__post_execute 2>"/dev/stderr" | tee -p -a "/data/logs/init.txt" &
# - - - - - - - - - - - - - - - - - - - - - - - - -
__script_exit $SERVICE_EXIT_CODE

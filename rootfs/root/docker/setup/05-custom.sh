#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609030601-git
# @@Author           :  CasjaysDev
# @@Contact          :  CasjaysDev <docker-admin@casjaysdev.pro>
# @@License          :  MIT
# @@Copyright        :  Copyright 2026 CasjaysDev
# @@Created          :  Sun May 24 11:58:45 AM EDT 2026
# @@File             :  05-custom.sh
# @@Description      :  script to run custom
# @@Changelog        :  newScript
# @@TODO             :  Refactor code
# @@Other            :  N/A
# @@Resource         :  N/A
# @@Terminal App     :  yes
# @@sudo/root        :  yes
# @@Template         :  templates/dockerfiles/init_scripts/05-custom.sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set bash options
set -o pipefail
[ "$DEBUGGER" = "on" ] && echo "Enabling debugging" && set -x$DEBUGGER_OPTIONS
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set env variables
VERSION="202609030601-git"
exitCode=0
apk add --no-cache ca-certificates 2>/dev/null || true
update-ca-certificates 2>/dev/null || true
FORGEJO_VERSION="${FORGEJO_VERSION:-latest}"
FORGEJO_BIN_FILE="/usr/local/bin/forgejo"
ACT_BIN_FILE="/usr/local/bin/act_runner"
ARCH="$(uname -m | tr '[:upper]' '[:lower]')"
case "$ARCH" in x86_64) ARCH="amd64" ;; aarch64) ARCH="arm64" ;; *) echo "$ARCH is not supported by this script" >&2 && exit 1 ;; esac
# Pinned fallback used when code.forgejo.org is unreachable from the build host
ACT_RUNNER_FALLBACK_VERSION="${ACT_RUNNER_FALLBACK_VERSION:-v13.1.0}"
# Fetch latest version tag from the forgejo-runner repo — 30s connect timeout
ACT_VERSIONS="$(curl -q --connect-timeout 30 --max-time 45 -LSsf \
  'https://code.forgejo.org/api/v1/repos/forgejo/runner/releases' \
  -H 'accept: application/json' 2>/dev/null | jq -r '.[].tag_name' | sort -Vr | head -n1)"
# Fall back to pinned version if API is unreachable
[ -z "$ACT_VERSIONS" ] && ACT_VERSIONS="$ACT_RUNNER_FALLBACK_VERSION" && echo "WARNING: code.forgejo.org unreachable, using act_runner $ACT_VERSIONS" >&2
# Fetch download URL from API; binary names use the version without leading 'v'
ACT_URL="$(curl -q --connect-timeout 30 --max-time 45 -LSsf \
  "https://code.forgejo.org/api/v1/repos/forgejo/runner/releases/tags/$ACT_VERSIONS" \
  -H 'accept: application/json' 2>/dev/null | jq -rc '.assets|.[]|.browser_download_url' | grep -E -- "linux-${ARCH}$")"
# If API parse yielded nothing, construct the direct download URL from the version
# Tag format: v13.1.0 → filename: forgejo-runner-13.1.0-linux-amd64 (strip leading 'v')
ACT_VER_PLAIN="${ACT_VERSIONS#v}"
[ -z "$ACT_URL" ] && ACT_URL="https://code.forgejo.org/forgejo/runner/releases/download/${ACT_VERSIONS}/forgejo-runner-${ACT_VER_PLAIN}-linux-${ARCH}"
if [ -z "$FORGEJO_VERSION" ] || [ "$FORGEJO_VERSION" = "latest" ] || [ "$FORGEJO_VERSION" = "current" ]; then
	_latest_url="$(curl -4sfL -o /dev/null -w '%{url_effective}' https://code.forgejo.org/forgejo/forgejo/releases/latest 2>/dev/null)"
	FORGEJO_VERSION="$(printf '%s\n' "$_latest_url" | grep -oE -- '[0-9]+\.[0-9]+\.[0-9]+')"
fi
if [ -z "$FORGEJO_VERSION" ]; then
	echo "Failed to resolve forgejo latest version from code.forgejo.org" >&2
	exit 1
fi
FORGEJO_URL="https://code.forgejo.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-${ARCH}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Predefined actions
echo "Downloading forgejo from $FORGEJO_URL"
if curl -4 -q -LSsf --retry 5 --retry-delay 10 --retry-all-errors "$FORGEJO_URL" -o "/tmp/forgejo.$$"; then
	mv -f "/tmp/forgejo.$$" "$FORGEJO_BIN_FILE"
	echo "forgejo has been installed to: $FORGEJO_BIN_FILE"
	chmod +x "$FORGEJO_BIN_FILE"
	if [ -d "/etc/sudoers.d" ]; then
		echo "root       ALL=(ALL)      NOPASSWD: ALL" >"/etc/sudoers.d/root"
		echo "git        ALL=(ALL)      NOPASSWD: ALL" >"/etc/sudoers.d/git"
		echo "docker     ALL=(ALL)      NOPASSWD: ALL" >"/etc/sudoers.d/docker"
	fi
else
	echo "Failed to download forgejo" >&2
	exitCode=$((exitCode + 1))
fi
echo "Downloading act_runner from $ACT_URL"
if [ -z "$ACT_URL" ]; then
	echo "Failed to resolve act_runner download URL" >&2
	exitCode=$((exitCode + 1))
elif curl -q -LSsf --retry 5 --retry-delay 10 --retry-all-errors "$ACT_URL" -o "/tmp/act_runner.$$"; then
	mv -f "/tmp/act_runner.$$" "$ACT_BIN_FILE"
	echo "act_runner has been installed to: $ACT_BIN_FILE"
	chmod +x "$ACT_BIN_FILE"
else
	echo "Failed to download act_runner" >&2
	exitCode=$((exitCode + 1))
fi
[ -x "$ACT_BIN_FILE" ] && [ -x "$FORGEJO_BIN_FILE" ] && exitCode=0
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Main script

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set the exit code
#exitCode=$?
# - - - - - - - - - - - - - - - - - - - - - - - - -
exit "$exitCode"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
# - - - - - - - - - - - - - - - - - - - - - - - - -

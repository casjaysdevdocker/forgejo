#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Hand-crafted runtime env fragment (never touched by gen-dockerfile).
# Sourced by /usr/local/bin/entrypoint.sh on every invocation, including
# the Docker HEALTHCHECK probe.
#
# Without this, the healthcheck only checks that the forgejo process is
# running and that its port shows up in the container's own netstat
# output — both of which can be true for a brief window before the web
# server is actually accepting and answering HTTP requests, so Docker
# reports "healthy" before external clients can reliably connect (seen
# right after `docker restart`; logged in TODO.AI.md).
#
# Setting HEALTH_ENDPOINTS makes the same healthcheck also require a
# real successful HTTP response from Forgejo itself, closing that race.
# - - - - - - - - - - - - - - - - - - - - - - - - -
HEALTH_ENDPOINTS="${HEALTH_ENDPOINTS:-http://127.0.0.1:${FORGEJO_PORT:-80}/api/healthz}"

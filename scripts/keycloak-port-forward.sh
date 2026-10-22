#!/bin/bash
# Manage a retrying kubectl port-forward: localhost:18082 -> svc/keycloak:80
# (namespace keycloak).
#
# The keycloak Terraform provider (terraform/keycloak-sso.tf) runs on this
# machine and cannot reach in-cluster addresses, so terraform plan/apply need
# this forward. It is started/stopped automatically by scripts/setup.sh and
# the make tf-plan/tf-apply targets; this script exists so the logic lives in
# one place.
#
# The forward retries until the service exists (fresh clusters create it
# during terraform apply) and survives pod restarts.
#
# Usage: keycloak-port-forward.sh {start|stop|status}

set -u

PORT=18082
NAMESPACE=keycloak
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${REPO_ROOT}/terraform/state"
PIDFILE="${STATE_DIR}/keycloak-pf.pid"
LOOPPIDFILE="${STATE_DIR}/keycloak-pf-loop.pid"
LOG="${STATE_DIR}/keycloak-pf.log"
mkdir -p "$STATE_DIR"

pid_alive() {
    [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null
}

start() {
    if pid_alive "$LOOPPIDFILE"; then
        echo "keycloak port-forward already running (loop pid $(cat "$LOOPPIDFILE"))"
        return 0
    fi
    (
        while :; do
            kubectl -n "$NAMESPACE" port-forward svc/keycloak "${PORT}:80" >>"$LOG" 2>&1 &
            echo $! > "$PIDFILE"
            wait
            # Service missing (fresh cluster) or kubectl hiccup: retry.
            sleep 2
        done
    ) &
    echo $! > "$LOOPPIDFILE"
    echo "keycloak port-forward starting (loop pid $(cat "$LOOPPIDFILE")): http://localhost:${PORT} -> ${NAMESPACE}/keycloak:80 (log: ${LOG})"
}

stop() {
    if pid_alive "$PIDFILE"; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
    fi
    if pid_alive "$LOOPPIDFILE"; then
        kill "$(cat "$LOOPPIDFILE")" 2>/dev/null || true
    fi
    # Last resort: catch any stray forward with exactly our port mapping.
    pkill -f "port-forward svc/keycloak ${PORT}:80" 2>/dev/null || true
    rm -f "$PIDFILE" "$LOOPPIDFILE"
    echo "keycloak port-forward stopped"
}

status() {
    if pid_alive "$LOOPPIDFILE"; then
        echo "running (loop pid $(cat "$LOOPPIDFILE")): http://localhost:${PORT} -> ${NAMESPACE}/keycloak:80"
    else
        echo "not running"
    fi
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "usage: $0 {start|stop|status}" >&2; exit 2 ;;
esac

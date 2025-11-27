#!/usr/bin/env bash
# Helper to manage a standalone PostgreSQL container on the NAS (outside Kubernetes).
# Actions: start|deploy, backup, status, restart, stop.

set -euo pipefail

ACTION="${1:-status}"

DOCKER_BIN="${DOCKER_BIN:-}"
PG_CONTAINER_NAME="${PG_CONTAINER_NAME:-nas-postgres}"
PG_IMAGE="${PG_IMAGE:-postgres:16}"
PG_DATA_DIR="${PG_DATA_DIR:-/share/Public/postgres-data}"
PG_BACKUP_DIR="${PG_BACKUP_DIR:-/share/Public/postgres-backups}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${POSTGRES_USER:-postgres}"
PG_PASSWORD="${POSTGRES_PASSWORD:-}"

fail() {
  echo "Error: $*" >&2
  exit 1
}

ensure_runtime() {
  if [[ -n "${DOCKER_BIN:-}" ]]; then
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    DOCKER_BIN="docker"
  elif command -v podman >/dev/null 2>&1; then
    DOCKER_BIN="podman"
  else
    fail "docker/podman not found on NAS."
  fi
}

ensure_password() {
  [[ -n "$PG_PASSWORD" ]] || fail "Define POSTGRES_PASSWORD in the environment or secrets."
}

ensure_dirs() {
  mkdir -p "$PG_DATA_DIR" "$PG_BACKUP_DIR"
}

container_exists() {
  ensure_runtime
  $DOCKER_BIN ps -a --format '{{.Names}}' | grep -q "^${PG_CONTAINER_NAME}$"
}

container_running() {
  ensure_runtime
  $DOCKER_BIN ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER_NAME}$"
}

start_postgres() {
  ensure_runtime
  ensure_dirs

  if container_exists; then
    $DOCKER_BIN start "$PG_CONTAINER_NAME" >/dev/null
    echo "PostgreSQL container already exists. Started if it was stopped."
  else
    ensure_password
    echo "Creating PostgreSQL container ${PG_CONTAINER_NAME} with data dir ${PG_DATA_DIR}..."
    $DOCKER_BIN run -d \
      --name "$PG_CONTAINER_NAME" \
      --restart unless-stopped \
      -p "${PG_PORT}:5432" \
      -v "${PG_DATA_DIR}:/var/lib/postgresql/data" \
      -e POSTGRES_PASSWORD="$PG_PASSWORD" \
      -e POSTGRES_USER="$PG_USER" \
      "$PG_IMAGE"
    echo "Container created."
  fi

  echo "PostgreSQL available on port ${PG_PORT} (host network). Data: ${PG_DATA_DIR}"
}

backup_postgres() {
  ensure_runtime
  ensure_password
  ensure_dirs

  if ! container_running; then
    if container_exists; then
      $DOCKER_BIN start "$PG_CONTAINER_NAME" >/dev/null
    else
      fail "Container ${PG_CONTAINER_NAME} is not running. Run start first."
    fi
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  backup_file="${PG_BACKUP_DIR}/postgres-${ts}.sql"
  echo "Creating backup at ${backup_file}..."
  $DOCKER_BIN exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER_NAME" \
    pg_dumpall -U "$PG_USER" >"$backup_file"
  echo "Backup completed."
}

status_postgres() {
  ensure_runtime
  if container_running; then
    $DOCKER_BIN ps --filter "name=${PG_CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  elif container_exists; then
    echo "Container ${PG_CONTAINER_NAME} exists but is stopped."
  else
    echo "Container ${PG_CONTAINER_NAME} not found."
  fi
}

restart_postgres() {
  ensure_runtime
  container_exists || fail "Container ${PG_CONTAINER_NAME} does not exist. Run start first."
  $DOCKER_BIN restart "$PG_CONTAINER_NAME" >/dev/null
  echo "Container ${PG_CONTAINER_NAME} restarted."
}

stop_postgres() {
  ensure_runtime
  container_running || fail "Container ${PG_CONTAINER_NAME} is not running."
  $DOCKER_BIN stop "$PG_CONTAINER_NAME" >/dev/null
  echo "Container ${PG_CONTAINER_NAME} stopped."
}

case "$ACTION" in
  start|deploy)
    start_postgres
    ;;
  backup)
    backup_postgres
    ;;
  status)
    status_postgres
    ;;
  restart)
    restart_postgres
    ;;
  stop)
    stop_postgres
    ;;
  *)
    fail "Usage: $0 {start|deploy|backup|status|restart|stop}"
    ;;
esac

#!/usr/bin/env bash
# Backup helper for MinIO data directory on VPS.
# Actions: backup, prune, status.

set -euo pipefail

ACTION="${1:-status}"

MINIO_DATA_DIR="${MINIO_DATA_DIR:-/srv/minio-data}"
MINIO_BACKUP_DIR="${MINIO_BACKUP_DIR:-${HOME}/minio-backups}"
MINIO_RETENTION_DAYS="${MINIO_RETENTION_DAYS:-7}"
MINIO_BACKUP_FORMAT="${MINIO_BACKUP_FORMAT:-tar.gz}"

fail() {
  echo "Error: $*" >&2
  exit 1
}

ensure_dirs() {
  mkdir -p "$MINIO_BACKUP_DIR"
}

validate_inputs() {
  [[ -d "$MINIO_DATA_DIR" ]] || fail "MinIO data directory not found: $MINIO_DATA_DIR"
  [[ "$MINIO_RETENTION_DAYS" =~ ^[0-9]+$ ]] || fail "MINIO_RETENTION_DAYS must be numeric."
  [[ "$MINIO_BACKUP_FORMAT" == "tar.gz" ]] || fail "Unsupported MINIO_BACKUP_FORMAT: $MINIO_BACKUP_FORMAT"
}

backup_minio() {
  ensure_dirs
  validate_inputs

  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local backup_file="${MINIO_BACKUP_DIR}/minio-data-${ts}.tar.gz"

  echo "Creating MinIO snapshot backup at ${backup_file}..."
  tar -C "$(dirname "$MINIO_DATA_DIR")" -czf "$backup_file" "$(basename "$MINIO_DATA_DIR")"

  [[ -s "$backup_file" ]] || fail "Backup file is empty: ${backup_file}"
  # Basic archive integrity check.
  tar -tzf "$backup_file" >/dev/null

  echo "MinIO backup completed: ${backup_file}"
  prune_backups
}

prune_backups() {
  ensure_dirs
  [[ "$MINIO_RETENTION_DAYS" =~ ^[0-9]+$ ]] || fail "MINIO_RETENTION_DAYS must be numeric."
  local mtime_keep="$((MINIO_RETENTION_DAYS - 1))"
  if (( mtime_keep < 0 )); then
    mtime_keep=0
  fi

  echo "Pruning MinIO backups older than ${MINIO_RETENTION_DAYS} day(s) in ${MINIO_BACKUP_DIR}..."
  find "$MINIO_BACKUP_DIR" -maxdepth 1 -type f -name 'minio-data-*.tar.gz' -mtime "+${mtime_keep}" -print -delete || true
  echo "Prune completed."
}

status_backups() {
  ensure_dirs
  echo "MinIO data dir: ${MINIO_DATA_DIR}"
  echo "MinIO backup dir: ${MINIO_BACKUP_DIR}"
  echo "Retention days: ${MINIO_RETENTION_DAYS}"
  echo "Backup format: ${MINIO_BACKUP_FORMAT}"
  echo "Disk usage:"
  du -sh "$MINIO_DATA_DIR" "$MINIO_BACKUP_DIR" 2>/dev/null || true
  echo "Latest backups:"
  ls -1t "$MINIO_BACKUP_DIR"/minio-data-*.tar.gz 2>/dev/null | head -n 10 || true
}

case "$ACTION" in
  backup)
    backup_minio
    ;;
  prune)
    prune_backups
    ;;
  status)
    status_backups
    ;;
  *)
    fail "Usage: $0 {backup|prune|status}"
    ;;
esac

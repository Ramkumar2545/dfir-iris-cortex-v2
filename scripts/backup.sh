#!/usr/bin/env bash
# ============================================================
# backup.sh — Backup Docker volumes (IRIS DB + Cortex ES data)
#
# Usage:
#   bash scripts/backup.sh                      (timestamped)
#   bash scripts/backup.sh --tag my-label       (custom tag)
#   bash scripts/backup.sh --restore 20260430   (restore)
# ============================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." ; pwd)"
BACKUP_BASE="${PROJECT_DIR}/backups"
TAG="$(date +%Y%m%d-%H%M%S)"
RESTORE_TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)     TAG="$2"; shift 2 ;;
    --restore) RESTORE_TAG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ── RESTORE ───────────────────────────────────────────────────
if [ -n "${RESTORE_TAG}" ]; then
  RESTORE_DIR="${BACKUP_BASE}/${RESTORE_TAG}"
  [ -d "${RESTORE_DIR}" ] || { echo "Backup not found: ${RESTORE_DIR}"; exit 1; }
  info "Restoring from ${RESTORE_DIR}..."
  info "Stopping containers..."
  cd "${PROJECT_DIR}" && docker compose down

  for VOL in dfir-iris-cortex-v2_db_data dfir-iris-cortex-v2_cortex_es_data; do
    TARBALL="${RESTORE_DIR}/${VOL}.tar.gz"
    if [ -f "${TARBALL}" ]; then
      info "Restoring volume: ${VOL}"
      docker volume rm "${VOL}" 2>/dev/null || true
      docker volume create "${VOL}"
      docker run --rm -v "${VOL}:/data" -v "${RESTORE_DIR}:/backup" \
        alpine tar xzf "/backup/${VOL}.tar.gz" -C /data
      ok "Restored ${VOL}"
    else
      warn "${TARBALL} not found — skipping"
    fi
  done

  info "Restarting stack..."
  docker compose up -d
  ok "Restore complete from ${RESTORE_TAG}"
  exit 0
fi

# ── BACKUP ────────────────────────────────────────────────────
BACKUP_DIR="${BACKUP_BASE}/${TAG}"
mkdir -p "${BACKUP_DIR}"
info "Backing up to ${BACKUP_DIR}..."

cd "${PROJECT_DIR}"

# IRIS PostgreSQL dump
info "Dumping IRIS PostgreSQL..."
DB_USER=$(grep '^POSTGRES_USER=' .env | cut -d= -f2)
DB_NAME=$(grep '^POSTGRES_DB='   .env | cut -d= -f2)
docker exec iriswebapp_db pg_dump -U "${DB_USER}" "${DB_NAME}" \
  | gzip > "${BACKUP_DIR}/iris_pg_dump.sql.gz"
ok "IRIS DB → iris_pg_dump.sql.gz"

# Cortex ES snapshot (volume-level)
for VOL in dfir-iris-cortex-v2_db_data dfir-iris-cortex-v2_cortex_es_data; do
  if docker volume inspect "${VOL}" &>/dev/null; then
    info "Backing up volume: ${VOL}"
    docker run --rm \
      -v "${VOL}:/data:ro" \
      -v "${BACKUP_DIR}:/backup" \
      alpine tar czf "/backup/${VOL}.tar.gz" -C /data .
    ok "${VOL} → ${VOL}.tar.gz"
  else
    warn "Volume ${VOL} not found — skipping"
  fi
done

# Manifest
cat > "${BACKUP_DIR}/manifest.txt" <<EOF
Backup tag   : ${TAG}
Date         : $(date -u '+%Y-%m-%d %H:%M:%S UTC')
IRIS version : $(grep '^IRIS_VERSION=' .env | cut -d= -f2)
Cortex       : $(grep '^CORTEX_VERSION=' .env | cut -d= -f2)
ES           : $(grep '^ES_VERSION=' .env | cut -d= -f2)
EOF

ok "Backup complete: ${BACKUP_DIR}"
du -sh "${BACKUP_DIR}"

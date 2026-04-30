#!/usr/bin/env bash
# ============================================================
# update.sh — Upgrade IRIS / Cortex / Elasticsearch versions
#
# Usage:
#   bash scripts/update.sh                     (reads .env)
#   IRIS_VERSION=v2.5.0 bash scripts/update.sh (one-shot)
#
# What it does:
#   1. Reads IRIS_VERSION, CORTEX_VERSION, ES_VERSION from .env
#   2. Pulls new images
#   3. Recreates containers (zero-data-loss — volumes preserved)
#   4. Re-installs iris_cortex_analyzer_module
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.."; pwd)"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

[ -f "${PROJECT_DIR}/.env" ] || err ".env not found. Run setup.sh first."

cd "${PROJECT_DIR}"

# ── Override from environment if provided ─────────────────────
[ -n "${IRIS_VERSION:-}"   ] && sed -i "s|^IRIS_VERSION=.*|IRIS_VERSION=${IRIS_VERSION}|"     .env
[ -n "${CORTEX_VERSION:-}" ] && sed -i "s|^CORTEX_VERSION=.*|CORTEX_VERSION=${CORTEX_VERSION}|" .env
[ -n "${ES_VERSION:-}"     ] && sed -i "s|^ES_VERSION=.*|ES_VERSION=${ES_VERSION}|"           .env

# ── Read current versions ──────────────────────────────────────
IRIS_VER=$(grep   '^IRIS_VERSION='   .env | cut -d= -f2)
CORTEX_VER=$(grep '^CORTEX_VERSION=' .env | cut -d= -f2)
ES_VER=$(grep     '^ES_VERSION='     .env | cut -d= -f2)

info "═══════════════════════════════════════════════════"
info " Upgrading stack:"
info "   IRIS    : ${IRIS_VER}"
info "   Cortex  : ${CORTEX_VER}"
info "   ES      : ${ES_VER}"
info "═══════════════════════════════════════════════════"

# ── Warn about ES version ──────────────────────────────────────
ES_MAJOR=$(echo "${ES_VER}" | cut -d. -f1)
if [ "${ES_MAJOR}" -lt 8 ] 2>/dev/null; then
  err "Cortex 4.x requires Elasticsearch 8.x — ES_VERSION=${ES_VER} is NOT supported!"
fi

# ── Backup before upgrade ──────────────────────────────────────
info "Creating pre-upgrade backup..."
bash "${SCRIPT_DIR}/backup.sh" --tag "pre-upgrade-$(date +%Y%m%d-%H%M%S)" || \
  warn "Backup failed — continuing anyway"

# ── Pull new images ───────────────────────────────────────────
info "Pulling new images..."
docker compose pull
ok "Images pulled"

# ── Restart with new images ───────────────────────────────────
info "Recreating containers..."
docker compose up -d --force-recreate
ok "Containers recreated"

# ── Re-install module ─────────────────────────────────────────
info "Waiting 30s for containers to stabilise..."
sleep 30
info "Re-installing iris_cortex_analyzer_module..."
bash "${SCRIPT_DIR}/install_module.sh"

ok "═══════════════════════════════════════════════════"
ok " Upgrade complete!"
ok "═══════════════════════════════════════════════════"

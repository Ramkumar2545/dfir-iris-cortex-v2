#!/usr/bin/env bash
# ============================================================
# install_module.sh — Build + install iris_cortex_analyzer_module
# Run AFTER: docker compose up -d  (all containers healthy)
#
# Uses /opt/venv/bin/pip inside IRIS containers
# (bare pip hits system Python — module invisible to IRIS)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.."; pwd)"
MODULE_DIR="${PROJECT_DIR}/iris_module"
VENV_PIP="/opt/venv/bin/pip"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

info "═══════════════════════════════════════════════════"
info " Installing iris_cortex_analyzer_module"
info "═══════════════════════════════════════════════════"

# ── 1. Build ──────────────────────────────────────────────────
info "[1/5] Building module from ${MODULE_DIR}..."
# Ensure build tool is available
python3 -m pip install --quiet --upgrade build 2>/dev/null || true

cd "${MODULE_DIR}"
python3 -m build --sdist --outdir dist/ 2>&1 | tail -5

TARBALL=$(ls "${MODULE_DIR}/dist"/iris_cortex_analyzer_module-*.tar.gz \
          | sort -V | tail -1)
ok "Built: $(basename ${TARBALL})"
cd - > /dev/null

# ── 2. Install into app container ─────────────────────────────
info "[2/5] Installing into iriswebapp_app..."
docker cp "${TARBALL}" iriswebapp_app:/tmp/
docker exec iriswebapp_app \
  "${VENV_PIP}" install --quiet "/tmp/$(basename ${TARBALL})"
ok "Installed in iriswebapp_app"

# ── 3. Install into worker container ──────────────────────────
info "[3/5] Installing into iriswebapp_worker..."
docker cp "${TARBALL}" iriswebapp_worker:/tmp/
docker exec iriswebapp_worker \
  "${VENV_PIP}" install --quiet "/tmp/$(basename ${TARBALL})"
ok "Installed in iriswebapp_worker"

# ── 4. Restart ────────────────────────────────────────────────
info "[4/5] Restarting app + worker..."
docker restart iriswebapp_app iriswebapp_worker
ok "Containers restarted"

# ── 5. Verify ─────────────────────────────────────────────────
info "[5/5] Waiting 20s then verifying..."
sleep 20

docker exec iriswebapp_app    "${VENV_PIP}" show iris_cortex_analyzer_module \
  > /dev/null && ok "Verified in iriswebapp_app" \
  || err "NOT found in app"

docker exec iriswebapp_worker "${VENV_PIP}" show iris_cortex_analyzer_module \
  > /dev/null && ok "Verified in iriswebapp_worker" \
  || err "NOT found in worker"

info ""
ok  " Module installation complete!"
info " "
info " Next: IRIS UI → Advanced → Modules → Add Module"
info "   Module name : iris_cortex_analyzer_module"
info "   cortex_url  : http://cortex:9001"
info "   cortex_api_key : <paste key from Cortex UI>"

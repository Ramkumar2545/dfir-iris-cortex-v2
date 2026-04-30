#!/usr/bin/env bash
# ============================================================
# install_module.sh — Build + install iris_cortex_analyzer_module
#
# Run AFTER: docker compose up -d  (all containers healthy)
# Uses /opt/venv/bin/pip inside IRIS containers
# (bare pip hits system Python — module invisible to IRIS)
#
# NOTE: IRIS source patches (updater.py, tasks.py, module_handler.py,
# util.py) are applied automatically at container boot via Docker Compose
# volume bind-mounts declared in docker-compose.yml. No manual patching
# step is needed here.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}"); pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.."; pwd)"
MODULE_DIR="${PROJECT_DIR}/iris_module"
VENV_PIP="/opt/venv/bin/pip"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

info "═══════════════════════════════════════════════════"
info " IRIS Cortex Integration — Module Install"
info "═══════════════════════════════════════════════════"
info "Patches are already active via docker-compose.yml volume mounts."
info ""

# ── 1. Ensure python3 build module is available on HOST ──────────
info "[1/4] Checking python3 build module..."
if ! python3 -m build --version &>/dev/null; then
  warn "python3 'build' module not found — installing now..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y -qq python3-build 2>/dev/null \
      || pip3 install --quiet build
  else
    pip3 install --quiet build
  fi
  ok "python3 build module installed"
else
  ok "python3 build module already available"
fi

# ── 2. Build ────────────────────────────────────────────────────
info "[2/4] Building module from ${MODULE_DIR}..."
cd "${MODULE_DIR}"
python3 -m build --sdist --outdir dist/ 2>&1 | tail -5

TARBALL=$(ls "${MODULE_DIR}/dist"/iris_cortex_analyzer_module-*.tar.gz \
          | sort -V | tail -1)
ok "Built: $(basename ${TARBALL})"
cd - > /dev/null

# ── 3. Install into app + worker containers ──────────────────────
info "[3/4] Installing into iriswebapp_app..."
docker cp "${TARBALL}" iriswebapp_app:/tmp/
docker exec iriswebapp_app \
  "${VENV_PIP}" install --quiet "/tmp/$(basename ${TARBALL})"
ok "Installed in iriswebapp_app"

info "[3/4] Installing into iriswebapp_worker..."
docker cp "${TARBALL}" iriswebapp_worker:/tmp/
docker exec iriswebapp_worker \
  "${VENV_PIP}" install --quiet "/tmp/$(basename ${TARBALL})"
ok "Installed in iriswebapp_worker"

# ── 4. Restart + Verify ──────────────────────────────────────────
info "[4/4] Restarting app + worker then verifying..."
docker restart iriswebapp_app iriswebapp_worker
sleep 20

docker exec iriswebapp_app    "${VENV_PIP}" show iris_cortex_analyzer_module \
  > /dev/null && ok "Verified in iriswebapp_app" \
  || err "NOT found in iriswebapp_app"

docker exec iriswebapp_worker "${VENV_PIP}" show iris_cortex_analyzer_module \
  > /dev/null && ok "Verified in iriswebapp_worker" \
  || err "NOT found in iriswebapp_worker"

info ""
ok  " Full install complete!"
info " "
info " Next: IRIS UI → Advanced → Modules → Add Module"
info "   Module name   : iris_cortex_analyzer_module"
info "   cortex_url    : http://cortex:9001"
info "   cortex_api_key: <paste key from Cortex UI>"

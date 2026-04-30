#!/usr/bin/env bash
# =============================================================
# apply_patches.sh — Copy patched IRIS source files into
# running iriswebapp_app and iriswebapp_worker containers.
#
# Run BEFORE install_module.sh (or call it via install_module.sh)
# Containers must already be up: docker compose up -d
#
# Patches fix four IRIS v2.4.x bugs:
#   1. module_handler.py — TypeError in task_hook_wrapper bytes encoding
#   2. tasks.py          — RuntimeError: Flask app context in ForkPoolWorker
#   3. updater.py        — TypeError: Blinker keyword dispatch (sender=None)
#   4. util.py           — TypeError: SECRET_KEY bytes in hmac_sign/verify
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$(cd "${SCRIPT_DIR}/../patches" && pwd)"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

info "═══════════════════════════════════════════════════"
info " Applying IRIS source patches"
info "═══════════════════════════════════════════════════"

# Verify containers are running
for CTR in iriswebapp_app iriswebapp_worker; do
  if ! docker ps --format '{{.Names}}' | grep -q "^${CTR}$"; then
    err "Container '${CTR}' is not running. Run: docker compose up -d"
  fi
done
ok "Both containers are running"

# ── Patch map: source file → destination path inside container ──
declare -A PATCH_MAP=(
  ["${PATCHES_DIR}/module_handler.py"]="/iriswebapp/app/iris_engine/module_handler/module_handler.py"
  ["${PATCHES_DIR}/tasks.py"]="/iriswebapp/app/iris_engine/tasking/tasks.py"
  ["${PATCHES_DIR}/updater.py"]="/iriswebapp/app/iris_engine/updater/updater.py"
  ["${PATCHES_DIR}/util.py"]="/iriswebapp/app/util.py"
)

apply_to_container() {
  local CTR="$1"
  info "── Patching container: ${CTR} ──"
  for SRC in "${!PATCH_MAP[@]}"; do
    DST="${PATCH_MAP[$SRC]}"
    FNAME="$(basename "${SRC}")"
    docker cp "${SRC}" "${CTR}:${DST}" \
      && ok "  ${FNAME} → ${DST}" \
      || err "  Failed to copy ${FNAME} into ${CTR}"
  done
}

apply_to_container "iriswebapp_app"
apply_to_container "iriswebapp_worker"

ok ""
ok " All 4 patches applied to both containers"
info " Patches are NOT persistent — re-run after container recreation."
info " Tip: call this script from install_module.sh (step 0) to automate."

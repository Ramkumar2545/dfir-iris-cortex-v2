#!/usr/bin/env bash
# ============================================================
# setup.sh — Universal first-time setup
# Supports: Ubuntu 22.04/24.04/25.04/26.04 + Debian 11/12
#           RHEL/Rocky/Alma/CentOS Stream 8,9 + Fedora 39-41+
#           Amazon Linux 2, 2023
#
# Steps:
#   1. Detect OS + install packages
#   2. Install Docker CE (if missing)
#   3. Set vm.max_map_count for Elasticsearch
#   4. Create runtime dirs (cortex/jobs, cortex/config, certs)
#   5. Generate self-signed TLS certificate
#   6. Auto-generate .env from .env.example (all secrets)
#   7. Inject PROJECT_ROOT into .env for docker-compose
#   8. Validate critical .env keys
#   9. Enable pgcrypto in PostgreSQL
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.."; pwd)"

source "${SCRIPT_DIR}/detect_os.sh"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "Please run as root: sudo bash scripts/setup.sh"

cd "${PROJECT_DIR}"

info "═══════════════════════════════════════════════════"
info " DFIR-IRIS + Cortex — Universal Setup v2"
info " OS: ${OS_ID} ${OS_VERSION} (${OS_FAMILY})"
info " Project root: ${PROJECT_DIR}"
info "═══════════════════════════════════════════════════"

# ── 1. OS packages ────────────────────────────────────────────
info "[1/9] Installing OS packages..."

if [ "${OS_FAMILY}" = "debian" ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq \
    curl wget ca-certificates gnupg lsb-release \
    openssl python3 python3-pip python3-venv python3-build \
    git build-essential libffi-dev libssl-dev

elif [ "${OS_FAMILY}" = "rpm" ]; then
  ${PKG_MGR} install -y \
    curl wget ca-certificates \
    openssl python3 python3-pip python3-devel \
    git gcc make libffi-devel openssl-devel
  python3 -m pip install --quiet --upgrade pip build 2>/dev/null || true
fi
ok "OS packages installed"

# ── 2. Docker ─────────────────────────────────────────────────
info "[2/9] Docker CE check / install..."
bash "${SCRIPT_DIR}/install_docker.sh"
ok "Docker ready"

# ── 3. vm.max_map_count ────────────────────────────────────────
info "[3/9] Setting vm.max_map_count=262144 (Elasticsearch requirement)"
sysctl -w vm.max_map_count=262144
if ! grep -q 'vm.max_map_count' /etc/sysctl.conf 2>/dev/null; then
  echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
fi
ok "vm.max_map_count=262144 (persistent)"

# ── 4. Runtime directories ────────────────────────────────────
info "[4/9] Creating runtime directories..."

# cortex/jobs must exist as an absolute host path so that Docker can
# bind-mount it into analyzer sub-containers spawned by Cortex.
# The path is saved as PROJECT_ROOT in .env (step 7).
info "  Setting up Cortex job directories..."
mkdir -p "${PROJECT_DIR}/cortex/jobs"
chmod -R 777 "${PROJECT_DIR}/cortex/jobs"
ok "  Cortex job directory configured at: ${PROJECT_DIR}/cortex/jobs"

mkdir -p \
  "${PROJECT_DIR}/cortex/config" \
  "${PROJECT_DIR}/cortex/logs" \
  "${PROJECT_DIR}/cortex/neurons"
chmod 777 "${PROJECT_DIR}/cortex/logs"
chmod 755 "${PROJECT_DIR}/cortex/config" "${PROJECT_DIR}/cortex/neurons"

mkdir -p \
  "${PROJECT_DIR}/certificates/web_certificates" \
  "${PROJECT_DIR}/certificates/rootCA" \
  "${PROJECT_DIR}/certificates/ldap"
touch "${PROJECT_DIR}/certificates/ldap/.keep"
ok "All runtime directories ready"

# ── 5. TLS certificates ──────────────────────────────────────
info "[5/9] Generating self-signed TLS certificate (10 years)"
CERT_PATH="${PROJECT_DIR}/certificates/web_certificates"
if [ ! -f "${CERT_PATH}/iris.crt" ]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout "${CERT_PATH}/iris.key" \
    -out    "${CERT_PATH}/iris.crt" \
    -subj   "/C=IN/ST=TN/L=Chennai/O=DFIR/CN=iris.local" 2>/dev/null
  cp "${CERT_PATH}/iris.crt" \
     "${PROJECT_DIR}/certificates/rootCA/irisRootCACert.pem"
  chmod 644 "${CERT_PATH}/iris.key" "${CERT_PATH}/iris.crt"
  chmod 644 "${PROJECT_DIR}/certificates/rootCA/irisRootCACert.pem"
  ok "TLS cert generated"
else
  ok "TLS cert already exists — skipping"
fi

# ── 6. .env generation ────────────────────────────────────────
info "[6/9] Setting up .env..."
if [ ! -f "${PROJECT_DIR}/.env" ]; then
  cp "${PROJECT_DIR}/.env.example" "${PROJECT_DIR}/.env"

  SECRET=$(python3  -c "import secrets; print(secrets.token_hex(32))")
  SALT=$(python3    -c "import secrets; print(secrets.token_hex(16))")
  DBPASS="IrisDB$(openssl rand -hex 8)"
  DBADMIN="IrisAdm$(openssl rand -hex 8)"
  CORTEX_SECRET=$(openssl rand -base64 48)

  sed -i "s|CHANGE_ME_secret_key_min_32_chars|${SECRET}|g"   "${PROJECT_DIR}/.env"
  sed -i "s|CHANGE_ME_password_salt|${SALT}|g"               "${PROJECT_DIR}/.env"
  sed -i "s|CHANGE_ME_db_password|${DBPASS}|g"               "${PROJECT_DIR}/.env"
  sed -i "s|CHANGE_ME_admin_password|${DBADMIN}|g"           "${PROJECT_DIR}/.env"
  sed -i "s|^DB_PASS=.*|DB_PASS=${DBPASS}|"                  "${PROJECT_DIR}/.env"
  sed -i "s|CHANGE_ME_cortex_secret_key|${CORTEX_SECRET}|g"  "${PROJECT_DIR}/.env"

  ok ".env created with auto-generated secrets"
  warn "Set CORTEX_API_KEY in .env after Cortex first-time setup"
else
  ok ".env already exists — skipping auto-generation"
fi

# ── 7. Inject PROJECT_ROOT into .env (docker-compose reads it) ────────
# CORTEX_DOCKER_JOB_DIR in docker-compose.yml expands to:
#   ${PROJECT_ROOT}/cortex/jobs
# which Cortex passes to spawned analyzer containers as their host path.
# Guard prevents duplicates on re-runs; sed updates if path changed.
info "[7/9] Writing PROJECT_ROOT to .env..."
if ! grep -q 'PROJECT_ROOT=' "${PROJECT_DIR}/.env" 2>/dev/null; then
  echo "PROJECT_ROOT=${PROJECT_DIR}" >> "${PROJECT_DIR}/.env"
else
  sed -i "s|^PROJECT_ROOT=.*|PROJECT_ROOT=${PROJECT_DIR}|" "${PROJECT_DIR}/.env"
fi
ok "PROJECT_ROOT=${PROJECT_DIR}"

# ── 8. Validate .env ───────────────────────────────────────────
info "[8/9] Validating .env keys..."
for KEY in SECRET_KEY SECURITY_PASSWORD_SALT DB_PASS IRIS_VERSION CORTEX_SECRET_KEY PROJECT_ROOT; do
  VAL=$(grep "^${KEY}=" "${PROJECT_DIR}/.env" | cut -d'=' -f2- || true)
  if [ -z "${VAL}" ] || echo "${VAL}" | grep -qi 'change_me'; then
    err "${KEY} is missing or still CHANGE_ME! Edit .env first."
  fi
  ok "  ${KEY} = ${VAL:0:40}..."
done

# ── 9. pgcrypto extension ──────────────────────────────────────
info "[9/9] Starting DB and enabling pgcrypto..."
docker compose up -d db
info "Waiting for DB to be healthy (up to 60s)..."
for i in $(seq 1 30); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' iriswebapp_db 2>/dev/null || echo 'starting')
  [ "${STATUS}" = "healthy" ] && break
  echo -n "."; sleep 2
done; echo ""

DB_USER=$(grep '^POSTGRES_USER=' "${PROJECT_DIR}/.env" | cut -d'=' -f2-)
DB_NAME=$(grep '^POSTGRES_DB='   "${PROJECT_DIR}/.env" | cut -d'=' -f2-)
docker exec iriswebapp_db psql -U "${DB_USER}" -d "${DB_NAME}" \
  -c "CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";" \
  2>&1 | grep -v '^$' || true
ok "pgcrypto + uuid-ossp enabled"

echo ""
info "═══════════════════════════════════════════════════"
ok  " Setup complete!"
info "═══════════════════════════════════════════════════"
info " Cortex jobs dir  : ${PROJECT_DIR}/cortex/jobs"
info " Next steps:"
info "   docker compose up -d"
info "   bash scripts/install_module.sh"
info "═══════════════════════════════════════════════════"

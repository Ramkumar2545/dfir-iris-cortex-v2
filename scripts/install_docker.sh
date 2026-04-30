#!/usr/bin/env bash
# ============================================================
# install_docker.sh — Installs Docker CE + Compose plugin
#
# Supported:
#   Debian/Ubuntu  : 20.04, 22.04, 24.04, 25.04, 26.04 (+future)
#   RHEL           : 8, 9
#   Rocky Linux    : 8, 9
#   AlmaLinux      : 8, 9
#   Fedora         : 39, 40, 41+ (rolling)
#   CentOS Stream  : 8, 9
#   Amazon Linux   : 2, 2023
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
source "${SCRIPT_DIR}/detect_os.sh"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

info "Detected OS: ${OS_ID} ${OS_VERSION} (${OS_FAMILY}) arch=${ARCH}"

# ── Check if Docker already installed ─────────────────────────
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
  DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
  ok "Docker ${DOCKER_VER} already installed — skipping"
  exit 0
fi

# ══════════════════════════════════════════════════════════════
# DEBIAN / UBUNTU
# ══════════════════════════════════════════════════════════════
if [ "${OS_FAMILY}" = "debian" ]; then

  info "Installing Docker CE for Debian/Ubuntu..."
  export DEBIAN_FRONTEND=noninteractive

  # Remove old conflicting packages
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y "${pkg}" 2>/dev/null || true
  done

  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release

  # Docker keyring
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # Resolve codename — handle Ubuntu 25.04+ where Docker repo may lag
  CODENAME="${OS_CODENAME}"
  if [ -z "${CODENAME}" ]; then
    CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")
  fi

  # Docker maps Ubuntu 25.04 (plucky) and 26.04 (questing) repo
  # If the exact codename doesn't exist yet, fall back to latest LTS (noble)
  DOCKER_REPO_URL="https://download.docker.com/linux/ubuntu"
  if [ "${OS_ID}" = "debian" ]; then
    DOCKER_REPO_URL="https://download.docker.com/linux/debian"
  fi

  HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" \
    "${DOCKER_REPO_URL}/dists/${CODENAME}/Release" || echo "000")

  if [ "${HTTP_STATUS}" != "200" ]; then
    warn "Docker repo not yet available for '${CODENAME}' (HTTP ${HTTP_STATUS})"
    warn "Falling back to 'noble' (Ubuntu 24.04 LTS) packages"
    CODENAME="noble"
  fi

  echo \
    "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
${DOCKER_REPO_URL} ${CODENAME} stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -qq
  apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  systemctl enable docker
  systemctl start  docker

# ══════════════════════════════════════════════════════════════
# RPM: RHEL / Rocky / AlmaLinux / CentOS Stream
# ══════════════════════════════════════════════════════════════
elif [ "${OS_FAMILY}" = "rpm" ]; then

  info "Installing Docker CE for RPM-based (${OS_ID} ${OS_VERSION})..."

  case "${OS_ID}" in
    fedora|nobara)
      DOCKER_REPO="https://download.docker.com/linux/fedora/docker-ce.repo"
      ;;
    amzn)
      # Amazon Linux — use amazon-linux-extras or direct dnf
      if [ "${OS_VERSION}" = "2" ]; then
        amazon-linux-extras install -y docker
        systemctl enable docker && systemctl start docker
        # Install compose plugin separately
        COMPOSE_VER=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
          | grep '"tag_name"' | sed 's/.*: "\(.*\)".*/\1/')
        mkdir -p /usr/local/lib/docker/cli-plugins
        curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-$(uname -m)" \
          -o /usr/local/lib/docker/cli-plugins/docker-compose
        chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
        ok "Docker installed on Amazon Linux 2"
        exit 0
      else
        # Amazon Linux 2023
        DOCKER_REPO="https://download.docker.com/linux/rhel/docker-ce.repo"
      fi
      ;;
    *)
      # RHEL, Rocky, Alma, CentOS Stream — all use rhel repo
      DOCKER_REPO="https://download.docker.com/linux/rhel/docker-ce.repo"
      ;;
  esac

  # Remove old packages
  ${PKG_MGR} remove -y docker docker-client docker-client-latest \
    docker-common docker-latest docker-latest-logrotate \
    docker-logrotate docker-engine podman runc 2>/dev/null || true

  ${PKG_MGR} install -y dnf-plugins-core 2>/dev/null || \
  ${PKG_MGR} install -y yum-utils 2>/dev/null || true

  if command -v dnf &>/dev/null; then
    dnf config-manager --add-repo "${DOCKER_REPO}"
  else
    yum-config-manager --add-repo "${DOCKER_REPO}"
  fi

  ${PKG_MGR} install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  systemctl enable docker
  systemctl start  docker

else
  err "Unsupported OS family '${OS_FAMILY}'. Install Docker manually: https://docs.docker.com/engine/install/"
fi

# ── Post-install ───────────────────────────────────────────────
if ! getent group docker | grep -q "\b${SUDO_USER:-${USER}}\b" 2>/dev/null; then
  usermod -aG docker "${SUDO_USER:-${USER}}" 2>/dev/null || true
  warn "User added to 'docker' group — log out and back in (or run: newgrp docker)"
fi

docker --version && ok "Docker installed successfully"
docker compose version && ok "Docker Compose plugin installed successfully"

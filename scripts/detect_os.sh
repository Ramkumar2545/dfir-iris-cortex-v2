#!/usr/bin/env bash
# ============================================================
# detect_os.sh — sourced by other scripts (not run directly)
# Sets:
#   OS_FAMILY   = debian | rpm
#   OS_ID       = ubuntu | debian | rhel | rocky | almalinux | fedora | centos | ...
#   OS_VERSION  = 22.04 | 24.04 | 25.04 | 26.04 | 9 | 10 | 41 ...
#   OS_CODENAME = jammy | noble | plucky | questing | ... (debian/ubuntu only)
#   PKG_MGR     = apt | dnf | yum
#   ARCH        = amd64 | arm64 | arm/v7
# ============================================================

if [ ! -f /etc/os-release ]; then
  echo "[ERR] /etc/os-release not found — cannot detect OS" >&2
  exit 1
fi

. /etc/os-release

OS_ID="${ID:-unknown}"
OS_VERSION="${VERSION_ID:-0}"
OS_CODENAME="${VERSION_CODENAME:-}"
# Some distros put codename only in UBUNTU_CODENAME
[ -z "${OS_CODENAME}" ] && OS_CODENAME="${UBUNTU_CODENAME:-}"

# Architecture normalised for Docker
case "$(uname -m)" in
  x86_64)          ARCH="amd64" ;;
  aarch64|arm64)   ARCH="arm64" ;;
  armv7l)          ARCH="armhf" ;;
  *)               ARCH="$(uname -m)" ;;
esac

_set_rpm_pkg_mgr() {
  if   command -v dnf  &>/dev/null; then PKG_MGR="dnf"
  elif command -v yum  &>/dev/null; then PKG_MGR="yum"
  else
    echo "[ERR] Neither dnf nor yum found" >&2; exit 1
  fi
}

case "${OS_ID}" in
  ubuntu|debian|linuxmint|pop|elementary|kali|parrot|zorin)
    OS_FAMILY="debian"; PKG_MGR="apt" ;;
  rhel|centos|centos-stream|rocky|almalinux|ol|scientific)
    OS_FAMILY="rpm"; _set_rpm_pkg_mgr ;;
  fedora|nobara)
    OS_FAMILY="rpm"; PKG_MGR="dnf" ;;
  amzn)
    OS_FAMILY="rpm"
    # Amazon Linux 2023+ uses dnf; AL2 uses yum
    _set_rpm_pkg_mgr ;;
  sles|opensuse-leap|opensuse-tumbleweed)
    OS_FAMILY="rpm"; PKG_MGR="zypper" ;;
  arch|manjaro)
    OS_FAMILY="arch"; PKG_MGR="pacman" ;;
  *)
    # Fallback: check ID_LIKE
    case "${ID_LIKE:-}" in
      *debian*|*ubuntu*)
        OS_FAMILY="debian"; PKG_MGR="apt" ;;
      *rhel*|*fedora*|*centos*)
        OS_FAMILY="rpm"; _set_rpm_pkg_mgr ;;
      *)
        echo "[WARN] Unknown OS '${OS_ID}' — assuming Debian family" >&2
        OS_FAMILY="debian"; PKG_MGR="apt" ;;
    esac ;;
esac

export OS_FAMILY OS_ID OS_VERSION OS_CODENAME PKG_MGR ARCH

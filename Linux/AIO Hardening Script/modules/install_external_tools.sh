#!/usr/bin/env bash
# modules/install_external_tools.sh
# External security tool installer module for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Requires lib/logging.sh, lib/prompts.sh, lib/detect.sh; requires OS_FAMILY + PKG_CMD via detect_os_and_pkg; requires internet access for repository/key installs

set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$ROOT_DIR/config.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/logging.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/prompts.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/detect.sh"

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

pkg_update() {
  case "${PKG_CMD:-}" in
    apt-get) apt-get update -y ;;
    dnf)     dnf -y makecache ;;
    yum)     yum -y makecache ;;
    *)       die "PKG_CMD is not set or unsupported: '${PKG_CMD:-}'" ;;
  esac
}

pkg_install() {
  case "${PKG_CMD:-}" in
    apt-get) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)     dnf install -y "$@" ;;
    yum)     yum install -y "$@" ;;
    *)       die "PKG_CMD is not set or unsupported: '${PKG_CMD:-}'" ;;
  esac
}

enable_and_start() {
  local unit="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now "$unit" || die "Failed to enable/start: $unit"
  else
    warn "systemctl not available; cannot enable/start $unit automatically."
  fi
}

# ----------------------------
# Suricata
# ----------------------------
install_suricata() {
  echo
  warn "Suricata is an IDS/inspection tool. It does not replace a firewall and does not block traffic by default."
  if ! prompt_yes_no "Continue installing Suricata?"; then
    log "Canceled Suricata install."
    return 0
  fi

  pkg_update

  case "${OS_FAMILY:-}" in
    ubuntu)
      pkg_install suricata
      ;;
    fedora|oracle)
      # Install from repo if available; teams can add additional repos later if needed.
      pkg_install suricata
      ;;
    *)
      die "Unsupported OS_FAMILY for Suricata install: '${OS_FAMILY:-}'"
      ;;
  esac

  # Enable service if present
  set +e
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now suricata.service
  fi
  set -e

  log "Suricata version:"
  suricata -V || true
  log "Suricata installation complete."
}

# ----------------------------
# ClamAV
# ----------------------------
install_clamav() {
  echo
  warn "ClamAV installation includes signature updates (requires network access)."
  if ! prompt_yes_no "Continue installing ClamAV?"; then
    log "Canceled ClamAV install."
    return 0
  fi

  pkg_update

  case "${OS_FAMILY:-}" in
    ubuntu)
      pkg_install clamav clamav-daemon
      ;;
    fedora|oracle)
      # Package names vary; try common baselines
      set +e
      pkg_install clamav clamav-update
      local rc=$?
      set -e
      if [[ $rc -ne 0 ]]; then
        pkg_install clamav || true
      fi
      ;;
    *)
      die "Unsupported OS_FAMILY for ClamAV install: '${OS_FAMILY:-}'"
      ;;
  esac

  # Update signatures if possible
  set +e
  if command -v freshclam >/dev/null 2>&1; then
    freshclam
  fi
  set -e

  # Enable services where applicable
  set +e
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now clamav-freshclam 2>/dev/null || true
    systemctl enable --now clamav-daemon 2>/dev/null || true
    systemctl enable --now clamd@scan 2>/dev/null || true
  fi
  set -e

  log "ClamAV version:"
  clamscan --version || true
  log "ClamAV installation complete."
}

# ----------------------------
# Wazuh repo helpers
# ----------------------------
add_wazuh_repo_apt() {
  pkg_update
  pkg_install gnupg apt-transport-https curl

  curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
    | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
  chmod 644 /usr/share/keyrings/wazuh.gpg

  echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
    | tee /etc/apt/sources.list.d/wazuh.list >/dev/null

  pkg_update
}

add_wazuh_repo_rpm() {
  require_cmd rpm
  require_cmd curl

  rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

  cat > /etc/yum.repos.d/wazuh.repo <<'EOF'
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
priority=1
EOF

  pkg_update
}

disable_wazuh_repo_prompt() {
  echo
  warn "Disabling the Wazuh repository after install helps prevent unintended upgrades during competition."
  if ! prompt_yes_no "Disable Wazuh repository now?"; then
    return 0
  fi

  case "${PKG_CMD:-}" in
    apt-get)
      if [[ -f /etc/apt/sources.list.d/wazuh.list ]]; then
        sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/wazuh.list
        pkg_update
        log "Wazuh APT repo disabled."
      else
        warn "Wazuh list file not found; cannot disable repo."
      fi
      ;;
    dnf|yum)
      if [[ -f /etc/yum.repos.d/wazuh.repo ]]; then
        sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/wazuh.repo
        log "Wazuh RPM repo disabled."
      else
        warn "Wazuh repo file not found; cannot disable repo."
      fi
      ;;
    *)
      warn "Unknown PKG_CMD; cannot disable Wazuh repo automatically."
      ;;
  esac
}

# ----------------------------
# Wazuh Agent
# ----------------------------
install_wazuh_agent() {
  echo
  warn "This installs the Wazuh agent and enrolls it to a Wazuh manager."
  warn "You must provide the manager IP/hostname correctly for enrollment to work."
  if ! prompt_yes_no "Continue installing Wazuh agent?"; then
    log "Canceled Wazuh agent install."
    return 0
  fi

  local mgr_ip=""
  local agent_name=""

  read -r -p "Wazuh manager IP/hostname: " mgr_ip
  [[ -n "$mgr_ip" ]] || die "Manager IP/hostname cannot be empty."

  read -r -p "Agent name (optional, press Enter to skip): " agent_name

  echo
  warn "Manager target: $mgr_ip"
  if [[ -n "$agent_name" ]]; then
    warn "Agent name: $agent_name"
  fi
  if ! prompt_yes_no "Confirm enrollment target is correct and proceed?"; then
    log "Canceled Wazuh agent install."
    return 0
  fi

  case "${OS_FAMILY:-}" in
    ubuntu)
      add_wazuh_repo_apt
      if [[ -n "$agent_name" ]]; then
        WAZUH_MANAGER="$mgr_ip" WAZUH_AGENT_NAME="$agent_name" apt-get install -y wazuh-agent
      else
        WAZUH_MANAGER="$mgr_ip" apt-get install -y wazuh-agent
      fi
      ;;
    fedora|oracle)
      add_wazuh_repo_rpm
      if [[ -n "$agent_name" ]]; then
        WAZUH_MANAGER="$mgr_ip" WAZUH_AGENT_NAME="$agent_name" "${PKG_CMD}" install -y wazuh-agent
      else
        WAZUH_MANAGER="$mgr_ip" "${PKG_CMD}" install -y wazuh-agent
      fi
      ;;
    *)
      die "Unsupported OS_FAMILY for Wazuh agent install: '${OS_FAMILY:-}'"
      ;;
  esac

  set +e
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now wazuh-agent.service
  fi
  set -e

  disable_wazuh_repo_prompt

  log "Wazuh agent installed. Service status:"
  set +e
  systemctl --no-pager status wazuh-agent 2>/dev/null | sed -n '1,12p'
  set -e
}

# ----------------------------
# Wazuh Manager
# ----------------------------
install_wazuh_manager() {
  echo
  warn "This installs the Wazuh manager on this machine."
  warn "Only install this if this host is intended to be the Wazuh manager for your environment."
  warn "This may consume additional CPU/memory and changes the security posture of the host."
  if ! prompt_yes_no "Continue installing Wazuh manager?"; then
    log "Canceled Wazuh manager install."
    return 0
  fi

  echo
  if ! prompt_yes_no "Final confirm: this host will run the Wazuh manager. Proceed?"; then
    log "Canceled Wazuh manager install."
    return 0
  fi

  case "${OS_FAMILY:-}" in
    ubuntu)
      add_wazuh_repo_apt
      apt-get install -y wazuh-manager
      ;;
    fedora|oracle)
      add_wazuh_repo_rpm
      "${PKG_CMD}" install -y wazuh-manager
      ;;
    *)
      die "Unsupported OS_FAMILY for Wazuh manager install: '${OS_FAMILY:-}'"
      ;;
  esac

  set +e
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now wazuh-manager.service
  fi
  set -e

  disable_wazuh_repo_prompt

  log "Wazuh manager installed. Service status:"
  set +e
  systemctl --no-pager status wazuh-manager 2>/dev/null | sed -n '1,12p'
  set -e
}

install_wazuh() {
  echo
  log "Wazuh installation selection:"
  local options=("wazuh_agent" "wazuh_manager" "Cancel")
  local choice
  choice="$(prompt_choice "Install which Wazuh component?" options[@])"

  case "$choice" in
    wazuh_agent)   install_wazuh_agent ;;
    wazuh_manager) install_wazuh_manager ;;
    Cancel)        log "Canceled Wazuh selection." ;;
    *)             die "Invalid selection: $choice" ;;
  esac
}

usage() {
  cat <<EOF
Usage:
  sudo $0 <tool>

Tools:
  suricata
  clamav
  wazuh

EOF
}

main() {
  require_root_or_sudo
  detect_os_and_pkg

  local tool="${1:-}"
  [[ -n "$tool" ]] || { usage; exit 1; }

  case "$tool" in
    suricata) install_suricata ;;
    clamav)   install_clamav ;;
    wazuh)    install_wazuh ;;
    *)        usage; die "Unknown tool: '$tool'" ;;
  esac
}

main "$@"

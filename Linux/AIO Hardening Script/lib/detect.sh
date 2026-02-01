#!/usr/bin/env bash
# lib/detect.sh
# OS/package manager and firewall detection for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Requires prompts.sh + logging.sh for confirm_or_select_firewall; expects OS_FAMILY set for best firewall default

# Enable strict error handling
require_root_or_sudo() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "This script must be run via sudo ./main.sh"
}

# Detect OS family and set OS_FAMILY, PKG_MGR, and PKG_CMD
detect_os_and_pkg() {
  local id="" like=""

  OS_FAMILY=""
  PKG_MGR=""
  PKG_CMD=""

  # Detect OS via /etc/os-release
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    like="${ID_LIKE:-}"
  fi

  case "$id" in
    ubuntu) OS_FAMILY="ubuntu" ;; # Ubuntu/Debian
    fedora) OS_FAMILY="fedora" ;; # Fedora
    ol|oracle|oraclelinux|olinux) OS_FAMILY="oracle" ;; # Oracle Linux
    centos|rhel|rocky|almalinux) OS_FAMILY="oracle" ;; # Treat RHEL/CentOS/Rocky/Alma as Oracle Linux family
    *) # Fallback to ID_LIKE parsing
      if [[ "$like" == *"ubuntu"* || "$like" == *"debian"* ]]; then
        OS_FAMILY="ubuntu"
      elif [[ "$like" == *"fedora"* ]]; then
        OS_FAMILY="fedora"
      elif [[ "$like" == *"rhel"* || "$like" == *"centos"* ]]; then
        OS_FAMILY="oracle" 
      else
        OS_FAMILY=""
      fi
      ;;
  esac

  # Determine package manager and command
  case "$OS_FAMILY" in
    ubuntu) # Ubuntu/Debian
      PKG_MGR="apt"
      PKG_CMD="apt-get"
      ;;
    fedora) # Fedora
      PKG_MGR="dnf"
      PKG_CMD="dnf"
      ;;
    oracle) # Oracle Linux / RHEL family
      if command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
        PKG_CMD="dnf"
      elif command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
        PKG_CMD="yum"
      fi
      ;;
  esac

  export OS_FAMILY PKG_MGR PKG_CMD
}

#  Detect installed firewall and set FIREWALL_TYPE and FIREWALL_CMD
detect_firewall() {
  # Reset variables
  FIREWALL_TYPE=""
  FIREWALL_CMD=""

  local has_ufw="false"
  local has_fwcmd="false"

  # Detect installed firewalls
  command -v ufw >/dev/null 2>&1 && has_ufw="true"
  command -v firewall-cmd >/dev/null 2>&1 && has_fwcmd="true"


  # Determine default firewall if both present
  if [[ "$has_ufw" == "true" && "$has_fwcmd" == "false" ]]; then
    FIREWALL_TYPE="ufw"
  elif [[ "$has_fwcmd" == "true" && "$has_ufw" == "false" ]]; then
    FIREWALL_TYPE="firewalld"
  elif [[ "$has_fwcmd" == "true" && "$has_ufw" == "true" ]]; then
    case "$OS_FAMILY" in
      ubuntu) FIREWALL_TYPE="ufw" ;;
      fedora|oracle) FIREWALL_TYPE="firewalld" ;;
      *) FIREWALL_TYPE="firewalld" ;;
    esac
  else
    FIREWALL_TYPE=""
  fi

  # Set FIREWALL_CMD based on detected type
  case "$FIREWALL_TYPE" in
    ufw) FIREWALL_CMD="ufw" ;;
    firewalld) FIREWALL_CMD="firewall-cmd" ;;
  esac

  export FIREWALL_TYPE FIREWALL_CMD
}

# Confirm detected firewall or prompt user to select
confirm_or_select_firewall() {
  local options=("ufw" "firewalld")
  local chosen=""

  detect_firewall

  # Prompt user to confirm or select firewall
  if [[ -n "$FIREWALL_TYPE" ]]; then
    if prompt_yes_no "Detected firewall: $FIREWALL_TYPE (command: $FIREWALL_CMD). Is this correct for your environment?"; then
      :
    else
      chosen="$(prompt_choice "Select firewall to manage:" options[@])"
      FIREWALL_TYPE="$chosen"
    fi
  # No firewall detected - Warning and prompt
  else
    warn "No supported firewall detected (ufw/firewalld). You may need to install one."
    chosen="$(prompt_choice "Select firewall to manage (will fail if not installed):" options[@])"
    FIREWALL_TYPE="$chosen"
  fi

  # Set FIREWALL_CMD based on selection
  case "$FIREWALL_TYPE" in
    ufw) FIREWALL_CMD="ufw" ;;
    firewalld) FIREWALL_CMD="firewall-cmd" ;;
    *) die "Invalid firewall selection: $FIREWALL_TYPE" ;;
  esac

  export FIREWALL_TYPE FIREWALL_CMD
}

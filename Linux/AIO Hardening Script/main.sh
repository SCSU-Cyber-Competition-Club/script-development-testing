#!/usr/bin/env bash
# main.sh
# Controller / menu logic for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Requires config.sh and lib/* to exist; exports ROLE and PORTS_TCP for modules
# Version 1.0
# Last updated 02-01-2026

# Enable strict error handling
set -euo pipefail
IFS=$'\n\t'

# Determine script root directory
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
. "$ROOT_DIR/config.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/logging.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/prompts.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/detect.sh"

ensure_exec_deps() {
  # Check that required scripts exist and are executable
  local deps=(
    "$ROOT_DIR/modules/preflight.sh"
    "$ROOT_DIR/modules/disable_ssh.sh"
    "$ROOT_DIR/modules/validate_role.sh"
    "$ROOT_DIR/modules/baseline.sh"
    "$ROOT_DIR/modules/firewall/ufw.sh"
    "$ROOT_DIR/modules/firewall/firewalld.sh"
    "$ROOT_DIR/modules/splunk_forwarder.sh"
    "$ROOT_DIR/linuxSplunkForwarderInstall.sh"
    "$ROOT_DIR/modules/install_external_tools.sh"
  )

  local missing=()
  local need_chmod=()

  local f
  for f in "${deps[@]}"; do
    if [[ ! -f "$f" ]]; then
      missing+=("$f")
      continue
    fi
    if [[ ! -x "$f" ]]; then
      need_chmod+=("$f")
    fi
  done

  # Report missing files and exit
  if (( ${#missing[@]} > 0 )); then
    warn "Missing required files:"
    for f in "${missing[@]}"; do
      warn "  - $f"
    done
    die "Cannot continue until missing files are restored."
  fi

  # Report non-executable files and offer to fix
  if (( ${#need_chmod[@]} == 0 )); then
    log "Executable dependencies: OK"
    return 0
  fi
  warn "Some required scripts are not executable:"
  for f in "${need_chmod[@]}"; do
    warn "  - $f"
  done

  # Prompt to fix non-executable scripts
  if ! prompt_yes_no "Set executable permission (chmod +x) for these files now?"; then
    die "Required scripts are not executable. Aborting."
  fi

  # Needs root if files are owned by root or extracted with restrictive perms.
  local chmod_cmd=(chmod +x)
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    chmod_cmd=(chmod +x)
  fi

  "${chmod_cmd[@]}" "${need_chmod[@]}"
  log "Set +x on required scripts."
}

# initializze ROLE and PORTS_TCP
export ROLE=""
export PORTS_TCP=()

# set and export ROLE and associated PORTS_TCP based on selection
set_role_ports() {
  local role="$1"
  ROLE="$role"
  PORTS_TCP=()

  case "$ROLE" in
    ecomm)   PORTS_TCP=("${PORTS_ECOMM_TCP[@]}") ;;
    webmail) PORTS_TCP=("${PORTS_WEBMAIL_TCP[@]}") ;;
    splunk)  PORTS_TCP=("${PORTS_SPLUNK_TCP[@]}") ;;
    *) die "Unknown role: $ROLE" ;;
  esac

  export ROLE PORTS_TCP
}

# Prompt user to select service role
select_role() {
  local options=("ecomm" "webmail" "splunk")
  local chosen=""

  if [[ -n "${DEFAULT_ROLE:-}" ]]; then
    if prompt_yes_no "Default role is '${DEFAULT_ROLE}'. Use this role?"; then
      chosen="$DEFAULT_ROLE"
    else
      chosen="$(prompt_choice "Select service role:" options[@])"
    fi
  else
    chosen="$(prompt_choice "Select service role:" options[@])"
  fi

  set_role_ports "$chosen"
  log "ROLE set to '$ROLE' (TCP allowed: ${PORTS_TCP[*]:-(none)})"
}

# function to run preflight module
run_preflight_module() {
  "$ROOT_DIR/modules/preflight.sh"
}

# function to run disable ssh module
run_disable_ssh_module() {
  "$ROOT_DIR/modules/disable_ssh.sh"
}

# function to run validate role module
run_validate_role_module() {
  "$ROOT_DIR/modules/validate_role.sh"
}

# function to run baseline hardening module
run_baseline_module() {
  "$ROOT_DIR/modules/baseline.sh"
}

# function to run splunk forwarder module
run_splunk_forwarder_module() {
  "$ROOT_DIR/modules/splunk_forwarder.sh"
}

# function to run external tool installation module
run_external_tool_install_module() {
  "$ROOT_DIR/modules/install_external_tools.sh" "$1"
}

# function to run firewall module based on selected ROLE and detected/selected firewall
apply_firewall() {
  # Detect or confirm firewall to use
  confirm_or_select_firewall
  log "Using firewall: $FIREWALL_TYPE ($FIREWALL_CMD)"

  echo
  warn "Module will enforce default-deny inbound and allow only ROLE TCP ports."
  warn "ROLE='$ROLE' TCP allowed: ${PORTS_TCP[*]:-(none)}"
  warn "If ports are wrong, scoring services may break until fixed."
  if ! prompt_yes_no "Continue to firewall module?"; then
    log "Aborted."
    return 0
  fi

  case "$FIREWALL_TYPE" in
    ufw)       "$ROOT_DIR/modules/firewall/ufw.sh" ;;
    firewalld) "$ROOT_DIR/modules/firewall/firewalld.sh" ;;
    *) die "Unsupported FIREWALL_TYPE: $FIREWALL_TYPE" ;;
  esac
}

# main menu loop
main_menu() {
  local options=(
    "Check Configuration File - Not Implemented"
    "Pre-flight status: Quick overview of system status"
    "Baseline hardening (safe) - Not Implemented"
    "Disable SSH"
    "Validate role services - Scan expected services for selected role"
    "Select/Change Role"
    "Enable firewall (default deny inbound; allow only role TCP ports; block SSH explicitly)"
    "Install Splunk Universal Forwarder (uses config.sh SPLUNK_INDEXER_IP)"
    "Install Suricata"
    "Install ClamAV"
    "Install WAZUH"
    "Exit"
  )

  local choice
  while true; do
    choice="$(prompt_choice "Select an action:" options[@])"
    case "$choice" in
      "Check Configuration File - Not Implemented")
        warn "Not implemented."
        ;;
      "Pre-flight status: Quick overview of system status")
        run_preflight_module
        ;;
      "Baseline hardening (safe) - Not Implemented")
        run_baseline_module
        ;;
      "Disable SSH")
        run_disable_ssh_module
        ;;
      "Validate role services - Scan expected services for selected role")
        run_validate_role_module
        ;;
      "Select/Change Role")
        select_role
        ;;
      "Enable firewall (default deny inbound; allow only role TCP ports; block SSH explicitly)")
        apply_firewall
        ;;
      "Install Splunk Universal Forwarder (uses config.sh SPLUNK_INDEXER_IP)")
        run_splunk_forwarder_module
        ;;
      "Install Suricata")
        run_external_tool_install_module "suricata"
        ;;
      "Install ClamAV")
        run_external_tool_install_module "clamav"
        ;;
      "Install WAZUH")
        run_external_tool_install_module "wazuh"
        ;;
      "Exit")
        exit 0
        ;;
      *)
        warn "Invalid selection."
        ;;
    esac
  done
}

# Main entry point
main() {
  require_root_or_sudo
  detect_os_and_pkg
  ensure_exec_deps
  if [[ -n "${OS_FAMILY:-}" ]]; then
    log "Detected OS_FAMILY=$OS_FAMILY, PKG_CMD=${PKG_CMD:-<none>}"
  else
    warn "Could not reliably detect OS_FAMILY from /etc/os-release."
  fi

  # Role selection up front (ports depend on it)
  select_role

  # Initial firewall detection
  confirm_or_select_firewall
  log "Firewall selected: $FIREWALL_TYPE ($FIREWALL_CMD)"

  main_menu
}

main "$@"

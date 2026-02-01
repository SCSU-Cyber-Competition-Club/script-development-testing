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
    chmod_cmd=(sudo chmod +x)
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

run_preflight_module() {
  sudo "$ROOT_DIR/modules/preflight.sh"
}

run_disable_ssh_module() {
  require_root_or_sudo
  sudo "$ROOT_DIR/modules/disable_ssh.sh"
}

run_validate_role_module() {
  sudo "$ROOT_DIR/modules/validate_role.sh"
}

run_baseline_module() {
  require_root_or_sudo
  sudo "$ROOT_DIR/modules/baseline.sh"
}

# function to run firewall module based on selected ROLE and detected/selected firewall
apply_firewall() {
  require_root_or_sudo
  # Detect or confirm firewall to use
  confirm_or_select_firewall
  log "Using firewall: $FIREWALL_TYPE ($FIREWALL_CMD)"

  echo
  warn "Controller guardrail: module will enforce default-deny inbound and allow only ROLE TCP ports."
  warn "ROLE='$ROLE' TCP allowed: ${PORTS_TCP[*]:-(none)}"
  warn "If ports are wrong, scoring services may break until fixed."
  if ! prompt_yes_no "Continue to firewall module?"; then
    log "Aborted."
    return 0
  fi

  case "$FIREWALL_TYPE" in
    ufw)       sudo "$ROOT_DIR/modules/firewall/ufw.sh" ;;
    firewalld) sudo "$ROOT_DIR/modules/firewall/firewalld.sh" ;;
    *) die "Unsupported FIREWALL_TYPE: $FIREWALL_TYPE" ;;
  esac
}

# function to run splunk forwarder module
run_splunk_forwarder_module() {
  require_root_or_sudo
  sudo "$ROOT_DIR/modules/splunk_forwarder.sh"
}

# main menu loop
main_menu() {
  local options=(
    "Pre-flight status (recommended first)"
    "Baseline hardening (safe)"
    "Disable SSH (Proxmox console access assumed)"
    "Validate role services (recommended before firewall)"
    "Select/Change Role"
    "Enable firewall (default deny inbound; allow only role TCP ports)"
    "Install Splunk Universal Forwarder (uses config.sh SPLUNK_INDEXER_IP)"
    "Exit"
  )

  local choice
  while true; do
    choice="$(prompt_choice "Select an action:" options[@])"
    case "$choice" in
      "Pre-flight status (recommended first)")
        run_preflight_module
        ;;
      "Baseline hardening (safe)")
        run_baseline_module
        ;;
      "Disable SSH (Proxmox console access assumed)")
        run_disable_ssh_module
        ;;
      "Validate role services (recommended before firewall)")
        run_validate_role_module
        ;;
      "Select/Change Role")
        select_role
        ;;
      "Enable firewall (default deny inbound; allow only role TCP ports)")
        apply_firewall
        ;;
      "Install Splunk Universal Forwarder (uses config.sh SPLUNK_INDEXER_IP)")
        run_splunk_forwarder_module
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

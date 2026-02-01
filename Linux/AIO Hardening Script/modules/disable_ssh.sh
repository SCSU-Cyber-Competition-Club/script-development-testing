#!/usr/bin/env bash
# modules/disable_ssh.sh
# SSH disable module for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Must be run with sudo/root; uses systemctl to disable sshd/ssh services

set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$ROOT_DIR/lib/logging.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/prompts.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/detect.sh"

stop_disable_unit_if_exists() {
  local unit="$1"
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "$unit"; then
    log "Disabling and stopping $unit"
    systemctl disable --now "$unit" || true
    return 0
  fi
  return 1
}

main() {
  require_root_or_sudo

  echo
  warn "SSH will be DISABLED. Proxmox console access remains available."
  echo

  if ! prompt_yes_no "Proceed to disable SSH (sshd/ssh service)?"; then
    log "Aborted SSH disable."
    return 0
  fi

  local did_any="false"

  if command -v systemctl >/dev/null 2>&1; then
    stop_disable_unit_if_exists "sshd.service" && did_any="true"
    stop_disable_unit_if_exists "ssh.service"  && did_any="true"

    # Optional: mask to prevent accidental restarts
    if [[ "$did_any" == "true" ]]; then
      if prompt_yes_no "Mask SSH services to prevent accidental re-enable? (recommended)"; then
        systemctl mask sshd.service 2>/dev/null || true
        systemctl mask ssh.service  2>/dev/null || true
        log "SSH services masked."
      fi
    fi
  else
    warn "systemctl not found. Cannot reliably disable ssh/sshd services."
  fi

  # Best-effort port check
  echo
  log "Checking if anything is still listening on TCP/22:"
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep -E '(:22\s|:22$)' || echo "No listener detected on :22"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntp 2>/dev/null | grep -E '(:22\s|:22$)' || echo "No listener detected on :22"
  else
    warn "No ss/netstat available to verify port 22."
  fi

  if [[ "$did_any" == "true" ]]; then
    log "SSH disable operation complete."
  else
    warn "No ssh/sshd unit files were found. SSH may already be disabled or managed differently."
  fi
}

main "$@"

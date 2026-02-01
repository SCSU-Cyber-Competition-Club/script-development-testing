#!/usr/bin/env bash
# modules/firewall/firewalld.sh
# firewalld (firewall-cmd) configuration module for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Requires that ROLE be set and PORTS_TCP array be exported by main.sh; requires firewall-cmd installed; must be run with sudo/root

# Enable strict error handling
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=/dev/null
. "$ROOT_DIR/lib/logging.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/prompts.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/detect.sh"


main() {
  # Err if not run as root/sudo
  require_root_or_sudo
  command -v firewall-cmd >/dev/null 2>&1 || die "firewall-cmd is not installed (firewalld missing)."


  # Validate ROLE and PORTS_TCP
  [[ -n "${ROLE:-}" ]] || die "ROLE is not set."
  [[ "${#PORTS_TCP[@]:-0}" -gt 0 ]] || warn "No TCP ports defined for ROLE=$ROLE."

  # Warning and confirmation
  echo
  warn "This will set DEFAULT DROP inbound and allow only the TCP ports listed for ROLE='$ROLE'."
  warn "Inbound traffic not explicitly allowed will be blocked."
  echo "TCP ports to allow: ${PORTS_TCP[*]:-(none)}"
  echo

  # Confirmation prompt before proceeding
  if ! prompt_yes_no "Proceed to enforce default-drop inbound with firewalld?"; then
    log "Aborted firewall changes."
    return 0
  fi

  # Extra confirmation to avoid breaking scoring accidentally
  if ! prompt_yes_no "FINAL CONFIRM: Wrong ports can break scoring services. Continue?"; then
    log "Aborted firewall changes."
    return 0
  fi
  
  # Enable and start firewalld service
  systemctl enable --now firewalld || die "Failed to enable/start firewalld."

  # Set up firewalld zone
  local zone="public"

  # Optionally remove existing allowed ports/services
  if prompt_yes_no "Remove existing allowed ports/services in zone '$zone' before applying? (recommended)"; then
    local existing_ports
    existing_ports="$(firewall-cmd --zone="$zone" --list-ports || true)"
    if [[ -n "$existing_ports" ]]; then
      local item
      for item in $existing_ports; do
        firewall-cmd --permanent --zone="$zone" --remove-port="$item" || true
      done
    fi

    # Remove existing services if selected
    local existing_services
    existing_services="$(firewall-cmd --zone="$zone" --list-services || true)"
    if [[ -n "$existing_services" ]]; then
      local svc
      for svc in $existing_services; do
        firewall-cmd --permanent --zone="$zone" --remove-service="$svc" || true
      done
    fi
  fi

  # Set default target to DROP
  firewall-cmd --set-default-zone="$zone"
  firewall-cmd --permanent --zone="$zone" --set-target=DROP

  # Allow defined TCP ports
  local p
  for p in "${PORTS_TCP[@]:-}"; do
    firewall-cmd --permanent --zone="$zone" --add-port="${p}/tcp"
  done

  # Reload firewalld to apply changes
  firewall-cmd --reload

  # Log final status
  log "firewalld configured for ROLE=$ROLE (zone=$zone, target=DROP). Current zone config:"
  firewall-cmd --zone="$zone" --list-all || true

  # Final reminder to verify scoring-critical services
  warn "Reminder: verify scoring-critical services are reachable on allowed ports from the scoring network."
}

main "$@"

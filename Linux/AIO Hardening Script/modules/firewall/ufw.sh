#!/usr/bin/env bash
# modules/firewall/ufw.sh
# UFW firewall configuration module for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Requires that ROLE be set and PORTS_TCP array be exported by main.sh; requires ufw installed; must be run with sudo/root

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
  command -v ufw >/dev/null 2>&1 || die "ufw is not installed."

  [[ -n "${ROLE:-}" ]] || die "ROLE is not set."
  [[ "${#PORTS_TCP[@]:-0}" -gt 0 ]] || warn "No TCP ports defined for ROLE=$ROLE."

  echo
  warn "This will set DEFAULT DENY inbound and allow only the TCP ports listed for ROLE='$ROLE'."
  warn "Inbound traffic not explicitly allowed will be blocked."
  echo "TCP ports to allow: ${PORTS_TCP[*]:-(none)}"
  echo

  # Confirmation prompt before proceeding
  if ! prompt_yes_no "Proceed to enforce default-deny inbound with UFW?"; then
    log "Aborted firewall changes."
    return 0
  fi

  # Extra confirmation to avoid breaking scoring accidentally
  if ! prompt_yes_no "FINAL CONFIRM: Wrong ports can break scoring services. Continue?"; then
    log "Aborted firewall changes."
    return 0
  fi

  # Optionally reset to a clean slate
  if prompt_yes_no "Reset UFW rules to a clean baseline before applying? (recommended)"; then
    ufw --force reset
  fi

  # Baseline policy
  ufw default deny incoming

  # Explicitly block all traffic on SSH port 22
  ufw deny 22/tcp
  ufw deny out 22/tcp

  # Allow defined TCP ports
  local p
  for p in "${PORTS_TCP[@]:-}"; do
    ufw allow "${p}/tcp"
  done

  # Enable UFW
  ufw --force enable

  # Log final status
  log "UFW configured for ROLE=$ROLE. Current status:"
  ufw status verbose || true

  # Final reminder to verify scoring-critical services
  warn "Reminder: verify scoring-critical services are reachable on allowed ports from the scoring network."
}

main "$@"

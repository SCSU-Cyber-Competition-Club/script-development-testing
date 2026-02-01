#!/usr/bin/env bash
# modules/splunk_forwarder.sh
# Splunk Universal Forwarder installation wrapper module for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Requires config.sh with SPLUNK_INDEXER_IP; requires linuxSplunkForwarderInstall.sh executable; must be run with sudo/root

# Enable strict error handling
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$ROOT_DIR/lib/logging.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/prompts.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/detect.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/config.sh"

main() {
  require_root_or_sudo

  # Check for installer script
  local installer="$ROOT_DIR/linuxSplunkForwarderInstall.sh"
  [[ -x "$installer" ]] || die "Splunk forwarder installer not found or not executable: $installer"
  # Check for SPLUNK_INDEXER_IP, fail if empty.
  [[ -n "${SPLUNK_INDEXER_IP:-}" ]] || die "config.sh: SPLUNK_INDEXER_IP is empty."

  # Summary and confirmation
  echo
  log "Splunk Universal Forwarder install will target indexer: $SPLUNK_INDEXER_IP"
  warn "Credentials will be passed as command-line arguments (may be visible via process listing to local users)."
  echo

  # prompt before proceeding
  if ! prompt_yes_no "Proceed with Splunk Universal Forwarder installation?"; then
    log "Aborted Splunk forwarder install."
    return 0
  fi

  # Prompt for admin username and password
  local admin_user=""
  local admin_pass=""

  read -r -p "Splunk admin username (for forward-server auth): " admin_user
  [[ -n "$admin_user" ]] || die "Username cannot be empty."

  prompt_secret "Splunk admin password: " admin_pass
  [[ -n "$admin_pass" ]] || die "Password cannot be empty."

  # Final confirmation
  echo
  log "About to run: sudo ./linuxSplunkForwarderInstall.sh $SPLUNK_INDEXER_IP $admin_user (password hidden)"
  if ! prompt_yes_no "Final confirm: run installer now?"; then
    log "Aborted Splunk forwarder install."
    return 0
  fi

  # Run installer
  "$installer" "$SPLUNK_INDEXER_IP" "$admin_user" "$admin_pass"
}

main "$@"

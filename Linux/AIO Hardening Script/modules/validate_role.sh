#!/usr/bin/env bash
# modules/validate_role.sh
# Service role validation module for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Requires ROLE and PORTS_TCP to be exported; requires systemctl for service validation

set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$ROOT_DIR/lib/logging.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/prompts.sh"

is_listening_tcp_port() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -lnt | awk '{print $4}' | grep -Eq "(:|\\])${port}\$"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lnt | awk '{print $4}' | grep -Eq "(:|\\])${port}\$"
  else
    die "Neither ss nor netstat is available to validate listening ports."
  fi
}

service_exists() {
  systemctl list-unit-files --no-pager | awk '{print $1}' | grep -qx "$1"
}

service_active() {
  systemctl is-active --quiet "$1"
}

check_service() {
  local unit="$1"
  local label="$2"

  if service_exists "$unit"; then
    if service_active "$unit"; then
      log "Service OK: $label ($unit) is active"
    else
      warn "Service NOT active: $label ($unit)"
      systemctl --no-pager --full status "$unit" | sed -n '1,10p' || true
    fi
  else
    warn "Service missing: $label ($unit not found)"
  fi
}

validate_ports() {
  local failed=()
  local p

  for p in "${PORTS_TCP[@]:-}"; do
    if ! is_listening_tcp_port "$p"; then
      failed+=("$p")
    fi
  done

  if (( ${#failed[@]} > 0 )); then
    warn "Expected TCP ports not listening: ${failed[*]}"
    warn "Firewall enforcement with these ports missing may break scoring."
  else
    log "All expected TCP ports are listening."
  fi
}

validate_ecomm() {
  log "Validating ecommerce stack (Apache + OpenCart)"
  check_service "apache2.service" "Apache HTTP Server" || \
  check_service "httpd.service"  "Apache HTTP Server"
}

validate_webmail() {
  log "Validating webmail stack (Postfix + Dovecot + Roundcube)"

  check_service "postfix.service" "Postfix MTA"
  check_service "dovecot.service" "Dovecot IMAP/POP3"

  # Roundcube typically served via Apache
  check_service "httpd.service" "Apache HTTP Server (Roundcube)" || \
  check_service "apache2.service" "Apache HTTP Server (Roundcube)"
}

validate_splunk() {
  log "Validating Splunk services"

  local found="false"
  local units=(
    splunk.service
    splunkd.service
    SplunkForwarder.service
    splunkforwarder.service
  )

  for u in "${units[@]}"; do
    if service_exists "$u"; then
      found="true"
      if service_active "$u"; then
        log "Service OK: $u is active"
      else
        warn "Service NOT active: $u"
      fi
    fi
  done

  if [[ "$found" == "false" ]]; then
    warn "No standard Splunk systemd units found."
    warn "Verify Splunk installation path and service configuration manually."
  fi
}

main() {
  [[ -n "${ROLE:-}" ]] || die "ROLE is not set."
  [[ "${#PORTS_TCP[@]:-0}" -gt 0 ]] || warn "No TCP ports defined for ROLE=$ROLE."

  echo
  log "=== Role Service Validation ==="
  log "ROLE: $ROLE"
  echo "Expected TCP ports: ${PORTS_TCP[*]:-(none)}"
  echo

  validate_ports
  echo

  case "$ROLE" in
    ecomm)
      validate_ecomm
      ;;
    webmail)
      validate_webmail
      ;;
    splunk)
      validate_splunk
      ;;
    *)
      die "Unknown ROLE: $ROLE"
      ;;
  esac

  echo
  log "Role validation completed."
  warn "Resolve missing services or ports before enabling firewall deny-by-default."
}

main "$@"

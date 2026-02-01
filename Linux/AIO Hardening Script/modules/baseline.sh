#!/usr/bin/env bash
# modules/baseline.sh
# Baseline hardening (safe) module for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Must be run with sudo/root; requires detect.sh for PKG_CMD; installs basic troubleshooting utilities

set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$ROOT_DIR/lib/logging.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/prompts.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/detect.sh"

refresh_package_metadata() {
  case "${PKG_CMD:-}" in
    apt-get)
      log "Running apt-get update..."
      DEBIAN_FRONTEND=noninteractive apt-get update -y
      ;;
    dnf)
      log "Running dnf makecache..."
      dnf -y makecache
      ;;
    yum)
      log "Running yum makecache..."
      yum -y makecache
      ;;
    *)
      warn "Unknown PKG_CMD; cannot refresh package metadata."
      return 1
      ;;
  esac
}

install_packages() {
  local pkgs=("$@")
  [[ "${#pkgs[@]}" -gt 0 ]] || return 0

  case "${PKG_CMD:-}" in
    apt-get)
      log "Installing packages via apt-get: ${pkgs[*]}"
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      log "Installing packages via dnf: ${pkgs[*]}"
      dnf -y install "${pkgs[@]}"
      ;;
    yum)
      log "Installing packages via yum: ${pkgs[*]}"
      yum -y install "${pkgs[@]}"
      ;;
    *)
      die "Unknown PKG_CMD; cannot install packages."
      ;;
  esac
}

main() {
  require_root_or_sudo
  detect_os_and_pkg

  echo
  log "=== Baseline Hardening (Safe) ==="
  warn "This module installs basic utilities only. It does not modify time sync, firewall rules, or service configs."
  echo "OS_FAMILY: ${OS_FAMILY:-unknown}"
  echo "PKG_CMD:   ${PKG_CMD:-unknown}"
  echo

  if prompt_yes_no "Refresh package metadata/cache first? (recommended)"; then
    refresh_package_metadata || warn "Package metadata refresh had issues."
  fi

  # Package mapping by family (keep small + likely available everywhere)
  local packages=()
  case "${OS_FAMILY:-}" in
    ubuntu)
      packages=(curl wget lsof net-tools procps psmisc)
      ;;
    fedora|oracle)
      # procps-ng is typical on RHEL/Fedora family
      packages=(curl wget lsof net-tools procps-ng psmisc)
      ;;
    *)
      # Fallback: try common names
      packages=(curl wget lsof net-tools procps psmisc)
      ;;
  esac

  echo
  log "Suggested tools to install: ${packages[*]}"
  if prompt_yes_no "Install these baseline tools now?"; then
    install_packages "${packages[@]}"
    log "Baseline tools install complete."
  else
    log "Skipped baseline tool installation."
  fi

  echo
  log "Baseline complete."
  warn "Recommended next: Pre-flight Status + Role Validation, then firewall deny-by-default."
}

main "$@"

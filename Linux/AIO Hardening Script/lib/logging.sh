#!/usr/bin/env bash
# lib/logging.sh
# Logging helpers for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: None; sourced by main.sh and modules

log()  { printf "[%s] %s\n" "$(date '+%F %T')" "$*"; }
warn() { printf "[%s] WARN: %s\n" "$(date '+%F %T')" "$*" >&2; }
die()  { printf "[%s] ERROR: %s\n" "$(date '+%F %T')" "$*" >&2; exit 1; }

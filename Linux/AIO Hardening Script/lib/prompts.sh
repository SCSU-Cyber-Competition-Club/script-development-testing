#!/usr/bin/env bash
# lib/prompts.sh
# User prompt helpers for AIO Hardening Script
# Written by Colin Robertson
# Intended for use with main.sh
# Requirements: Interactive terminal for select/Y-N prompts; sourced by main.sh and modules

# Usage: prompt_yes_no "Question?"
# Returns 0 for yes, 1 for no
prompt_yes_no() {
  local q="$1" ans=""
  while true; do
    read -r -p "$q [Y/N]: " ans
    ans="${ans,,}"
    case "$ans" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     echo "Please answer Y or N." ;;
    esac
  done
}

# Usage: prompt_choice "Prompt" options[@]
# Returns selected choice
prompt_choice() {
  local prompt_message="$1"
  local choices=("${!2}")
  local choice

  echo
  echo "$prompt_message"
  select choice in "${choices[@]}"; do
    if [[ -n "$choice" ]]; then
      echo "$choice"
      return 0
    else
      echo "Invalid choice. Please try again."
    fi
  done
}

# Usage: prompt_secret "Prompt" varname
# Used to read a secret input (like a password) without echoing
prompt_secret() {
  local prompt="$1"
  local __varname="$2"
  local value=""
  read -r -s -p "$prompt" value
  echo
  printf -v "$__varname" '%s' "$value"
}

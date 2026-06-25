#!/usr/bin/env bash

set -o pipefail

SHIVA_VERSION="1.0.0"
SHIVA_RELEASE="Stable"
SHIVA_PRODUCT="Shiva Toolkit"
SHIVA_CONFIG="${SHIVA_CONFIG:-/etc/shiva/shiva.conf}"
SHIVA_PROFILE_DIR="${SHIVA_PROFILE_DIR:-/etc/shiva/profiles}"
SHIVA_BUILTIN_PROFILE_DIR="${SHIVA_BUILTIN_PROFILE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/profiles}"

if [[ -t 1 && "${NO_COLOR:-}" == "" ]]; then
  SHIVA_GREEN=$'\033[32m'
  SHIVA_YELLOW=$'\033[33m'
  SHIVA_RED=$'\033[31m'
  SHIVA_BOLD=$'\033[1m'
  SHIVA_RESET=$'\033[0m'
else
  SHIVA_GREEN=""
  SHIVA_YELLOW=""
  SHIVA_RED=""
  SHIVA_BOLD=""
  SHIVA_RESET=""
fi

: "${CHECK_OPENVPN:=true}"
: "${CHECK_OCSERV:=false}"
: "${CHECK_AMNEZIA:=false}"
: "${CHECK_DOCKER:=true}"
: "${CHECK_SMART:=true}"
: "${CHECK_TEMPERATURE:=true}"
: "${CHECK_INTERFACES:=true}"
: "${OPENVPN_INTERFACE:=tun0}"
: "${AMNEZIA_INTERFACE:=awg0}"
: "${AMNEZIA_SERVICE:=awg-quick@awg0}"
: "${REQUIRED_INTERFACES:=}"
: "${REQUIRED_INTERFACE:=}"
: "${SMART_DISK:=}"

shiva_detect_hostname() {
  local detected
  if command -v hostnamectl >/dev/null 2>&1; then
    detected="$(hostnamectl --static 2>/dev/null || true)"
  fi
  if [[ -z "${detected:-}" ]] && command -v hostname >/dev/null 2>&1; then
    detected="$(hostname 2>/dev/null || true)"
  fi
  [[ "$detected" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || detected="unknown"
  printf '%s' "$detected"
}

shiva_load_profile() {
  local builtin external
  SHIVA_HOSTNAME="${SHIVA_HOSTNAME:-$(shiva_detect_hostname)}"
  SHIVA_PROFILE_NAME="$SHIVA_HOSTNAME"
  SHIVA_PROFILE_SOURCE="defaults"
  builtin="$SHIVA_BUILTIN_PROFILE_DIR/$SHIVA_HOSTNAME.conf"
  external="$SHIVA_PROFILE_DIR/$SHIVA_HOSTNAME.conf"

  if [[ -r "$builtin" ]]; then
    source "$builtin"
    SHIVA_PROFILE_SOURCE="$builtin"
  fi
  if [[ -r "$external" ]]; then
    source "$external"
    SHIVA_PROFILE_SOURCE="$external"
  fi
  [[ -r "$SHIVA_CONFIG" ]] && source "$SHIVA_CONFIG"
  return 0
}

shiva_load_profile

# Backward-compatible singular form for profiles that require one interface.
if [[ -z "$REQUIRED_INTERFACES" && -n "$REQUIRED_INTERFACE" ]]; then
  REQUIRED_INTERFACES="$REQUIRED_INTERFACE"
fi

shiva_title() {
  local title="$1"
  printf '\n══════════════════════════════════════\n'
  printf '        %s\n' "$title"
  printf '══════════════════════════════════════\n\n'
}

shiva_version_string() {
  printf '%s v%s' "$SHIVA_PRODUCT" "$SHIVA_VERSION"
}

shiva_status() {
  local level="$1" label="$2" value="$3" icon color
  case "$level" in
    ok)   icon="🟢"; color="$SHIVA_GREEN" ;;
    warn) icon="🟡"; color="$SHIVA_YELLOW" ;;
    fail) icon="🔴"; color="$SHIVA_RED" ;;
    *)    icon="⚪"; color="" ;;
  esac
  printf '%s %s%-18s%s %s\n' "$icon" "$color" "$label" "$SHIVA_RESET" "$value"
}

shiva_have() {
  command -v "$1" >/dev/null 2>&1
}

shiva_enabled() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

shiva_check_enabled() {
  local variable="$1"
  shiva_enabled "${!variable:-false}"
}

shiva_vpn_checks_enabled() {
  shiva_check_enabled CHECK_OPENVPN ||
    shiva_check_enabled CHECK_OCSERV ||
    shiva_check_enabled CHECK_AMNEZIA
}

shiva_interface_exists() {
  local interface="$1"
  [[ -d "/sys/class/net/$interface" ]] ||
    {
      shiva_have ip && {
        ip link show dev "$interface" >/dev/null 2>&1 ||
          ip link show "$interface" >/dev/null 2>&1 ||
          ip addr show dev "$interface" >/dev/null 2>&1 ||
          ip addr show "$interface" >/dev/null 2>&1
      }
    }
}

shiva_interface_is_up() {
  local interface="$1"
  if [[ -r "/sys/class/net/$interface/operstate" ]]; then
    [[ "$(<"/sys/class/net/$interface/operstate")" == "up" ]]
  elif shiva_have ip; then
    ip -brief link show dev "$interface" 2>/dev/null |
      awk '$2 == "UP" {found=1} END {exit !found}'
  else
    return 1
  fi
}

shiva_required_interface_healthy() {
  local interface="$1"

  if shiva_check_enabled CHECK_OPENVPN &&
    [[ "$interface" == "$OPENVPN_INTERFACE" ]]; then
    shiva_interface_exists "$interface"
    return
  fi
  if shiva_check_enabled CHECK_AMNEZIA &&
    [[ "$interface" == "$AMNEZIA_INTERFACE" ]]; then
    shiva_interface_exists "$interface"
    return
  fi
  shiva_interface_is_up "$interface"
}

shiva_active_interfaces() {
  shiva_have ip || return 1
  ip -brief link 2>/dev/null |
    awk '$1 != "lo" && $2 == "UP" {printf "%s%s", separator, $1; separator=", "}'
}

shiva_service_state() {
  local service="$1"
  if ! shiva_have systemctl; then
    printf 'UNAVAILABLE'
  elif systemctl is-active --quiet "$service" 2>/dev/null; then
    printf 'RUNNING'
  elif systemctl list-unit-files "$service.service" --no-legend 2>/dev/null | grep -q .; then
    printf 'STOPPED'
  else
    printf 'NOT INSTALLED'
  fi
}

shiva_openvpn_state() {
  if shiva_interface_exists "$OPENVPN_INTERFACE"; then
    printf 'RUNNING (%s)' "$OPENVPN_INTERFACE"
  elif shiva_have systemctl &&
    systemctl list-units --type=service --state=active --no-legend \
      'openvpn-client@*.service' 'openvpn@*.service' 2>/dev/null | grep -q .; then
    printf 'RUNNING'
  elif shiva_have systemctl &&
    systemctl list-unit-files --no-legend \
      'openvpn-client@*.service' 'openvpn@*.service' 2>/dev/null | grep -q .; then
    printf 'STOPPED'
  else
    printf 'NOT INSTALLED'
  fi
}

shiva_amnezia_state() {
  if shiva_interface_exists "$AMNEZIA_INTERFACE"; then
    printf 'RUNNING (%s)' "$AMNEZIA_INTERFACE"
  else
    shiva_service_state "$AMNEZIA_SERVICE"
  fi
}

shiva_service_level() {
  case "$1" in
    RUNNING*) printf 'ok' ;;
    "NOT INSTALLED" | UNAVAILABLE) printf 'warn' ;;
    *) printf 'fail' ;;
  esac
}

shiva_root_disk() {
  local root_source disk
  shiva_have findmnt && shiva_have lsblk || return 1

  root_source="$(findmnt -n -o SOURCE / 2>/dev/null)" || return 1
  root_source="${root_source%%\[*}"
  [[ "$root_source" == /dev/* ]] || return 1

  disk="$(
    lsblk -s -r -n -p -o NAME,TYPE "$root_source" 2>/dev/null |
      awk '$2 == "disk" {print $1; exit}'
  )"
  [[ -n "$disk" ]] || return 1
  printf '%s' "$disk"
}

shiva_disk_model() {
  local disk="$1" model
  model="$(lsblk -d -n -o MODEL "$disk" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  printf '%s' "$model"
}

shiva_smart_health() {
  local disk="$1" output rc
  SHIVA_SMART_STATE="unknown"
  SHIVA_SMART_OUTPUT=""
  SHIVA_SMART_ERROR=""

  if ! shiva_have smartctl; then
    SHIVA_SMART_STATE="not_installed"
    return 0
  fi

  if ! shiva_have sudo; then
    SHIVA_SMART_STATE="requires_sudo"
    SHIVA_SMART_ERROR="sudo command not found"
    return 0
  fi

  if output="$(sudo -n smartctl -H "$disk" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
  SHIVA_SMART_OUTPUT="$output"
  if (( rc == 0 )) &&
    grep -Fq 'SMART overall-health self-assessment test result: PASSED' <<<"$output"; then
    SHIVA_SMART_STATE="passed"
    return 0
  fi
  if grep -Fq 'SMART overall-health self-assessment test result: FAILED' <<<"$output"; then
    SHIVA_SMART_STATE="failed"
    return 0
  fi
  if grep -Eqi 'password is required|a password is required|not allowed|sudoers|permission denied|no new privileges|sudo\.conf|effective uid is not 0' <<<"$output"; then
    SHIVA_SMART_STATE="requires_sudo"
    SHIVA_SMART_ERROR="$output"
    return 0
  fi
  SHIVA_SMART_ERROR="${output:-smartctl exited with code $rc without a recognized SMART result}"
  return 0
}

shiva_pause() {
  [[ -t 0 ]] || return 0
  printf '\nPress Enter to continue...'
  read -r _
}

shiva_require_root() {
  if (( EUID != 0 )); then
    printf 'This action requires root. Run with sudo.\n' >&2
    return 1
  fi
}

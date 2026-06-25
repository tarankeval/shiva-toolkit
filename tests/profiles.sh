#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/profiles"
mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/hostnamectl" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--static" ]] || exit 1
printf 'ananda\n'
EOF
chmod +x "$test_dir/bin/hostnamectl"

read_profile() {
  local host="$1"
  SHIVA_HOSTNAME="$host" \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    bash -c '
      source "$1/lib/shiva/common.sh"
      printf "%s|%s|%s|%s|%s|%s\n" \
        "$SHIVA_PROFILE_NAME" "$CHECK_DOCKER" "$CHECK_OPENVPN" \
        "$CHECK_OCSERV" "$CHECK_SMART" "$CHECK_TEMPERATURE"
    ' _ "$PROJECT_DIR"
}

[[ "$(read_profile shiva-server)" == "shiva-server|false|true|false|true|true" ]]
[[ "$(read_profile shiva-vpn)" == "shiva-vpn|false|true|true|true|true" ]]
[[ "$(read_profile ananda)" == "ananda|true|false|false|true|true" ]]

detected="$(
  PATH="$test_dir/bin:$PATH" \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    bash -c '
      source "$1/lib/shiva/common.sh"
      printf "%s|%s|%s\n" "$SHIVA_HOSTNAME" "$CHECK_DOCKER" "$CHECK_OPENVPN"
    ' _ "$PROJECT_DIR"
)"
[[ "$detected" == "ananda|true|false" ]]

shiva_server_health="$(
  NO_COLOR=1 \
  SHIVA_HOSTNAME=shiva-server \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/empty-profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    "$PROJECT_DIR/bin/shiva-health" 2>/dev/null || true
)"
! grep -qi 'docker' <<<"$shiva_server_health"

shiva_server_doctor="$(
  NO_COLOR=1 \
  SHIVA_HOSTNAME=shiva-server \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/empty-profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    "$PROJECT_DIR/bin/shiva-doctor" 2>/dev/null || true
)"
! grep -qi 'docker' <<<"$shiva_server_doctor"

shiva_server_help="$(
  NO_COLOR=1 \
  SHIVA_HOSTNAME=shiva-server \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/empty-profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    "$PROJECT_DIR/bin/shiva" --help
)"
! grep -qi 'docker' <<<"$shiva_server_help"

shiva_server_menu="$(
  printf '0\n' |
    NO_COLOR=1 \
    SHIVA_HOSTNAME=shiva-server \
    SHIVA_CONFIG="$test_dir/missing.conf" \
    SHIVA_PROFILE_DIR="$test_dir/empty-profiles" \
    SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
      "$PROJECT_DIR/bin/shiva"
)"
! grep -qi 'docker' <<<"$shiva_server_menu"

cat >"$test_dir/profiles/shiva-server.conf" <<'EOF'
CHECK_TEMPERATURE=false
CHECK_SMART=false
CHECK_INTERFACES=false
CHECK_DOCKER=false
CHECK_OPENVPN=false
CHECK_OCSERV=true
CHECK_AMNEZIA=false
EOF

override="$(
  SHIVA_HOSTNAME=shiva-server \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    bash -c '
      source "$1/lib/shiva/common.sh"
      printf "%s|%s|%s|%s|%s|%s\n" \
        "$CHECK_TEMPERATURE" "$CHECK_SMART" "$CHECK_INTERFACES" \
        "$CHECK_DOCKER" "$CHECK_OPENVPN" "$CHECK_OCSERV"
    ' _ "$PROJECT_DIR"
)"
[[ "$override" == "false|false|false|false|false|true" ]]

docker_output="$(
  NO_COLOR=1 \
  SHIVA_HOSTNAME=shiva-server \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    "$PROJECT_DIR/bin/shiva-docker"
)"
[[ -z "$docker_output" ]]

network_output="$(
  NO_COLOR=1 \
  SHIVA_HOSTNAME=shiva-server \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    "$PROJECT_DIR/bin/shiva-network"
)"
! grep -q '^Interfaces$' <<<"$network_output"

cat >"$test_dir/profiles/quiet.conf" <<'EOF'
CHECK_TEMPERATURE=false
CHECK_SMART=false
CHECK_INTERFACES=false
CHECK_DOCKER=false
CHECK_OPENVPN=false
CHECK_OCSERV=false
CHECK_AMNEZIA=false
EOF

quiet_vpn="$(
  NO_COLOR=1 \
  SHIVA_HOSTNAME=quiet \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    "$PROJECT_DIR/bin/shiva-vpn"
)"
[[ -z "$quiet_vpn" ]]

quiet_health="$(
  NO_COLOR=1 \
  SHIVA_HOSTNAME=quiet \
  SHIVA_CONFIG="$test_dir/missing.conf" \
  SHIVA_PROFILE_DIR="$test_dir/profiles" \
  SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
    "$PROJECT_DIR/bin/shiva-health" 2>/dev/null || true
)"
! grep -Eq 'CPU|SSD|Interfaces|OPENVPN|OCSERV|AMNEZIA|DOCKER' <<<"$quiet_health"

quiet_menu="$(
  printf '0\n' |
    NO_COLOR=1 \
    SHIVA_HOSTNAME=quiet \
    SHIVA_CONFIG="$test_dir/missing.conf" \
    SHIVA_PROFILE_DIR="$test_dir/profiles" \
    SHIVA_BUILTIN_PROFILE_DIR="$PROJECT_DIR/lib/shiva/profiles" \
      "$PROJECT_DIR/bin/shiva"
)"
! grep -Eq 'VPN Status|Docker' <<<"$quiet_menu"

printf 'Profile tests passed.\n'

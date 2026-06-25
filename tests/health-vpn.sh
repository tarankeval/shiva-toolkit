#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
fake_bin="$test_dir/bin"
mkdir -p "$fake_bin"

write_command() {
  local name="$1"
  shift
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$@"
  } >"$fake_bin/$name"
  chmod +x "$fake_bin/$name"
}

write_command findmnt 'printf "/dev/mapper/vg-root\n"'
write_command lsblk '
case "$*" in
  *"NAME,TYPE"*) printf "/dev/mapper/vg-root lvm\n/dev/sda2 part\n/dev/sda disk\n" ;;
  *MODEL*) printf "KINGSTON SA400S3\n" ;;
esac'
write_command smartctl 'exit 0'
write_command sudo '
case "${SMART_SUDO_MODE:-passed}" in
  passed)
    printf "SMART overall-health self-assessment test result: PASSED\n"
    exit 0
    ;;
  failed)
    printf "SMART overall-health self-assessment test result: FAILED\n"
    exit 8
    ;;
  denied)
    printf "sudo: a password is required\n" >&2
    exit 1
    ;;
  misleading)
    printf "SMART overall-health self-assessment test result: PASSED\n"
    exit 4
    ;;
  unknown)
    printf "Device open failed: transport error\n" >&2
    exit 2
    ;;
esac'
write_command ip '
if [[ "$*" == "link show dev tun0" ]]; then
  exit 0
fi
exit 1'
write_command systemctl 'exit 1'

export PATH="$fake_bin:$PATH"
export SHIVA_CONFIG="$test_dir/missing.conf"
export NO_COLOR=1

source "$PROJECT_DIR/lib/shiva/common.sh"

disk="$(shiva_root_disk)"
[[ "$disk" == "/dev/sda" ]]
[[ "$(shiva_disk_model "$disk")" == "KINGSTON SA400S3" ]]
shiva_smart_health "$disk"
[[ "$SHIVA_SMART_STATE" == "passed" ]]
SMART_SUDO_MODE=failed shiva_smart_health "$disk"
[[ "$SHIVA_SMART_STATE" == "failed" ]]
SMART_SUDO_MODE=denied shiva_smart_health "$disk"
[[ "$SHIVA_SMART_STATE" == "requires_sudo" ]]
SMART_SUDO_MODE=misleading shiva_smart_health "$disk"
[[ "$SHIVA_SMART_STATE" == "unknown" ]]
SMART_SUDO_MODE=unknown shiva_smart_health "$disk"
[[ "$SHIVA_SMART_STATE" == "unknown" ]]
grep -q 'transport error' <<<"$SHIVA_SMART_ERROR"
mv "$fake_bin/smartctl" "$fake_bin/smartctl.disabled"
shiva_smart_health "$disk"
[[ "$SHIVA_SMART_STATE" == "not_installed" ]]
mv "$fake_bin/smartctl.disabled" "$fake_bin/smartctl"
mv "$fake_bin/sudo" "$fake_bin/sudo.disabled"
shiva_smart_health "$disk"
[[ "$SHIVA_SMART_STATE" == "requires_sudo" ]]
mv "$fake_bin/sudo.disabled" "$fake_bin/sudo"

health_profile="$test_dir/health.conf"
cat >"$health_profile" <<'EOF'
CHECK_TEMPERATURE=false
CHECK_SMART=true
CHECK_INTERFACES=false
CHECK_DOCKER=false
CHECK_OPENVPN=false
CHECK_OCSERV=false
CHECK_AMNEZIA=false
SMART_DISK="/dev/sda"
EOF

health_output="$(
  SMART_SUDO_MODE=passed SHIVA_CONFIG="$health_profile" \
    "$PROJECT_DIR/bin/shiva-health" 2>/dev/null || true
)"
grep -q 'SSD.*PASSED (/dev/sda KINGSTON SA400S3)' <<<"$health_output"
grep -q 'Health Summary' <<<"$health_output"
grep -q 'Passed.*[0-9]' <<<"$health_output"
grep -q 'Warning.*[0-9]' <<<"$health_output"
grep -q 'Errors.*[0-9]' <<<"$health_output"
grep -q 'Server Health' <<<"$health_output"

failed_output="$(
  SMART_SUDO_MODE=failed SHIVA_CONFIG="$health_profile" \
    "$PROJECT_DIR/bin/shiva-health" 2>/dev/null || true
)"
grep -q 'SSD.*SMART FAILED (/dev/sda KINGSTON SA400S3)' <<<"$failed_output"

sudo_output="$(
  SMART_SUDO_MODE=denied SHIVA_CONFIG="$health_profile" \
    "$PROJECT_DIR/bin/shiva-health" 2>/dev/null || true
)"
grep -q 'SSD.*SMART REQUIRES SUDO' <<<"$sudo_output"

doctor_output="$(
  SMART_SUDO_MODE=unknown SHIVA_CONFIG="$health_profile" \
    "$PROJECT_DIR/bin/shiva-doctor" 2>/dev/null || true
)"
grep -q 'SMART detail.*transport error' <<<"$doctor_output"

vpn_health_profile="$test_dir/vpn-health.conf"
cat >"$vpn_health_profile" <<'EOF'
CHECK_TEMPERATURE=false
CHECK_SMART=false
CHECK_INTERFACES=true
CHECK_DOCKER=false
CHECK_OPENVPN=true
CHECK_OCSERV=false
CHECK_AMNEZIA=false
REQUIRED_INTERFACE="tun0"
OPENVPN_INTERFACE="tun0"
EOF

vpn_health_output="$(
  SHIVA_CONFIG="$vpn_health_profile" \
    "$PROJECT_DIR/bin/shiva-health" 2>/dev/null || true
)"
grep -q 'Interface tun0.*UP' <<<"$vpn_health_output"
grep -q 'OPENVPN CLIENT.*RUNNING (tun0)' <<<"$vpn_health_output"
! grep -q 'Interface tun0.*DOWN' <<<"$vpn_health_output"

vpn_output="$(
  CHECK_OPENVPN=true CHECK_OCSERV=false CHECK_AMNEZIA=false \
    "$PROJECT_DIR/bin/shiva-vpn"
)"
grep -q 'OPENVPN CLIENT.*RUNNING (tun0)' <<<"$vpn_output"
! grep -q 'OCSERV' <<<"$vpn_output"
! grep -q 'AMNEZIA' <<<"$vpn_output"

printf 'Health and VPN tests passed.\n'

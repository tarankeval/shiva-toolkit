#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
stage_history="$stage/history.log"

for script in "$PROJECT_DIR"/bin/shiva* "$PROJECT_DIR"/lib/shiva/*.sh \
  "$PROJECT_DIR"/install.sh "$PROJECT_DIR"/packaging/*.sh \
  "$PROJECT_DIR"/tests/*.sh; do
  bash -n "$script"
done

version_output="$(NO_COLOR=1 "$PROJECT_DIR/bin/shiva" --version)"
help_output="$(NO_COLOR=1 "$PROJECT_DIR/bin/shiva" --help)"
grep -q '^Shiva Toolkit v1.1.0-dev$' <<<"$version_output"
grep -q 'Shiva Toolkit v1.1.0-dev (Automation Preview)' <<<"$help_output"
grep -q 'repair   Plan or apply guided repairs' <<<"$help_output"
grep -q 'watchdog Run automation checks' <<<"$help_output"
grep -q 'history  Show operational history' <<<"$help_output"
grep -q 'advisor  Show operational recommendations' <<<"$help_output"
grep -q 'notify   Send configured notifications' <<<"$help_output"
NO_COLOR=1 "$PROJECT_DIR/bin/shiva-doctor" >/dev/null || [[ $? -eq 2 ]]
NO_COLOR=1 SHIVA_HISTORY_FILE="$stage_history" "$PROJECT_DIR/bin/shiva-history" >/dev/null
NO_COLOR=1 "$PROJECT_DIR/bin/shiva-repair" --help >/dev/null
NO_COLOR=1 "$PROJECT_DIR/bin/shiva-watchdog" --help >/dev/null
NO_COLOR=1 "$PROJECT_DIR/bin/shiva-advisor" --help >/dev/null
NO_COLOR=1 "$PROJECT_DIR/bin/shiva-notify" --help >/dev/null
bash "$PROJECT_DIR/tests/health-vpn.sh"
bash "$PROJECT_DIR/tests/profiles.sh"
bash "$PROJECT_DIR/tests/automation.sh"

install_output="$(DESTDIR="$stage" "$PROJECT_DIR/install.sh")"
grep -q 'Shiva Toolkit v1.1.0-dev Automation Preview installed' <<<"$install_output"
test -x "$stage/usr/local/bin/shiva"
test -r "$stage/usr/local/lib/shiva/common.sh"
test -r "$stage/usr/local/lib/shiva/profiles/shiva-server.conf"
grep -q '^CHECK_DOCKER=false$' \
  "$stage/usr/local/lib/shiva/profiles/shiva-server.conf"
test -r "$stage/usr/local/lib/shiva/profiles/shiva-vpn.conf"
test -r "$stage/usr/local/lib/shiva/profiles/ananda.conf"
test -d "$stage/etc/shiva/profiles"
test -r "$stage/etc/shiva/shiva.conf"
test -r "$stage/etc/systemd/system/shiva-watchdog.service"
grep -q 'ExecStart=/usr/local/bin/shiva-watchdog' \
  "$stage/etc/systemd/system/shiva-watchdog.service"

printf 'Smoke tests passed.\n'

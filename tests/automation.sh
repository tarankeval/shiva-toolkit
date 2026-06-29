#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

history_file="$stage/history.log"
state_file="$stage/watchdog.state"

cat >"$history_file" <<'EOF'
2026-06-24T10:00:00+02:00	ok	watchdog	all checks passed
2026-06-24T10:05:00+02:00	info	repair	network repair planned for lo
2026-06-25T11:00:00+02:00	fail	watchdog	2 failure(s) detected
EOF

history_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    "$PROJECT_DIR/bin/shiva-history" --module watchdog 10
)"
grep -q 'watchdog' <<<"$history_output"
grep -q 'all checks passed' <<<"$history_output"
grep -q '2 failure(s) detected' <<<"$history_output"
! grep -q 'network repair planned' <<<"$history_output"

repair_history="$stage/repair-history.log"
repair_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$repair_history" SHIVA_REPAIR_INTERFACE=lo \
    "$PROJECT_DIR/bin/shiva-repair" network
)"
grep -q 'PLAN bring lo down' <<<"$repair_output"
grep -q 'PLAN bring lo up' <<<"$repair_output"
grep -q $'\tinfo\trepair\tnetwork repair planned for lo' "$repair_history"

repair_status="$(
  NO_COLOR=1 SHIVA_REPAIR_INTERFACE=lo "$PROJECT_DIR/bin/shiva-repair" status
)"
grep -q 'Default mode' <<<"$repair_status"
grep -q 'DRY RUN' <<<"$repair_status"
grep -q 'Network target' <<<"$repair_status"

printf 'ok\n' >"$state_file"
NO_COLOR=1 SHIVA_WATCHDOG_STATE_FILE="$state_file" \
  "$PROJECT_DIR/bin/shiva-watchdog" --status >/dev/null

printf 'fail:3\n' >"$state_file"
if NO_COLOR=1 SHIVA_WATCHDOG_STATE_FILE="$state_file" \
  "$PROJECT_DIR/bin/shiva-watchdog" --status >/dev/null; then
  printf 'watchdog --status should fail for fail state\n' >&2
  exit 1
else
  rc=$?
  [[ "$rc" -eq 2 ]]
fi

printf 'Automation tests passed.\n'

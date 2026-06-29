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

history_fail_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    "$PROJECT_DIR/bin/shiva-history" --level fail 10
)"
grep -q '2 failure(s) detected' <<<"$history_fail_output"
! grep -q 'all checks passed' <<<"$history_fail_output"

history_summary="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    "$PROJECT_DIR/bin/shiva-history" --summary 10
)"
grep -q 'Total: 3' <<<"$history_summary"
grep -q 'By level' <<<"$history_summary"
grep -q 'watchdog' <<<"$history_summary"

advisor_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-advisor" 10
)"
grep -q 'Recommendations' <<<"$advisor_output"
grep -q 'shiva history --level fail' <<<"$advisor_output"

advisor_json="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-advisor" --json 10
)"
grep -q '"history_window":10' <<<"$advisor_json"
grep -q '"failures":1' <<<"$advisor_json"
grep -q '"recommendations":\[' <<<"$advisor_json"

NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
  SHIVA_WATCHDOG_STATE_FILE="$state_file" \
  SHIVA_NOTIFY_STATE_DIR="$stage/notify" \
  SHIVA_TELEGRAM_ENABLED=false \
  "$PROJECT_DIR/bin/shiva-advisor" --notify 10 >/dev/null
grep -q 'notification skipped: telegram disabled' "$history_file"

dashboard_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_NODES="local:server:localhost vpn:VPN:shiva-vpn" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-dashboard" 10
)"
grep -q 'SHIVA DASHBOARD' <<<"$dashboard_output"
grep -q 'Watchdog' <<<"$dashboard_output"
grep -q 'Service' <<<"$dashboard_output"
grep -q 'Nodes' <<<"$dashboard_output"
grep -q 'Recent failures' <<<"$dashboard_output"

dashboard_json="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_NODES="local:server:localhost vpn:VPN:shiva-vpn" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-dashboard" --json 10
)"
grep -q '"failures":1' <<<"$dashboard_json"
grep -q '"service":' <<<"$dashboard_json"
grep -q '"nodes":2' <<<"$dashboard_json"
grep -q '"telegram":"disabled"' <<<"$dashboard_json"

repair_history="$stage/repair-history.log"
repair_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$repair_history" SHIVA_REPAIR_INTERFACE=lo \
    "$PROJECT_DIR/bin/shiva-repair" network
)"
grep -q 'PLAN bring lo down' <<<"$repair_output"
grep -q 'PLAN bring lo up' <<<"$repair_output"
grep -q $'\tinfo\trepair\tnetwork repair planned for lo' "$repair_history"

repair_verify_rc=0
repair_verify_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$repair_history" SHIVA_REPAIR_INTERFACE=lo \
    "$PROJECT_DIR/bin/shiva-repair" --verify-after network
)" || repair_verify_rc=$?
[[ "$repair_verify_rc" -ne 0 ]]
grep -q 'SHIVA VERIFY NETWORK' <<<"$repair_verify_output"
grep -Eq $'\t(repair)\t(network verification passed|network verification failed)' "$repair_history"

repair_status="$(
  NO_COLOR=1 SHIVA_REPAIR_INTERFACE=lo "$PROJECT_DIR/bin/shiva-repair" status
)"
grep -q 'Default mode' <<<"$repair_status"
grep -q 'DRY RUN' <<<"$repair_status"
grep -q 'Network target' <<<"$repair_status"

verify_dns_output="$(
  NO_COLOR=1 "$PROJECT_DIR/bin/shiva-repair" verify dns || true
)"
grep -q 'SHIVA VERIFY DNS' <<<"$verify_dns_output"
grep -Eq 'DNS[[:space:]]+(OK|FAILED)' <<<"$verify_dns_output"

notify_output="$(
  NO_COLOR=1 "$PROJECT_DIR/bin/shiva-notify" --dry-run --category test "test message"
)"
grep -q 'DRY RUN' <<<"$notify_output"
grep -q 'Category' <<<"$notify_output"
grep -q 'test message' <<<"$notify_output"

notify_status="$(
  NO_COLOR=1 "$PROJECT_DIR/bin/shiva-notify" status
)"
grep -q 'Telegram' <<<"$notify_status"
grep -q 'Cooldown' <<<"$notify_status"

service_plan="$(
  NO_COLOR=1 "$PROJECT_DIR/bin/shiva-service" enable
)"
grep -q 'PLAN systemctl enable shiva-watchdog' <<<"$service_plan"

nodes_output="$(
  NO_COLOR=1 SHIVA_NODES="local:server:localhost vpn:VPN:shiva-vpn" \
    "$PROJECT_DIR/bin/shiva-nodes"
)"
grep -q 'local' <<<"$nodes_output"
grep -q 'vpn' <<<"$nodes_output"

nodes_json="$(
  NO_COLOR=1 SHIVA_NODES="local:server:localhost vpn:VPN:shiva-vpn" \
    "$PROJECT_DIR/bin/shiva-nodes" --json
)"
grep -q '"nodes":\[' <<<"$nodes_json"
grep -q '"name":"vpn"' <<<"$nodes_json"

printf 'ok\n' >"$state_file"
NO_COLOR=1 SHIVA_WATCHDOG_STATE_FILE="$state_file" \
  "$PROJECT_DIR/bin/shiva-watchdog" --status >/dev/null

watchdog_config="$(
  NO_COLOR=1 SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-watchdog" --config
)"
grep -q 'Interval' <<<"$watchdog_config"
grep -q 'Auto repair' <<<"$watchdog_config"
grep -q 'Repair targets' <<<"$watchdog_config"

printf 'fail:3\n' >"$state_file"
if NO_COLOR=1 SHIVA_WATCHDOG_STATE_FILE="$state_file" \
  "$PROJECT_DIR/bin/shiva-watchdog" --status >/dev/null; then
  printf 'watchdog --status should fail for fail state\n' >&2
  exit 1
else
  rc=$?
  [[ "$rc" -eq 2 ]]
fi

printf 'fail:3:network,dns\n' >"$state_file"
watchdog_status="$(
  NO_COLOR=1 SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-watchdog" --status || [[ "$?" -eq 2 ]]
)"
grep -q '3 failure(s)' <<<"$watchdog_status"
grep -q 'network,dns' <<<"$watchdog_status"

printf 'Automation tests passed.\n'

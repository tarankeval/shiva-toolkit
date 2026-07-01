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
2026-06-25T11:05:00+02:00	fail	watchdog	DNS failed
2026-06-25T11:10:00+02:00	fail	watchdog	OpenVPN disconnected
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
grep -q 'Total: 5' <<<"$history_summary"
grep -q 'By level' <<<"$history_summary"
grep -q 'watchdog' <<<"$history_summary"

history_date_json="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    "$PROJECT_DIR/bin/shiva-history" --json --date 2026-06-25 --level ERROR --service openvpn 10
)"
grep -q '"schema":1' <<<"$history_date_json"
grep -q '"source":"history"' <<<"$history_date_json"
grep -q '"OpenVPN disconnected"' <<<"$history_date_json"
! grep -q 'DNS failed' <<<"$history_date_json"

cat >"$stage/health.json" <<'EOF'
{"schema":1,"overall":"previous","health_percent":0}
EOF
health_json_output="$(
  NO_COLOR=1 SHIVA_HEALTH_SNAPSHOT_FILE="$stage/health.json" \
    SHIVA_HEALTH_TIMELINE_FILE="$stage/health.timeline" \
    SHIVA_EVENT_FILE="$stage/events.log" \
    SHIVA_NOTIFY_QUEUE_FILE="$stage/notify.queue" \
    "$PROJECT_DIR/bin/shiva-health" --json || true
)"
grep -q '"schema":1' <<<"$health_json_output"
grep -q '"overall":' <<<"$health_json_output"
grep -q '"checks":\[' <<<"$health_json_output"
grep -q '"key":"dns"' <<<"$health_json_output"
grep -q '"key":"uptime"' <<<"$health_json_output"
grep -q '"key":"load_average"' <<<"$health_json_output"
grep -q '"key":"root_free"' <<<"$health_json_output"
grep -q '"timestamp":' <<<"$health_json_output"
grep -q '"metrics":' <<<"$health_json_output"
grep -q '"events":\[' <<<"$health_json_output"
grep -q '"services":\[' <<<"$health_json_output"
test -r "$stage/health.json"
test -r "$stage/health.timeline"
test -r "$stage/events.log"
test -r "$stage/notify.queue"
grep -q 'overall changed from previous' "$stage/events.log"
grep -q 'overall changed from previous' "$stage/notify.queue"

health_timeline_before="$(wc -l <"$stage/health.timeline" | tr -d ' ')"
NO_COLOR=1 SHIVA_HEALTH_SNAPSHOT_FILE="$stage/health.json" \
  SHIVA_HEALTH_TIMELINE_FILE="$stage/health.timeline" \
  SHIVA_EVENT_FILE="$stage/events.log" \
  SHIVA_NOTIFY_QUEUE_FILE="$stage/notify.queue" \
  "$PROJECT_DIR/bin/shiva-health" --json >/dev/null || true
health_timeline_after="$(wc -l <"$stage/health.timeline" | tr -d ' ')"
(( health_timeline_after > health_timeline_before ))

state_output="$(
  NO_COLOR=1 SHIVA_HEALTH_SNAPSHOT_FILE="$stage/health.json" \
    SHIVA_HEALTH_TIMELINE_FILE="$stage/health.timeline" \
    SHIVA_EVENT_FILE="$stage/events.log" \
    SHIVA_NOTIFY_QUEUE_FILE="$stage/notify.queue" \
    "$PROJECT_DIR/bin/shiva-state"
)"
grep -q 'SHIVA STATE' <<<"$state_output"
grep -q 'Health snapshot' <<<"$state_output"
grep -q 'Snapshot age' <<<"$state_output"
grep -q 'Timeline entries' <<<"$state_output"
grep -q 'Notify queue' <<<"$state_output"

state_json="$(
  NO_COLOR=1 SHIVA_HEALTH_SNAPSHOT_FILE="$stage/health.json" \
    SHIVA_HEALTH_TIMELINE_FILE="$stage/health.timeline" \
    SHIVA_EVENT_FILE="$stage/events.log" \
    SHIVA_NOTIFY_QUEUE_FILE="$stage/notify.queue" \
    "$PROJECT_DIR/bin/shiva-state" --json
)"
grep -q '"schema":1' <<<"$state_json"
grep -q '"source":"state"' <<<"$state_json"
grep -q '"health_snapshot":"' <<<"$state_json"
grep -q '"snapshot_age_seconds":' <<<"$state_json"
grep -q '"timestamp":' <<<"$state_json"
grep -q '"timeline_entries":' <<<"$state_json"
grep -q '"events":' <<<"$state_json"
grep -q '"notify_queue_messages":' <<<"$state_json"
grep -q '"limits":' <<<"$state_json"

seq 1 5 >"$stage/cleanup.timeline"
seq 1 5 >"$stage/cleanup.events"
seq 1 5 >"$stage/cleanup.queue"
cleanup_dry="$(
  NO_COLOR=1 SHIVA_HEALTH_SNAPSHOT_FILE="$stage/health.json" \
    SHIVA_HEALTH_TIMELINE_FILE="$stage/cleanup.timeline" \
    SHIVA_EVENT_FILE="$stage/cleanup.events" \
    SHIVA_NOTIFY_QUEUE_FILE="$stage/cleanup.queue" \
    SHIVA_TIMELINE_MAX_LINES=3 \
    SHIVA_EVENTS_MAX_LINES=2 \
    SHIVA_NOTIFY_QUEUE_MAX_LINES=4 \
    "$PROJECT_DIR/bin/shiva-state" cleanup --dry-run
)"
grep -q 'Health snapshot' <<<"$cleanup_dry"
grep -q 'PLAN trim Health timeline' <<<"$cleanup_dry"
grep -q 'PLAN trim Events log' <<<"$cleanup_dry"
grep -q 'PLAN trim Notify queue' <<<"$cleanup_dry"
[[ "$(wc -l <"$stage/cleanup.timeline" | tr -d ' ')" -eq 5 ]]
[[ "$(wc -l <"$stage/cleanup.events" | tr -d ' ')" -eq 5 ]]
[[ "$(wc -l <"$stage/cleanup.queue" | tr -d ' ')" -eq 5 ]]
test -r "$stage/health.json"

cleanup_apply="$(
  NO_COLOR=1 SHIVA_HEALTH_SNAPSHOT_FILE="$stage/health.json" \
    SHIVA_HEALTH_TIMELINE_FILE="$stage/cleanup.timeline" \
    SHIVA_EVENT_FILE="$stage/cleanup.events" \
    SHIVA_NOTIFY_QUEUE_FILE="$stage/cleanup.queue" \
    SHIVA_TIMELINE_MAX_LINES=3 \
    SHIVA_EVENTS_MAX_LINES=2 \
    SHIVA_NOTIFY_QUEUE_MAX_LINES=4 \
    "$PROJECT_DIR/bin/shiva-state" cleanup --apply
)"
grep -q 'RUN trim Health timeline' <<<"$cleanup_apply"
grep -q 'RUN trim Events log' <<<"$cleanup_apply"
grep -q 'RUN trim Notify queue' <<<"$cleanup_apply"
[[ "$(wc -l <"$stage/cleanup.timeline" | tr -d ' ')" -eq 3 ]]
[[ "$(wc -l <"$stage/cleanup.events" | tr -d ' ')" -eq 2 ]]
[[ "$(wc -l <"$stage/cleanup.queue" | tr -d ' ')" -eq 4 ]]
test -r "$stage/health.json"

seq 1 5 >"$stage/limited.timeline"
NO_COLOR=1 SHIVA_HEALTH_SNAPSHOT_FILE="$stage/limited-health.json" \
  SHIVA_HEALTH_TIMELINE_FILE="$stage/limited.timeline" \
  SHIVA_EVENT_FILE="$stage/limited-events.log" \
  SHIVA_NOTIFY_QUEUE_FILE="$stage/limited-queue.log" \
  SHIVA_TIMELINE_MAX_LINES=3 \
  "$PROJECT_DIR/bin/shiva-health" --json >/dev/null || true
[[ "$(wc -l <"$stage/limited.timeline" | tr -d ' ')" -eq 3 ]]

health_timeline_json="$(
  NO_COLOR=1 SHIVA_HEALTH_TIMELINE_FILE="$stage/health.timeline" \
    "$PROJECT_DIR/bin/shiva-history" --health --json 10
)"
grep -q '"source":"health-timeline"' <<<"$health_timeline_json"
grep -q '"points":\[' <<<"$health_timeline_json"

log_watchdog_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    "$PROJECT_DIR/bin/shiva-log" watchdog 10
)"
grep -q 'SHIVA LOG WATCHDOG' <<<"$log_watchdog_output"
grep -q 'OpenVPN disconnected' <<<"$log_watchdog_output"
! grep -q 'network repair planned' <<<"$log_watchdog_output"

log_dns_json="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    "$PROJECT_DIR/bin/shiva-log" dns --json 10
)"
grep -q '"schema":1' <<<"$log_dns_json"
grep -q '"source":"log"' <<<"$log_dns_json"
grep -q '"target":"dns"' <<<"$log_dns_json"
grep -q '"DNS failed"' <<<"$log_dns_json"
! grep -q 'OpenVPN disconnected' <<<"$log_dns_json"

log_vpn_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    "$PROJECT_DIR/bin/shiva-log" vpn 10
)"
grep -q 'OpenVPN disconnected' <<<"$log_vpn_output"

advisor_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-advisor" 10
)"
grep -q 'Recommendations' <<<"$advisor_output"
grep -Eq 'INFO|RECOMMENDED|CRITICAL' <<<"$advisor_output"
grep -q 'shiva history --level fail' <<<"$advisor_output"

advisor_json="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-advisor" --json 10
)"
grep -q '"history_window":10' <<<"$advisor_json"
grep -q '"schema":1' <<<"$advisor_json"
grep -q '"source":"health-engine"' <<<"$advisor_json"
grep -q '"health_percent":' <<<"$advisor_json"
grep -q '"checks":\[' <<<"$advisor_json"
grep -q '"recommendations":\[' <<<"$advisor_json"
grep -q '"level":"CRITICAL"\|"level":"RECOMMENDED"\|"level":"INFO"' <<<"$advisor_json"

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
    SHIVA_DASHBOARD_SNAPSHOT_FILE="$stage/dashboard.json" \
    "$PROJECT_DIR/bin/shiva-dashboard"
)"
grep -q 'SHIVA DASHBOARD' <<<"$dashboard_output"
grep -q 'Health' <<<"$dashboard_output"
grep -q 'Watchdog' <<<"$dashboard_output"
grep -q 'Nodes' <<<"$dashboard_output"
grep -q 'Attention' <<<"$dashboard_output"
grep -q 'Uptime' <<<"$dashboard_output"
grep -q 'Load average' <<<"$dashboard_output"
grep -q 'Root free' <<<"$dashboard_output"
test -r "$stage/dashboard.json"
grep -q '"recent_warnings":' "$stage/dashboard.json"

dashboard_compact_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_DASHBOARD_SNAPSHOT_FILE="$stage/dashboard-compact.json" \
    "$PROJECT_DIR/bin/shiva-dashboard" --compact
)"
grep -q 'SHIVA DASHBOARD' <<<"$dashboard_compact_output"
! grep -q 'Attention' <<<"$dashboard_compact_output"
! grep -q 'Passed' <<<"$dashboard_compact_output"

dashboard_rich_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_DASHBOARD_SNAPSHOT_FILE="$stage/dashboard-rich.json" \
    "$PROJECT_DIR/bin/shiva-dashboard" --rich
)"
grep -q 'System' <<<"$dashboard_rich_output"
grep -q 'State' <<<"$dashboard_rich_output"
grep -q 'History' <<<"$dashboard_rich_output"

dashboard_json="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_NODES="local:server:localhost vpn:VPN:shiva-vpn" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    SHIVA_DASHBOARD_SNAPSHOT_FILE="$stage/dashboard-json.json" \
    "$PROJECT_DIR/bin/shiva-dashboard" --json
)"
grep -q '"schema":1' <<<"$dashboard_json"
grep -q '"source":"health-engine"' <<<"$dashboard_json"
grep -q '"health_percent":' <<<"$dashboard_json"
grep -q '"nodes":2' <<<"$dashboard_json"
grep -q '"telegram":"disabled"' <<<"$dashboard_json"
grep -q '"updated_at":' <<<"$dashboard_json"
grep -q '"uptime":' <<<"$dashboard_json"
grep -q '"load_average":' <<<"$dashboard_json"
grep -q '"root_free":' <<<"$dashboard_json"
grep -q '"recent_warnings":' <<<"$dashboard_json"
test -r "$stage/dashboard-json.json"

dashboard_watch_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_NODES="local:server:localhost vpn:VPN:shiva-vpn" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-dashboard" --watch --interval 0 --count 1
)"
grep -q 'Refresh' <<<"$dashboard_watch_output"
grep -q 'Attention' <<<"$dashboard_watch_output"

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

NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
  SHIVA_NOTIFY_STATE_DIR="$stage/notify" \
  SHIVA_TELEGRAM_ENABLED=false \
  "$PROJECT_DIR/bin/shiva-notify" test >/dev/null
grep -q 'notification skipped: telegram disabled' "$history_file"

readonly_history_dir="$stage/readonly-history"
mkdir -p "$readonly_history_dir"
chmod 500 "$readonly_history_dir"
readonly_history_error="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$readonly_history_dir/history.log" \
    "$PROJECT_DIR/bin/shiva-notify" "history write should be silent" 2>&1 >/dev/null
)"
chmod 700 "$readonly_history_dir"
[[ -z "$readonly_history_error" ]]

doctor_state_output="$(
  NO_COLOR=1 SHIVA_STATE_DIR="$stage/state" \
    SHIVA_HISTORY_FILE="$stage/state/history.log" \
    SHIVA_WATCHDOG_STATE_FILE="$stage/state/watchdog.state" \
    SHIVA_NOTIFY_STATE_DIR="$stage/state/notify" \
    "$PROJECT_DIR/bin/shiva-doctor" state
)"
grep -q 'SHIVA DOCTOR STATE' <<<"$doctor_state_output"
grep -q 'WRITABLE' <<<"$doctor_state_output"

doctor_state_json="$(
  NO_COLOR=1 SHIVA_STATE_DIR="$stage/state-json" \
    SHIVA_HISTORY_FILE="$stage/state-json/history.log" \
    SHIVA_WATCHDOG_STATE_FILE="$stage/state-json/watchdog.state" \
    SHIVA_NOTIFY_STATE_DIR="$stage/state-json/notify" \
    "$PROJECT_DIR/bin/shiva-doctor" state --json
)"
grep -q '"schema":1' <<<"$doctor_state_json"
grep -q '"source":"doctor-state"' <<<"$doctor_state_json"
grep -q '"issues":0' <<<"$doctor_state_json"
grep -q '"files":\[' <<<"$doctor_state_json"

doctor_config_output="$(
  NO_COLOR=1 SHIVA_NODES="local:server:localhost" \
    "$PROJECT_DIR/bin/shiva-doctor" config || true
)"
grep -q 'SHIVA DOCTOR CONFIG' <<<"$doctor_config_output"
grep -q 'Profile' <<<"$doctor_config_output"

doctor_config_json="$(
  NO_COLOR=1 SHIVA_NODES="local:server:localhost" \
    "$PROJECT_DIR/bin/shiva-doctor" config --json || true
)"
grep -q '"schema":1' <<<"$doctor_config_json"
grep -q '"source":"doctor-config"' <<<"$doctor_config_json"
grep -q '"profile":' <<<"$doctor_config_json"
grep -q '"nodes":1' <<<"$doctor_config_json"

doctor_release_output="$(
  NO_COLOR=1 "$PROJECT_DIR/bin/shiva-doctor" release
)"
grep -q 'SHIVA DOCTOR RELEASE' <<<"$doctor_release_output"
grep -q 'Release readiness' <<<"$doctor_release_output"

doctor_release_json="$(
  NO_COLOR=1 "$PROJECT_DIR/bin/shiva-doctor" release --json
)"
grep -q '"schema":1' <<<"$doctor_release_json"
grep -q '"source":"doctor-release"' <<<"$doctor_release_json"
grep -q '"issues":0' <<<"$doctor_release_json"
grep -q '"status":"ok"' <<<"$doctor_release_json"
grep -q '"README release doctor"' <<<"$doctor_release_json"

service_plan="$(
  NO_COLOR=1 "$PROJECT_DIR/bin/shiva-service" enable
)"
grep -q 'PLAN systemctl enable shiva-watchdog' <<<"$service_plan"

service_status_output="$(
  NO_COLOR=1 "$PROJECT_DIR/bin/shiva-service" status || true
)"
grep -q 'shiva-watchdog.service' <<<"$service_status_output"

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
grep -q '"schema":1' <<<"$nodes_json"
grep -q '"source":"nodes"' <<<"$nodes_json"
grep -q '"nodes":\[' <<<"$nodes_json"
grep -q '"name":"vpn"' <<<"$nodes_json"

cluster_output="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    SHIVA_NODES="local:server:localhost vpn:VPN:shiva-vpn" \
    "$PROJECT_DIR/bin/shiva-cluster"
)"
grep -q 'SHIVA CLUSTER' <<<"$cluster_output"
grep -q 'Nodes' <<<"$cluster_output"
grep -q 'Watchdog' <<<"$cluster_output"

cluster_json="$(
  NO_COLOR=1 SHIVA_HISTORY_FILE="$history_file" \
    SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    SHIVA_NODES="local:server:localhost vpn:VPN:shiva-vpn" \
    "$PROJECT_DIR/bin/shiva-cluster" --json
)"
grep -q '"schema":1' <<<"$cluster_json"
grep -q '"source":"health-engine"' <<<"$cluster_json"
grep -q '"nodes":2' <<<"$cluster_json"
grep -q '"configured_nodes":1' <<<"$cluster_json"
grep -q '"watchdog":' <<<"$cluster_json"

cat >"$stage/dashboard-snapshot.json" <<'EOF'
{"schema":1,"version":"test","hostname":"snapshot","profile":"snapshot","source":"health-engine","overall":"excellent","health_percent":100,"failures":0,"warnings":0,"watchdog":"ok","telegram":"disabled","checks":[]}
EOF
cluster_snapshot_json="$(
  NO_COLOR=1 SHIVA_DASHBOARD_SNAPSHOT_FILE="$stage/dashboard-snapshot.json" \
    SHIVA_NODES="local:server:localhost vpn:VPN:shiva-vpn" \
    "$PROJECT_DIR/bin/shiva-cluster" --json
)"
grep -q '"health_percent":100' <<<"$cluster_snapshot_json"
grep -q '"watchdog":"ok"' <<<"$cluster_snapshot_json"

printf 'ok\n' >"$state_file"
NO_COLOR=1 SHIVA_WATCHDOG_STATE_FILE="$state_file" \
  "$PROJECT_DIR/bin/shiva-watchdog" --status >/dev/null

watchdog_config="$(
  NO_COLOR=1 SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    "$PROJECT_DIR/bin/shiva-watchdog" --config
)"
grep -q 'Interval' <<<"$watchdog_config"
grep -q 'Failure threshold' <<<"$watchdog_config"
grep -q 'Metadata file' <<<"$watchdog_config"
grep -q 'Auto repair' <<<"$watchdog_config"
grep -q 'Repair targets' <<<"$watchdog_config"

watchdog_help="$(
  NO_COLOR=1 "$PROJECT_DIR/bin/shiva-watchdog" --help
)"
grep -q -- '--watch' <<<"$watchdog_help"

watchdog_watch_output="$(
  NO_COLOR=1 SHIVA_WATCHDOG_INTERVAL=1 SHIVA_WATCHDOG_STATE_FILE="$state_file" \
    SHIVA_WATCHDOG_META_FILE="$stage/watchdog.json" \
    timeout 2 "$PROJECT_DIR/bin/shiva-watchdog" --watch 2>/dev/null || true
)"
grep -q 'Press Ctrl+C to stop' <<<"$watchdog_watch_output"
test -r "$stage/watchdog.json"
grep -q '"consecutive_failures":' "$stage/watchdog.json"

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

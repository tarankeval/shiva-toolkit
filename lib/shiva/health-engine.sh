#!/usr/bin/env bash

# Shared health collection engine. Output format is:
# level<TAB>key<TAB>label<TAB>value

shiva_health_engine_collect() {
  local temp raw_temp temp_level ram_total ram_used ram_percent ram_level
  local smart_disk disk_model disk_label root_percent fs_level interface
  local active_interfaces state failed_units updated_at uptime_seconds uptime_days
  local load1 load5 load15 cpu_count load_level root_avail root_free_percent

  updated_at="$(date -Iseconds)"
  printf '%s\t%s\t%s\t%s\n' "ok" "updated_at" "Updated" "$updated_at"

  if [[ -r /proc/uptime ]]; then
    read -r uptime_seconds _ < /proc/uptime
    uptime_seconds="${uptime_seconds%%.*}"
    uptime_days=$((uptime_seconds / 86400))
    printf '%s\t%s\t%s\t%s\n' "ok" "uptime" "Uptime" "${uptime_days}d $(((uptime_seconds % 86400) / 3600))h"
  else
    printf '%s\t%s\t%s\t%s\n' "warn" "uptime" "Uptime" "UNAVAILABLE"
  fi

  if [[ -r /proc/loadavg ]]; then
    read -r load1 load5 load15 _ < /proc/loadavg
    cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
    load_level="$(
      awk -v load="$load1" -v cpus="$cpu_count" 'BEGIN {
        if (cpus < 1) cpus = 1
        if (load >= cpus * 2) print "fail"
        else if (load >= cpus) print "warn"
        else print "ok"
      }'
    )"
    printf '%s\t%s\t%s\t%s\n' "$load_level" "load_average" "Load average" "$load1 $load5 $load15"
  else
    printf '%s\t%s\t%s\t%s\n' "warn" "load_average" "Load average" "UNAVAILABLE"
  fi

  if shiva_check_enabled CHECK_TEMPERATURE; then
    temp="UNKNOWN"
    temp_level=warn
    if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
      raw_temp="$(< /sys/class/thermal/thermal_zone0/temp)"
      if (( raw_temp > 0 )); then
        temp="$((raw_temp / 1000))°C"
        if (( raw_temp >= 80000 )); then
          temp_level=fail
        elif (( raw_temp >= 70000 )); then
          temp_level=warn
        else
          temp_level=ok
        fi
      fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$temp_level" "cpu" "CPU" "$temp"
  fi

  if shiva_have free; then
    read -r ram_total ram_used < <(free -m | awk '/^Mem:/ {print $2, $3}')
    ram_percent=$((ram_used * 100 / ram_total))
    if (( ram_percent >= 90 )); then
      ram_level=fail
    elif (( ram_percent >= 80 )); then
      ram_level=warn
    else
      ram_level=ok
    fi
    printf '%s\t%s\t%s\t%s\n' "$ram_level" "ram" "RAM" "${ram_used} MB / ${ram_total} MB"
  else
    printf '%s\t%s\t%s\t%s\n' "warn" "ram" "RAM" "UNAVAILABLE"
  fi

  if shiva_check_enabled CHECK_SMART; then
    smart_disk="$SMART_DISK"
    [[ -n "$smart_disk" ]] || smart_disk="$(shiva_root_disk || true)"
    if [[ -n "$smart_disk" ]]; then
      disk_model="$(shiva_disk_model "$smart_disk")"
      disk_label="$smart_disk"
      [[ -n "$disk_model" ]] && disk_label+=" $disk_model"
      shiva_smart_health "$smart_disk"
      case "$SHIVA_SMART_STATE" in
        passed) printf '%s\t%s\t%s\t%s\n' "ok" "smart" "SSD" "PASSED ($disk_label)" ;;
        failed) printf '%s\t%s\t%s\t%s\n' "fail" "smart" "SSD" "SMART FAILED ($disk_label)" ;;
        not_installed) printf '%s\t%s\t%s\t%s\n' "warn" "smart" "SSD" "SMART NOT INSTALLED" ;;
        requires_sudo) printf '%s\t%s\t%s\t%s\n' "warn" "smart" "SSD" "SMART REQUIRES SUDO" ;;
        *) printf '%s\t%s\t%s\t%s\n' "warn" "smart" "SSD" "SMART UNKNOWN ($disk_label)" ;;
      esac
    else
      printf '%s\t%s\t%s\t%s\n' "warn" "smart" "SSD" "SMART UNKNOWN (DISK NOT FOUND)"
    fi
  fi

  read -r root_percent < <(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')
  if (( root_percent >= 95 )); then
    fs_level=fail
  elif (( root_percent >= 85 )); then
    fs_level=warn
  else
    fs_level=ok
  fi
  printf '%s\t%s\t%s\t%s\n' "$fs_level" "root_fs" "Root FS" "${root_percent}%"
  read -r root_avail root_free_percent < <(df -P -h / | awk 'NR==2 {gsub("%","",$5); print $4, 100 - $5}')
  printf '%s\t%s\t%s\t%s\n' "$fs_level" "root_free" "Root free" "${root_avail} free (${root_free_percent}%)"

  if shiva_check_enabled CHECK_INTERFACES; then
    if [[ -n "$REQUIRED_INTERFACES" ]]; then
      for interface in $REQUIRED_INTERFACES; do
        if shiva_required_interface_healthy "$interface"; then
          printf '%s\t%s\t%s\t%s\n' "ok" "interface_$interface" "Interface $interface" "UP"
        else
          printf '%s\t%s\t%s\t%s\n' "fail" "interface_$interface" "Interface $interface" "DOWN OR MISSING"
        fi
      done
    elif shiva_have ip; then
      active_interfaces="$(shiva_active_interfaces)"
      if [[ -n "$active_interfaces" ]]; then
        printf '%s\t%s\t%s\t%s\n' "ok" "interfaces" "Interfaces" "$active_interfaces"
      else
        printf '%s\t%s\t%s\t%s\n' "fail" "interfaces" "Interfaces" "NO ACTIVE INTERFACES"
      fi
    else
      printf '%s\t%s\t%s\t%s\n' "warn" "interfaces" "Interfaces" "IP COMMAND UNAVAILABLE"
    fi
  fi

  if shiva_check_enabled CHECK_OPENVPN; then
    state="$(shiva_openvpn_state)"
    printf '%s\t%s\t%s\t%s\n' "$(shiva_service_level "$state")" "openvpn_client" "OPENVPN CLIENT" "$state"
  fi

  if shiva_check_enabled CHECK_OCSERV; then
    state="$(shiva_service_state ocserv)"
    printf '%s\t%s\t%s\t%s\n' "$(shiva_service_level "$state")" "ocserv" "OCSERV" "$state"
  fi

  if shiva_check_enabled CHECK_AMNEZIA; then
    state="$(shiva_amnezia_state)"
    printf '%s\t%s\t%s\t%s\n' "$(shiva_service_level "$state")" "amnezia" "AMNEZIA" "$state"
  fi

  if shiva_check_enabled CHECK_DOCKER; then
    state="$(shiva_service_state docker)"
    printf '%s\t%s\t%s\t%s\n' "$(shiva_service_level "$state")" "docker" "DOCKER" "$state"
  fi

  if shiva_gateway_ok; then
    printf '%s\t%s\t%s\t%s\n' "ok" "gateway" "Gateway" "OK"
  else
    printf '%s\t%s\t%s\t%s\n' "fail" "gateway" "Gateway" "FAILED"
  fi

  if shiva_connectivity_ok; then
    printf '%s\t%s\t%s\t%s\n' "ok" "internet" "Internet" "OK"
  else
    printf '%s\t%s\t%s\t%s\n' "fail" "internet" "Internet" "FAILED"
  fi

  if shiva_dns_ok; then
    printf '%s\t%s\t%s\t%s\n' "ok" "dns" "DNS" "OK"
  else
    printf '%s\t%s\t%s\t%s\n' "fail" "dns" "DNS" "FAILED"
  fi

  if shiva_have systemctl; then
    failed_units="$(systemctl --failed --no-legend 2>/dev/null | grep -c . || true)"
    if (( failed_units == 0 )); then
      printf '%s\t%s\t%s\t%s\n' "ok" "failed_units" "Failed Units" "NONE"
    else
      printf '%s\t%s\t%s\t%s\n' "fail" "failed_units" "Failed Units" "$failed_units"
    fi
  else
    printf '%s\t%s\t%s\t%s\n' "warn" "failed_units" "Failed Units" "UNAVAILABLE"
  fi
}

shiva_health_engine_json_escape() {
  shiva_json_escape "$1"
}

shiva_health_summary_from_file() {
  local health_file="$1" passed warnings failures total
  passed="$(awk -F '\t' '$1 == "ok" {count += 1} END {print count + 0}' "$health_file")"
  warnings="$(awk -F '\t' '$1 == "warn" {count += 1} END {print count + 0}' "$health_file")"
  failures="$(awk -F '\t' '$1 == "fail" {count += 1} END {print count + 0}' "$health_file")"
  total=$((passed + warnings + failures))
  if (( total > 0 )); then
    SHIVA_HEALTH_PERCENT=$(((passed * 100 + warnings * 50) / total))
  else
    SHIVA_HEALTH_PERCENT=0
  fi
  if (( failures > 0 )); then
    SHIVA_HEALTH_OVERALL="attention_required"
  elif (( warnings > 0 )); then
    SHIVA_HEALTH_OVERALL="good_with_warnings"
  else
    SHIVA_HEALTH_OVERALL="excellent"
  fi
  SHIVA_HEALTH_PASSED="$passed"
  SHIVA_HEALTH_WARNINGS="$warnings"
  SHIVA_HEALTH_FAILURES="$failures"
}

shiva_health_checks_json_from_file() {
  local health_file="$1"
  awk -F '\t' '
    function esc(value) {
      gsub(/\\/,"\\\\",value)
      gsub(/"/,"\\\"",value)
      gsub(/\t/,"\\t",value)
      return value
    }
    {
      if (count > 0) printf ","
      printf "{\"level\":\"%s\",\"key\":\"%s\",\"label\":\"%s\",\"value\":\"%s\"}", esc($1), esc($2), esc($3), esc($4)
      count += 1
    }
  ' "$health_file"
}

shiva_health_snapshot_json_from_file() {
  local health_file="$1" source="${2:-health-engine}" timestamp uptime load_average root_free
  timestamp="$(date -Iseconds)"
  shiva_health_summary_from_file "$health_file"
  uptime="$(awk -F '\t' '$2 == "uptime" {print $4; exit}' "$health_file")"
  load_average="$(awk -F '\t' '$2 == "load_average" {print $4; exit}' "$health_file")"
  root_free="$(awk -F '\t' '$2 == "root_free" {print $4; exit}' "$health_file")"
  printf '{'
  shiva_json_metadata "$source" "$SHIVA_HEALTH_OVERALL" "$SHIVA_HEALTH_PERCENT"
  printf '"timestamp":"%s",' "$(shiva_json_escape "$timestamp")"
  printf '"passed":%s,' "$SHIVA_HEALTH_PASSED"
  printf '"warnings":%s,' "$SHIVA_HEALTH_WARNINGS"
  printf '"failures":%s,' "$SHIVA_HEALTH_FAILURES"
  printf '"metrics":{'
  printf '"uptime":"%s",' "$(shiva_json_escape "$uptime")"
  printf '"load_average":"%s",' "$(shiva_json_escape "$load_average")"
  printf '"root_free":"%s"' "$(shiva_json_escape "$root_free")"
  printf '},'
  printf '"events":[],"services":[],"checks":['
  shiva_health_checks_json_from_file "$health_file"
  printf ']}\n'
}

shiva_event_emit() {
  local level="$1" category="$2" message="$3" dir timestamp
  timestamp="$(date -Iseconds)"
  dir="$(dirname -- "$SHIVA_EVENT_FILE")"
  mkdir -p "$dir" 2>/dev/null || return 0
  { printf '%s\t%s\t%s\t%s\n' "$timestamp" "$level" "$category" "$message" >>"$SHIVA_EVENT_FILE"; } 2>/dev/null || return 0
  dir="$(dirname -- "$SHIVA_NOTIFY_QUEUE_FILE")"
  mkdir -p "$dir" 2>/dev/null || return 0
  { printf '%s\t%s\t%s\t%s\n' "$timestamp" "$level" "$category" "$message" >>"$SHIVA_NOTIFY_QUEUE_FILE"; } 2>/dev/null || return 0
}

shiva_health_snapshot_write() {
  local health_file="$1" snapshot_file="${2:-$SHIVA_HEALTH_SNAPSHOT_FILE}" source="${3:-health-engine}"
  local dir tmp_file previous_overall previous_percent
  shiva_health_summary_from_file "$health_file"
  if [[ -r "$snapshot_file" ]]; then
    previous_overall="$(sed -n 's/.*"overall":"\([^"]*\)".*/\1/p' "$snapshot_file")"
    previous_percent="$(sed -n 's/.*"health_percent":\([0-9][0-9]*\).*/\1/p' "$snapshot_file")"
  fi
  dir="$(dirname -- "$snapshot_file")"
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp_file="$dir/.health.$$"
  { shiva_health_snapshot_json_from_file "$health_file" "$source" >"$tmp_file"; } 2>/dev/null &&
    { mv "$tmp_file" "$snapshot_file"; } 2>/dev/null || {
      rm -f "$tmp_file" 2>/dev/null || true
      return 0
    }
  mkdir -p "$(dirname -- "$SHIVA_HEALTH_TIMELINE_FILE")" 2>/dev/null || true
  { printf '%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$SHIVA_HEALTH_PERCENT" "$SHIVA_HEALTH_OVERALL" "$SHIVA_HEALTH_FAILURES" >>"$SHIVA_HEALTH_TIMELINE_FILE"; } 2>/dev/null || true
  if [[ -n "${previous_overall:-}" && "$previous_overall" != "$SHIVA_HEALTH_OVERALL" ]]; then
    shiva_event_emit "info" "health" "overall changed from $previous_overall to $SHIVA_HEALTH_OVERALL"
  elif [[ -n "${previous_percent:-}" && "$previous_percent" != "$SHIVA_HEALTH_PERCENT" ]]; then
    shiva_event_emit "info" "health" "health changed from $previous_percent% to $SHIVA_HEALTH_PERCENT%"
  fi
}

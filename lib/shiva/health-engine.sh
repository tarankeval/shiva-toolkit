#!/usr/bin/env bash

# Shared health collection engine. Output format is:
# level<TAB>key<TAB>label<TAB>value

shiva_health_engine_collect() {
  local temp raw_temp temp_level ram_total ram_used ram_percent ram_level
  local smart_disk disk_model disk_label root_percent fs_level interface
  local active_interfaces state failed_units

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
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

#!/usr/bin/env bash
# Collects CPU / memory / disk / fan stats for the demi.sysmon bar widget.
# Prints one "key=value" per line; missing values are printed empty.
# GPU stats are streamed separately by nvidia-smi (see Sysmon.qml).

set -uo pipefail

emit() { printf '%s=%s\n' "$1" "$2"; }
# rd FILE: read the first line into $REPLY without forking (empty on failure)
rd() { REPLY=""; [ -r "$1" ] && read -r REPLY < "$1" 2>/dev/null || REPLY=""; }
instance="${1:-default}"

# ---------- CPU model ----------
cpu_model=$(awk -F: '/^model name/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' /proc/cpuinfo 2>/dev/null)

# ---------- CPU temperature (k10temp / coretemp / zenpower) ----------
cpu_temp=""
for hw in /sys/class/hwmon/hwmon*; do
  [ -r "$hw/name" ] || continue
  rd "$hw/name"
  case "$REPLY" in
    k10temp|coretemp|zenpower) ;;
    *) continue ;;
  esac
  for f in "$hw"/temp*_input; do
    [ -r "$f" ] || continue
    rd "$f"; raw=$REPLY
    [ -n "$raw" ] || continue
    c=$((raw / 1000))
    if [ -z "$cpu_temp" ] || [ "$c" -gt "$cpu_temp" ]; then cpu_temp=$c; fi
  done
done

# ---------- NVMe temperature ----------
nvme_temp=""
for hw in /sys/class/hwmon/hwmon*; do
  [ -r "$hw/name" ] || continue
  rd "$hw/name"; [ "$REPLY" = "nvme" ] || continue
  [ -r "$hw/temp1_input" ] || continue
  rd "$hw/temp1_input"; raw=$REPLY
  [ -n "$raw" ] || continue
  c=$((raw / 1000))
  if [ -z "$nvme_temp" ] || [ "$c" -gt "$nvme_temp" ]; then nvme_temp=$c; fi
done

# ---------- Fan speeds (needs a super-I/O driver such as nct6683/nct6775/nct6687d) ----------
# Uses fanN_label when the driver provides one. Otherwise, for super-I/O chips
# (MSI boards often leave labels empty) fall back to the usual header order:
# fan1 CPU, fan2 pump, fan3+ case. Fans on any other chip (e.g. amdgpu) are
# named "<chip> fan N" so they never collide with the motherboard ones.
# Every fan is exported in `fans` as "name=rpm;" pairs, INCLUDING stopped or
# unplugged ones (rpm 0); the UI hides the zeros but can tell "no sensors"
# from "all fans stopped".
# fan_cpu and fan_sys remain for backwards compatibility.
fan_cpu=""
fan_sys=""
fans=""
for f in $(ls -v /sys/class/hwmon/hwmon*/fan[0-9]*_input 2>/dev/null); do
  [ -r "$f" ] || continue
  rd "$f"; rpm=$REPLY
  case "$rpm" in ''|*[!0-9]*) continue ;; esac
  idx=${f##*/fan}; idx=${idx%_input}
  hw=${f%/*}
  rd "$hw/name"; chip=$REPLY
  rd "${f%_input}_label"; label=$REPLY
  superio=0
  case "$chip" in nct*|it8*|f71*|w83*|sch*) superio=1 ;; esac
  if [ -z "$label" ]; then
    if [ "$superio" = 1 ]; then
      case "$idx" in
        1) label="CPU fan" ;;
        2) label="Pump" ;;
        *) label="Case fan $((idx - 2))" ;;
      esac
    else
      label="${chip:-hwmon} fan $idx"
    fi
  fi
  label=${label//[;=]/ }
  fans="${fans}${label}=${rpm};"
  if [ "$superio" = 1 ]; then
    if [ "$idx" = 1 ]; then
      fan_cpu=$rpm
    elif [ "$idx" -gt 2 ] && [ "$rpm" -gt 0 ]; then
      if [ -z "$fan_sys" ] || [ "$rpm" -gt "$fan_sys" ]; then fan_sys=$rpm; fi
    fi
  fi
done

# ---------- CPU frequency (average across cores, MHz) ----------
freq_sum=0
freq_n=0
for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
  [ -r "$f" ] || continue
  rd "$f"; v=$REPLY
  [ -n "$v" ] || continue
  freq_sum=$((freq_sum + v))
  freq_n=$((freq_n + 1))
done
cpu_freq=""
[ "$freq_n" -gt 0 ] && cpu_freq=$((freq_sum / freq_n / 1000))

cpu_max_freq=""
for f in /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq; do
  [ -r "$f" ] || continue
  rd "$f"; v=$REPLY
  [ -n "$v" ] && cpu_max_freq=$((v / 1000))
done

# ---------- CPU usage since the previous call (state kept in XDG_RUNTIME_DIR) ----------
state_dir="${XDG_RUNTIME_DIR:-/tmp}"
state_file="$state_dir/demi-sysmon-${instance//[^A-Za-z0-9_-]/_}.stat"
cpu_usage=""
# First run after login: take a baseline and wait briefly so the very first
# reading is a real percentage instead of an empty "--" for one cycle.
if [ ! -r "$state_file" ]; then
  read -r _ u0 n0 s0 idle0 iow0 irq0 sirq0 st0 _ < /proc/stat
  printf '%s %s\n' \
    $((u0 + n0 + s0 + idle0 + iow0 + irq0 + sirq0 + st0)) \
    $((u0 + n0 + s0 + irq0 + sirq0 + st0)) > "$state_file" 2>/dev/null
  sleep 0.3
fi
if read -r _ u n s idle iow irq sirq st _ < /proc/stat; then
  total=$((u + n + s + idle + iow + irq + sirq + st))
  busy=$((u + n + s + irq + sirq + st))
  if read -r prev_total prev_busy < "$state_file" 2>/dev/null; then
    d_total=$((total - prev_total))
    d_busy=$((busy - prev_busy))
    if [ "$d_total" -gt 0 ] && [ "$d_busy" -ge 0 ]; then
      cpu_usage=$((100 * d_busy / d_total))
    fi
  fi
  printf '%s %s\n' "$total" "$busy" > "$state_file" 2>/dev/null
fi

# ---------- Memory (MiB) ----------
mem_total=0
mem_avail=0
swap_total=0
swap_free=0
while read -r key value _; do
  case "$key" in
    MemTotal:)      mem_total=$value ;;
    MemAvailable:)  mem_avail=$value ;;
    SwapTotal:)     swap_total=$value ;;
    SwapFree:)      swap_free=$value ;;
  esac
done < /proc/meminfo
mem_used=""
[ "$mem_total" -gt 0 ] && mem_used=$(( (mem_total - mem_avail) / 1024 ))
mem_total=$((mem_total / 1024))
swap_used=""
swap_total=$((swap_total / 1024))
swap_free=$((swap_free / 1024))
[ "$swap_total" -gt 0 ] && swap_used=$((swap_total - swap_free))

# ---------- Load / uptime ----------
load=$(awk '{ printf "%s %s %s", $1, $2, $3 }' /proc/loadavg 2>/dev/null)
uptime=$(awk '{ printf "%d", $1 }' /proc/uptime 2>/dev/null)

emit cpu_model "$cpu_model"
emit cpu_temp "$cpu_temp"
emit cpu_usage "$cpu_usage"
emit cpu_freq "$cpu_freq"
emit cpu_max_freq "$cpu_max_freq"
emit cpu_cores "$(nproc 2>/dev/null)"
emit mem_used "$mem_used"
emit mem_total "$mem_total"
emit swap_used "$swap_used"
emit swap_total "$swap_total"
emit nvme_temp "$nvme_temp"
emit fans "$fans"
emit fan_cpu "$fan_cpu"
emit fan_sys "$fan_sys"
emit load "$load"
emit uptime "$uptime"

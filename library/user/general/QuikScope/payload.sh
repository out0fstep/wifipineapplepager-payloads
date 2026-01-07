# Title: QuickScope
# Description: Pick a live-seen AP from Recon, then add its SSID + clients to allow/deny filter lists (dedupe enabled).
# Author: out0fstep / ChatGPT assist
# Version: 1.3.3
# Category: user/general

set -euo pipefail
set -E

########################################
# Options
########################################
RECON_DB=""
DEDUPE="true"

SHOW_BANNER="true"
BANNER_COLOR="teal"
STATUS_COLOR="red"

SPIN_SCAN="Collecting"
SPIN_PARSING="Parsing"
SPIN_APPLYING="Applying"
SPIN_EXAMINE="Examining"

TOP_N_APS=10
LIVE_WINDOW_SEC=60

# IMPORTANT: let Recon correlate stations after focusing the AP
EXAMINE_SECONDS=20   # 15-30 tends to work better than 8-12

DEBUG="true"
ERR_LOG="/root/loot/quickscope_error.log"

########################################
# Spinner + UI helpers
########################################
__spin=""

stop_spin() {
  if [[ -n "${__spin}" ]]; then
    STOP_SPINNER "${__spin}" >/dev/null 2>&1 || true
    __spin=""
  fi
}
start_spin() {
  stop_spin
  __spin="$(START_SPINNER "$1")" || __spin=""
}

die() {
  stop_spin
  ERROR_DIALOG "$1" >/dev/null 2>&1 || true
  exit 0
}

on_err() {
  local ec=$?
  stop_spin
  local loc="line ${BASH_LINENO[0]:-?}"
  local cmd="${BASH_COMMAND:-?}"
  local msg="QuickScope error ($ec) @ $loc"
  if [[ "$DEBUG" == "true" ]]; then
    {
      echo "-----"
      echo "Time: $(date -Iseconds 2>/dev/null || date)"
      echo "Exit: $ec"
      echo "Loc : $loc"
      echo "Cmd : $cmd"
    } >> "$ERR_LOG" 2>/dev/null || true
    ERROR_DIALOG "$msg" >/dev/null 2>&1 || true
  fi
  exit 0
}
trap 'on_err' ERR
trap 'stop_spin' EXIT

logc() { local c="$1"; shift; LOG "$c" "$*"; }

trim() {
  local s="$1"
  s="${s//$'\r'/}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

norm_bssid_nocolon() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ':-'
}
norm_bssid_colon() {
  # best-effort: if input is already colon form, keep; if nocolon 12 hex, add colons
  local x; x="$(norm_bssid_nocolon "$1")"
  if [[ "$x" =~ ^[0-9a-f]{12}$ ]]; then
    printf '%s:%s:%s:%s:%s:%s' "${x:0:2}" "${x:2:2}" "${x:4:2}" "${x:6:2}" "${x:8:2}" "${x:10:2}"
  else
    printf '%s' "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  fi
}

########################################
# Banner
########################################
print_banner() {
  [[ "$SHOW_BANNER" == "true" ]] || return 0
  LOG " "
  logc "$BANNER_COLOR" '   ____       _ _     __                     '
  logc "$BANNER_COLOR" '  /___ \_   _(_) | __/ _\ ___ ___  _ __   ___'
  logc "$BANNER_COLOR" ' //  / / | | | | |/ /\ \ / __/ _ \| '"'"'_ \ / _ \'
  logc "$BANNER_COLOR" '/ \_/ /| |_| | |   < _\ \ (_| (_) | |_) |  __/'
  logc "$BANNER_COLOR" '\___,_\ \__,_|_|_|\_\\__/\___\___/| .__/ \___|'
  logc "$BANNER_COLOR" '                                  |_|         '
  LOG " "
  LOG "QuickScope v1.3.3 Created by: out0fstep"
  LOG " "
}

########################################
# Filter dedupe helpers
########################################
norm_ssid() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
norm_mac()  { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ':-'; }

get_existing_ssids() { PINEAPPLE_SSID_FILTER_LIST 2>/dev/null | tr '[:upper:]' '[:lower:]' || true; }
get_existing_macs()  { PINEAPPLE_MAC_FILTER_LIST 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ':-' || true; }

ssid_present() {
  [[ "$DEDUPE" == "true" ]] || return 1
  local s; s="$(norm_ssid "$1")"
  get_existing_ssids | grep -Fqx -- "$s" && return 0
  get_existing_ssids | grep -Fq  -- "$s" && return 0
  return 1
}
mac_present() {
  [[ "$DEDUPE" == "true" ]] || return 1
  local m; m="$(norm_mac "$1")"
  get_existing_macs | grep -Fq -- "$m" && return 0
  return 1
}

########################################
# Recon DB + sqlite
########################################
command -v sqlite3 >/dev/null 2>&1 || die "Missing dependency: sqlite3"

autodetect_recon_db() {
  if [[ -n "${RECON_DB}" && -f "${RECON_DB}" ]]; then
    echo "${RECON_DB}"; return 0
  fi
  local candidates=(
    "/root/recon/recon.db"
    "/root/recon.db"
    "/tmp/recon/recon.db"
    "/tmp/recon.db"
  )
  local p
  for p in "${candidates[@]}"; do
    [[ -f "$p" ]] && { echo "$p"; return 0; }
  done
  p="$(find /root /tmp -maxdepth 4 -type f -name 'recon.db' 2>/dev/null | head -n 1 || true)"
  [[ -n "$p" && -f "$p" ]] && { echo "$p"; return 0; }
  return 1
}

sql() { sqlite3 -batch -noheader "$RECON_DB" "$1" 2>/dev/null || true; }

########################################
# Schema discovery
########################################
pick_col() {
  local table="$1"; shift
  local want cols
  cols="$(sql "PRAGMA table_info($table);" | awk -F'|' '{print tolower($2)}')"
  for want in "$@"; do
    if echo "$cols" | grep -qx "$want"; then
      echo "$want"; return 0
    fi
  done
  return 1
}

table_cols() { sql "PRAGMA table_info($1);" | awk -F'|' '{print tolower($2)}' | tr '\n' ' '; }

find_ap_table() {
  local t cols
  for t in $(sql "SELECT name FROM sqlite_master WHERE type='table';"); do
    cols="$(table_cols "$t")"
    if echo "$cols" | grep -Eq '(^| )ssid($| )|(^| )essid($| )|(^| )network_name($| )|(^| )name($| )' \
       && echo "$cols" | grep -Eq '(^| )bssid($| )|(^| )ap_bssid($| )|(^| )mac($| )'; then
      echo "$t"; return 0
    fi
  done
  return 1
}

# Find a station/client table more reliably: look for station/client mac + bssid-ish
find_station_table() {
  local t cols
  for t in $(sql "SELECT name FROM sqlite_master WHERE type='table';"); do
    cols="$(table_cols "$t")"
    if echo "$cols" | grep -Eq '(client_mac|station_mac|sta_mac|station|client|mac)' \
       && echo "$cols" | grep -Eq '(bssid|ap_bssid|router_bssid|target_bssid|assoc_bssid)'; then
      echo "$t"; return 0
    fi
  done
  return 1
}

########################################
# Live filtering helpers
########################################
find_time_col() { local table="$1"; pick_col "$table" last_seen lastseen seen timestamp ts time || true; }

get_max_ts_and_unit() {
  local table="$1"; local tcol="$2"
  [[ -n "$tcol" ]] || { echo "0|"; return 0; }
  local maxv
  maxv="$(sql "SELECT MAX($tcol) FROM $table;" | head -n1 || true)"
  [[ "$maxv" =~ ^[0-9]+$ ]] || { echo "0|"; return 0; }
  if [[ "$maxv" -gt 1000000000000 ]]; then echo "${maxv}|ms"
  elif [[ "$maxv" -gt 1000000000 ]]; then echo "${maxv}|s"
  else echo "${maxv}|"
  fi
}

recent_where_clause() {
  local table="$1"
  local tcol; tcol="$(find_time_col "$table")"
  local meta; meta="$(get_max_ts_and_unit "$table" "$tcol")"
  local maxv unit
  maxv="${meta%%|*}"; unit="${meta##*|}"

  if [[ -n "$tcol" && -n "$unit" && "$maxv" -gt 0 ]]; then
    if [[ "$unit" == "s" ]]; then
      local minv=$((maxv - LIVE_WINDOW_SEC)); [[ "$minv" -lt 0 ]] && minv=0
      echo "AND $tcol >= $minv"; return 0
    fi
    if [[ "$unit" == "ms" ]]; then
      local win_ms=$((LIVE_WINDOW_SEC * 1000))
      local minv=$((maxv - win_ms)); [[ "$minv" -lt 0 ]] && minv=0
      echo "AND $tcol >= $minv"; return 0
    fi
  fi
  echo ""
}

########################################
# Robust client collection
########################################
collect_clients_for_bssid() {
  local table="$1"
  local mac_col="$2"
  local bssid_col="$3"
  local sel_bssid="$4"
  local where_recent="$5"

  local b1 b2
  b1="$(norm_bssid_colon "$sel_bssid")"
  b2="$(norm_bssid_nocolon "$sel_bssid")"

  # Try several comparisons:
  # 1) exact match with colon form
  # 2) exact match with nocolon form
  # 3) normalized compare (remove colons on DB side too)
  sql "
    SELECT DISTINCT $mac_col
    FROM $table
    WHERE (
      $bssid_col = '$b1'
      OR $bssid_col = '$b2'
      OR lower(replace(replace($bssid_col,':',''),'-','')) = '$b2'
    )
    AND $mac_col IS NOT NULL
    AND LENGTH($mac_col) > 0
    $where_recent
    ORDER BY $mac_col;
  "
}

########################################
# Main flow
########################################
print_banner

# One unified "collecting" spinner
logc "$STATUS_COLOR" "Collecting networks..."
start_spin "$SPIN_SCAN"

RECON_DB="$(autodetect_recon_db || true)"
[[ -n "$RECON_DB" && -f "$RECON_DB" ]] || die "Recon DB not found. Open Recon, let it discover networks, then try again."

# Fresh recon session helps avoid stale pool
stop_spin
if CONFIRMATION_DIALOG "Start a fresh Recon session? (Recommended)"; then
  start_spin "$SPIN_SCAN"
  PINEAPPLE_RECON_NEW "quickscope" >/dev/null 2>&1 || true
  sleep 10
  stop_spin
fi

# Discover AP schema
start_spin "$SPIN_PARSING"
AP_TABLE="$(find_ap_table || true)"
[[ -n "$AP_TABLE" ]] || die "Could not find AP table in recon.db. Run Recon and try again."

SSID_COL="$(pick_col "$AP_TABLE" ssid essid network_name name || true)"
BSSID_COL="$(pick_col "$AP_TABLE" bssid ap_bssid mac || true)"
SIG_COL="$(pick_col "$AP_TABLE" rssi signal power dbm strength || true)"
[[ -n "$SSID_COL" && -n "$BSSID_COL" ]] || die "Could not identify SSID/BSSID columns in $AP_TABLE."

# Discover station schema (more robust)
STATION_TABLE="$(find_station_table || true)"
STATION_MAC_COL=""
STATION_BSSID_COL=""
if [[ -n "$STATION_TABLE" ]]; then
  STATION_MAC_COL="$(pick_col "$STATION_TABLE" client_mac station_mac sta_mac mac || true)"
  STATION_BSSID_COL="$(pick_col "$STATION_TABLE" bssid ap_bssid router_bssid target_bssid assoc_bssid || true)"
fi

# Build AP list (top N by RSSI)
AP_RECENT_WHERE="$(recent_where_clause "$AP_TABLE")"
AP_LINES=()

if [[ -n "$SIG_COL" ]]; then
  while IFS='|' read -r bssid ssid sig; do
    bssid="$(trim "${bssid:-}")"
    ssid="$(trim "${ssid:-}")"
    sig="$(trim "${sig:-}")"
    [[ -n "$bssid" ]] || continue
    [[ -n "$ssid" ]] || ssid="<hidden>"
    [[ -n "$sig"  ]] || sig="?"
    AP_LINES+=("${ssid}"$'\t'"${bssid}"$'\t'"${sig}")
  done < <(sql "
    SELECT $BSSID_COL, $SSID_COL, $SIG_COL
    FROM $AP_TABLE
    WHERE $BSSID_COL IS NOT NULL
      $AP_RECENT_WHERE
    GROUP BY $BSSID_COL, $SSID_COL, $SIG_COL
    ORDER BY $SIG_COL DESC
    LIMIT $TOP_N_APS;
  ")
else
  while IFS='|' read -r bssid ssid; do
    bssid="$(trim "${bssid:-}")"
    ssid="$(trim "${ssid:-}")"
    [[ -n "$bssid" ]] || continue
    [[ -n "$ssid" ]] || ssid="<hidden>"
    AP_LINES+=("${ssid}"$'\t'"${bssid}"$'\t'"?")
  done < <(sql "
    SELECT DISTINCT $BSSID_COL, $SSID_COL
    FROM $AP_TABLE
    WHERE $BSSID_COL IS NOT NULL
      $AP_RECENT_WHERE
    LIMIT $TOP_N_APS;
  ")
fi
stop_spin

AP_COUNT="${#AP_LINES[@]}"
[[ "$AP_COUNT" -gt 0 ]] || die "No LIVE networks seen yet. Open Recon, wait for nearby APs, then run again."

# Display APs only
LOG "Top Live Networks:"
AP_SSIDS=(); AP_BSSIDS=(); AP_SIGS=()
for i in $(seq 1 "$AP_COUNT"); do
  idx=$((i-1))
  IFS=$'\t' read -r ssid bssid sig <<<"${AP_LINES[$idx]}"
  AP_SSIDS+=("$ssid"); AP_BSSIDS+=("$bssid"); AP_SIGS+=("$sig")
  LOG " $i) $ssid ($bssid) rssi:$sig"
done

LOG " "
LOG "Press any button to continue..."
WAIT_FOR_BUTTON_PRESS ANY

# Pick AP
PICK="$(NUMBER_PICKER "Pick target network (1-$AP_COUNT)" "1")" || exit 0
[[ "$PICK" =~ ^[0-9]+$ ]] || die "Invalid selection."
[[ "$PICK" -ge 1 && "$PICK" -le "$AP_COUNT" ]] || die "Out of range."

SEL_IDX=$((PICK-1))
SEL_SSID="$(trim "${AP_SSIDS[$SEL_IDX]}")"
SEL_BSSID="$(trim "${AP_BSSIDS[$SEL_IDX]}")"

# Pick allow/deny
CHOICE="$(NUMBER_PICKER "1=DENY  2=ALLOW" "1")" || exit 0
case "$CHOICE" in
  1) LIST="deny" ;;
  2) LIST="allow" ;;
  *) die "Invalid choice. Pick 1 or 2." ;;
esac

# Confirm
CONFIRMATION_DIALOG "Apply $LIST lists for this AP + its clients?" || { ALERT "Cancelled"; exit 0; }

# Focus AP so Recon can populate station associations (like the Recon UI)
if [[ "$EXAMINE_SECONDS" -gt 0 ]]; then
  start_spin "$SPIN_EXAMINE"
  PINEAPPLE_EXAMINE_BSSID "$SEL_BSSID" >/dev/null 2>&1 || true
  sleep "$EXAMINE_SECONDS"
  PINEAPPLE_EXAMINE_RESET >/dev/null 2>&1 || true
  stop_spin
fi

# Apply SSID filter (skip hidden)
SSID_ADDED=0
SSID_SKIPPED=0
if [[ -z "$SEL_SSID" || "$SEL_SSID" == "<hidden>" ]]; then
  SSID_SKIPPED=1
elif ssid_present "$SEL_SSID"; then
  SSID_SKIPPED=1
else
  start_spin "$SPIN_APPLYING"
  PINEAPPLE_SSID_FILTER_ADD "$LIST" "$SEL_SSID" >/dev/null 2>&1 || die "Failed to add SSID to $LIST list."
  stop_spin
  SSID_ADDED=1
fi

# Collect + apply client MACs (silent)
CLIENTS_ADDED=0
CLIENTS_SKIPPED=0

if [[ -n "$STATION_TABLE" && -n "$STATION_MAC_COL" && -n "$STATION_BSSID_COL" ]]; then
  local_where="$(recent_where_clause "$STATION_TABLE")"

  start_spin "$SPIN_PARSING"
  mapfile -t CLIENT_MACS < <(collect_clients_for_bssid "$STATION_TABLE" "$STATION_MAC_COL" "$STATION_BSSID_COL" "$SEL_BSSID" "$local_where")
  stop_spin

  if [[ "${#CLIENT_MACS[@]}" -gt 0 ]]; then
    start_spin "$SPIN_APPLYING"
    for mac in "${CLIENT_MACS[@]}"; do
      mac="$(trim "$mac")"
      [[ -n "$mac" ]] || continue
      if mac_present "$mac"; then
        CLIENTS_SKIPPED=$((CLIENTS_SKIPPED+1))
        continue
      fi
      PINEAPPLE_MAC_FILTER_ADD "$LIST" "$mac" >/dev/null 2>&1 || die "Failed adding MAC to $LIST list: $mac"
      CLIENTS_ADDED=$((CLIENTS_ADDED+1))
    done
    stop_spin
  fi
else
  LOG "Stations table not detected — added SSID only."
fi

LOG " "
LOG "SSID: added $SSID_ADDED, skipped $SSID_SKIPPED"
LOG "Clients: added $CLIENTS_ADDED, skipped $CLIENTS_SKIPPED"
ALERT "QuickScope complete ($LIST)"
exit 0

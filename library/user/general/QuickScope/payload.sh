#!/bin/bash
# Title: QuickScope
# Description: Quickly add a target SSID and associated client MACs to allow/deny filter lists (dedupe enabled).
# Author: out0fstep / ChatGPT assist
# Version: 2.2
# Category: user/general
#

set -euo pipefail

########################################
# Options (user configurable)
########################################
RECON_DB="/root/recon/recon.db"
DEDUPE="true"

# Banner
SHOW_BANNER="true"
BANNER_COLOR="teal"    

# Single-word spinner labels (<=1.0.4 safe)
SPIN_LOADING="Loading"
SPIN_PARSING="Parsing"
SPIN_APPLYING="Applying"

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
  exit 1
}
trap 'stop_spin' EXIT

need() { command -v "$1" >/dev/null 2>&1; }

logc() {
  # logc <color> <message>
  # If a color isn't supported by the current theme, LOG should still print the message (often default color).
  local c="$1"; shift
  LOG "$c" "$*"
}

########################################
# Banner
########################################
print_banner() {
  [[ "$SHOW_BANNER" == "true" ]] || return 0

  LOG " "
  logc "$BANNER_COLOR" "    ██████                ███           █████       █████████                                      "
  logc "$BANNER_COLOR" "  ███░░░░███             ░░░           ░░███       ███░░░░░███                                     "
  logc "$BANNER_COLOR" " ███    ░░███ █████ ████ ████   ██████  ░███ █████░███    ░░░   ██████   ██████  ████████   ██████ "
  logc "$BANNER_COLOR" "░███     ░███░░███ ░███ ░░███  ███░░███ ░███░░███ ░░█████████  ███░░███ ███░░███░░███░░███ ███░░███"
  logc "$BANNER_COLOR" "░███   ██░███ ░███ ░███  ░███ ░███ ░░░  ░██████░   ░░░░░░░░███░███ ░░░ ░███ ░███ ░███ ░███░███████ "
  logc "$BANNER_COLOR" "░░███ ░░████  ░███ ░███  ░███ ░███  ███ ░███░░███  ███    ░███░███  ███░███ ░███ ░███ ░███░███░░░  "
  logc "$BANNER_COLOR" " ░░░██████░██ ░░████████ █████░░██████  ████ █████░░█████████ ░░██████ ░░██████  ░███████ ░░██████ "
  logc "$BANNER_COLOR" "   ░░░░░░ ░░   ░░░░░░░░ ░░░░░  ░░░░░░  ░░░░ ░░░░░  ░░░░░░░░░   ░░░░░░   ░░░░░░   ░███░░░   ░░░░░░  "
  logc "$BANNER_COLOR" "                                                                                 ░███              "
  logc "$BANNER_COLOR" "                                                                                 █████             "
  logc "$BANNER_COLOR" "                                                                                ░░░░░              "
  LOG " "
  LOG "QuickScope v1.0"
  LOG " "
}

########################################
# Filter dedupe helpers
########################################
norm_ssid() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
norm_mac()  { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ':-'; }

get_existing_ssids() {
  PINEAPPLE_SSID_FILTER_LIST 2>/dev/null | tr '[:upper:]' '[:lower:]' || true
}
get_existing_macs() {
  PINEAPPLE_MAC_FILTER_LIST 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ':-' || true
}
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
# SQLite helpers + schema discovery
########################################
need sqlite3 || die "Missing dependency: sqlite3"
[[ -f "$RECON_DB" ]] || die "Recon DB not found at $RECON_DB. Run Recon first."

sql() { sqlite3 -batch -noheader "$RECON_DB" "$1" 2>/dev/null || true; }

find_ap_table() {
  local t cols
  for t in $(sql "SELECT name FROM sqlite_master WHERE type='table';"); do
    cols="$(sql "PRAGMA table_info($t);" | awk -F'|' '{print tolower($2)}')"
    if echo "$cols" | grep -Eq '(^| )ssid($| )' && echo "$cols" | grep -Eq '(^| )bssid($| )'; then
      echo "$t"; return 0
    fi
  done
  if sql "SELECT 1 FROM sqlite_master WHERE type='table' AND name='ssid';" | grep -q 1; then
    echo "ssid"; return 0
  fi
  return 1
}

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

find_client_table() {
  local t cols
  for t in $(sql "SELECT name FROM sqlite_master WHERE type='table';"); do
    cols="$(sql "PRAGMA table_info($t);" | awk -F'|' '{print tolower($2)}')"
    if echo "$cols" | grep -Eq '(client_mac|station_mac|mac)' && echo "$cols" | grep -Eq '(bssid|ap_bssid)'; then
      echo "$t"; return 0
    fi
  done
  return 1
}

########################################
# Main
########################################
print_banner

# 1) Choose allow vs deny 
if CONFIRMATION_DIALOG "Add selected AP + clients to ALLOW? (Cancel=DENY)"; then
  LIST="allow"
else
  LIST="deny"
fi
LOG "Target list: $LIST"

# 2) Discover tables/columns
start_spin "$SPIN_LOADING"

AP_TABLE="$(find_ap_table || true)"
[[ -n "$AP_TABLE" ]] || die "Could not find AP table in recon.db."

SSID_COL="$(pick_col "$AP_TABLE" ssid essid network_name name || true)"
BSSID_COL="$(pick_col "$AP_TABLE" bssid ap_bssid mac || true)"
[[ -n "$SSID_COL" && -n "$BSSID_COL" ]] || die "Could not identify SSID/BSSID columns in $AP_TABLE."

CLIENT_TABLE="$(find_client_table || true)"
CLIENT_MAC_COL=""
CLIENT_BSSID_COL=""
if [[ -n "$CLIENT_TABLE" ]]; then
  CLIENT_MAC_COL="$(pick_col "$CLIENT_TABLE" client_mac station_mac mac || true)"
  CLIENT_BSSID_COL="$(pick_col "$CLIENT_TABLE" bssid ap_bssid || true)"
fi

stop_spin

# 3) Build AP list 
start_spin "$SPIN_PARSING"

AP_LINES=()
if [[ -n "$CLIENT_TABLE" && -n "$CLIENT_MAC_COL" && -n "$CLIENT_BSSID_COL" ]]; then
  while IFS='|' read -r bssid ssid cc; do
    [[ -n "$bssid" ]] || continue
    ssid="${ssid:-<hidden>}"
    AP_LINES+=("${ssid}\t${bssid}\t${cc}")
  done < <(sql "
    SELECT a.$BSSID_COL, a.$SSID_COL, COUNT(DISTINCT c.$CLIENT_MAC_COL) AS cc
    FROM $AP_TABLE a
    LEFT JOIN $CLIENT_TABLE c ON c.$CLIENT_BSSID_COL = a.$BSSID_COL
    GROUP BY a.$BSSID_COL, a.$SSID_COL
    ORDER BY cc DESC;
  ")
else
  while IFS='|' read -r bssid ssid; do
    [[ -n "$bssid" ]] || continue
    ssid="${ssid:-<hidden>}"
    AP_LINES+=("${ssid}\t${bssid}\t0")
  done < <(sql "
    SELECT DISTINCT $BSSID_COL, $SSID_COL
    FROM $AP_TABLE
    WHERE $BSSID_COL IS NOT NULL
    ORDER BY $SSID_COL;
  " | awk -F'|' '{print $1 "|" $2}')
fi

stop_spin

AP_COUNT="${#AP_LINES[@]}"
[[ "$AP_COUNT" -gt 0 ]] || die "No APs found in recon.db. Run Recon and try again."

LOG "Select an AP:"
AP_SSIDS=(); AP_BSSIDS=(); AP_CCNT=()
for i in $(seq 1 "$AP_COUNT"); do
  idx=$((i-1))
  IFS=$'\t' read -r ssid bssid cc <<<"${AP_LINES[$idx]}"
  AP_SSIDS+=("$ssid"); AP_BSSIDS+=("$bssid"); AP_CCNT+=("$cc")
  LOG " $i) $ssid ($bssid) clients:$cc"
done

PICK="$(NUMBER_PICKER "Pick AP (1-$AP_COUNT)" "1")" || exit 0
[[ "$PICK" =~ ^[0-9]+$ ]] || die "Invalid selection."
[[ "$PICK" -ge 1 && "$PICK" -le "$AP_COUNT" ]] || die "Out of range."

SEL_IDX=$((PICK-1))
SEL_SSID="${AP_SSIDS[$SEL_IDX]}"
SEL_BSSID="${AP_BSSIDS[$SEL_IDX]}"
SEL_CC="${AP_CCNT[$SEL_IDX]}"

LOG "Selected: $SEL_SSID ($SEL_BSSID)"

# 4) Checkpoint: confirm before making any changes
CONFIRMATION_DIALOG "Update the filter lists?" || { ALERT "Cancelled"; exit 0; }

# 5) Apply SSID filter (skip hidden/blank)
SSID_ADDED=0
SSID_SKIPPED=0
if [[ -z "$SEL_SSID" || "$SEL_SSID" == "<hidden>" ]]; then
  SSID_SKIPPED=1
  LOG "SSID hidden/blank — skipping SSID add."
elif ssid_present "$SEL_SSID"; then
  SSID_SKIPPED=1
  LOG "SSID already present — skipping."
else
  start_spin "$SPIN_APPLYING"
  PINEAPPLE_SSID_FILTER_ADD "$LIST" "$SEL_SSID"
  stop_spin
  SSID_ADDED=1
  LOG "SSID added."
fi

# 6) Apply client MAC filters (if client table exists)
CLIENTS_ADDED=0
CLIENTS_SKIPPED=0

if [[ -n "$CLIENT_TABLE" && -n "$CLIENT_MAC_COL" && -n "$CLIENT_BSSID_COL" ]]; then
  start_spin "$SPIN_PARSING"
  mapfile -t CLIENT_MACS < <(sql "
    SELECT DISTINCT $CLIENT_MAC_COL
    FROM $CLIENT_TABLE
    WHERE $CLIENT_BSSID_COL = '$SEL_BSSID'
      AND $CLIENT_MAC_COL IS NOT NULL
      AND LENGTH($CLIENT_MAC_COL) > 0
    ORDER BY $CLIENT_MAC_COL;
  ")
  stop_spin

  if [[ "${#CLIENT_MACS[@]}" -eq 0 ]]; then
    LOG "No clients recorded for this AP in recon.db."
  else
    start_spin "$SPIN_APPLYING"
    for mac in "${CLIENT_MACS[@]}"; do
      [[ -n "$mac" ]] || continue
      if mac_present "$mac"; then
        CLIENTS_SKIPPED=$((CLIENTS_SKIPPED+1))
        continue
      fi
      PINEAPPLE_MAC_FILTER_ADD "$LIST" "$mac"
      CLIENTS_ADDED=$((CLIENTS_ADDED+1))
    done
    stop_spin
  fi
else
  LOG "Client table not detected — only SSID will be handled."
fi

# 7) Summary + final alert
LOG "SSID: added $SSID_ADDED, skipped $SSID_SKIPPED"
LOG "Clients: added $CLIENTS_ADDED, skipped $CLIENTS_SKIPPED"

# End-of-run user notification
ALERT "Lists updated ($LIST)"

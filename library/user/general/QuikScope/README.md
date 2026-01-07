# QuickScope

**QuickScope** is a Pineapple Pager payload that helps you quickly:
1) pick a *recently seen* Access Point (AP) from **Recon**, then  
2) add that AP’s **SSID** (network filter) and associated **client MACs** (client filter) to either the **ALLOW** or **DENY** lists — with optional dedupe to avoid duplicates.

> **For authorized testing / legitimate network administration only.**  
> Use only on networks and devices you own or have explicit permission to assess.

---

## ✨ Features

- **Live AP selection** from Recon (top N by signal/RSSI)
- **One-run workflow**: pick AP → pick allow/deny → confirm → apply
- **Dedupe support** (skip SSIDs/MACs that already exist in filter lists)
- **Robust Recon DB discovery** (tries common recon.db paths + falls back to `find`)
- **Schema discovery** (tries to locate AP and station/client tables/columns dynamically)
- **UI friendly**: banner, colored status logs, spinners, confirmation dialogs
- **Debug error logging** (optional) to help track failures

---

## ✅ Requirements

- **Hak5 Pineapple Pager** (payload runtime)
- Recon must have run long enough to populate `recon.db`
- `sqlite3` must be installed (payload checks this and errors if missing)

---

## 📦 Installation

1. Create a payload folder on the Pager:
   - `payloads/user/general/QuickScope/`

2. Save your script as:
   - `payload.sh`

3. Make it executable:
   ```bash
   chmod +x payload.sh
🚀 Usage
Start Recon on the Pineapple Pager and wait until nearby networks appear.

Run the payload:

bash
Copy code
./payload.sh
Optional: choose to start a fresh Recon session (recommended).

Select a network (1–N) from the “Top Live Networks” list.

Choose:

1 = DENY

2 = ALLOW

Confirm the action, then QuickScope applies:

SSID → SSID filter list (allow/deny)

Clients → MAC filter list (allow/deny)

At the end you’ll see a summary:

SSID: added X, skipped Y

Clients: added X, skipped Y

⚙️ Configuration Options
Edit these values near the top of payload.sh:

Recon / behavior
RECON_DB=""
Leave empty to auto-detect. Set explicitly if your recon.db lives elsewhere.

TOP_N_APS=10
How many APs to show.

LIVE_WINDOW_SEC=60
How “recent” an AP/station entry must be (best-effort, depends on schema/time column).

EXAMINE_SECONDS=20
Time to focus the AP so Recon correlates stations/clients (15–30 often works best).

Dedupe
DEDUPE="true"
If true, skips SSIDs/MACs that already exist in filter lists.

UI / cosmetics
SHOW_BANNER="true"

BANNER_COLOR="teal"

STATUS_COLOR="red"

SPIN_SCAN="Collecting"

SPIN_PARSING="Parsing"

SPIN_APPLYING="Applying"

SPIN_EXAMINE="Examining"

Debugging
DEBUG="true"

ERR_LOG="/root/loot/quickscope_error.log"

If DEBUG=true, errors will show a dialog and log details like timestamp, exit code, line number, and last command.

🔎 How it works (high level)
Find recon.db automatically (or use RECON_DB if set).

Optionally start a fresh Recon session to reduce stale entries.

Use SQLite schema inspection (PRAGMA table_info) to find:

an AP table with SSID + BSSID columns

a station/client table with client MAC + BSSID association columns (best-effort)

List top APs (by RSSI if available).

After you pick one:

Call PINEAPPLE_EXAMINE_BSSID and wait EXAMINE_SECONDS

Add SSID to allow/deny SSID filter (skips hidden or duplicate)

Collect associated client MACs and add to allow/deny MAC filter (skips duplicates)

🐞 Known Issues / Bugs
Client collection is not reliable yet
Bug: Client collection/association may not work consistently (or may return zero clients), even when the AP selection and SSID filtering works.

Why: Recon database schema and the way stations/clients are correlated varies and can be timing dependent. Even with PINEAPPLE_EXAMINE_BSSID and a wait window, the station table may:

not exist (or use unexpected column names)

store BSSIDs in a different format (colon vs no-colon, mixed case, etc.)

record associations in a different table than expected

require longer correlation time than currently used

Workarounds to try:

Increase EXAMINE_SECONDS to 25–40

Increase LIVE_WINDOW_SEC to 90–180

Let Recon run longer before running QuickScope

Run QuickScope twice after focusing the AP once in the Recon UI

If you can share PRAGMA table_info(...) outputs or a redacted recon.db schema, the client collection logic can be tightened for your firmware/version.

🧪 Troubleshooting
“Recon DB not found”

Start Recon and let it discover networks.

Confirm recon.db exists in one of the expected paths (or set RECON_DB manually).

“No LIVE networks seen yet”

Increase LIVE_WINDOW_SEC or wait longer in Recon.

Ensure nearby APs are present and Recon is actually collecting.

Errors during run

If DEBUG=true, check:

/root/loot/quickscope_error.log

🛣️ Roadmap / Ideas
Improve station/client discovery across more recon.db schemas

Add optional “show captured clients” preview before applying

Export a run report to loot (SSID, BSSID, applied MACs, counts)

Add a “retry client collection” step if zero clients found

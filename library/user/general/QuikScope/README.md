# 🎯 QuikScope

**QuikScope** is a WiFi Pineapple Pager payload that lets you **quickly select an AP from Recon results** and then **add the AP SSID + associated client MACs** to the Pager’s **ALLOW or DENY filter lists** (with optional dedupe).

It’s built for fast, on-device workflow:

1) Run Recon  
2) Run QuickScope  
3) Pick an AP  
4) Choose ALLOW or DENY  
5) Confirm changes  
6) Lists update automatically

⚠️ **Authorized testing only.**

---

## ✨ What it does

- Reads Recon database: `/root/recon/recon.db`
- Discovers the AP + client tables/columns automatically (schema-tolerant)
- Shows APs and (if available) **client counts**
- Prompts:
  - Add to **ALLOW** (OK) or **DENY** (Cancel)
  - Select AP via number picker
  - **Checkpoint confirmation** before writing changes
- Updates:
  - SSID filter list (skips hidden SSIDs)
  - MAC filter list (clients associated with selected BSSID)
- Optional dedupe:
  - Avoids re-adding SSIDs/MACs already in filter lists

---

## 📁 Files

- `payload.sh` — main payload script

Recommended folder:
- `library/user/general/QuickScope/`

---

## ✅ Requirements

- Hak5 **WiFi Pineapple Pager**
- Recon has been run at least once (so `recon.db` exists)
- `sqlite3` installed (used to query the Recon DB)

---

## ▶️ Usage

1. **Run Recon** on the Pineapple Pager to populate the Recon DB:
   - Ensure `/root/recon/recon.db` exists.

2. Launch **QuickScope** from the Pager payload menu.

3. Choose target list:
   - **OK** = add selected AP + clients to **ALLOW**
   - **Cancel** = add selected AP + clients to **DENY**

4. Select an AP from the list.

5. Confirm when prompted:
   - `Update the filter lists?`

6. Review summary output (added vs skipped).

---

## 🧠 Behavior Notes

- **Hidden SSIDs** are skipped automatically for SSID list updates.
- Client MAC updates only occur if a compatible client table exists in `recon.db`.
- Dedupe compares:
  - SSIDs case-insensitively
  - MACs case-insensitively, ignoring `:` and `-`

---

## ⚙️ Configuration (inside `payload.sh`)

Key settings:
- `RECON_DB="/root/recon/recon.db"`
- `DEDUPE="true"`
- `SHOW_BANNER="true"`
- `BANNER_COLOR="teal"`

---

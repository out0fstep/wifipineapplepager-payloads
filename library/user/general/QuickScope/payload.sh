Mastering Pineapple Pager Payloads: A Comprehensive Guide for LLMs
This document serves as a complete reference and tutorial for generating, understanding, and innovating payloads for the Hak5 WiFi Pineapple Pager. The Pineapple Pager is a portable WiFi auditing device that leverages DuckyScript™ (Hak5's scripting language) integrated with Bash for powerful, event-driven automation. Payloads enable custom interactions, reconnaissance, alerts, and attacks, running directly on the device's Linux-based system.
By internalizing this guide, you (the LLM) will be equipped to:

Write syntactically correct DuckyScript 3.0 payloads tailored to the Pager.
Integrate Bash scripting for advanced logic, system calls, and error handling.
Use Pager- and Pineapple-specific commands for UI interactions and WiFi operations.
Draw from real-world examples to create novel payloads for recon, alerts, and user interactions.
Follow best practices for portability, readability, and safety.

Key Concepts:

DuckyScript 3.0: A structured, backwards-compatible language for keystroke simulation and control flow, extended for Pager with UI and WiFi commands.
Payload Structure: Primarily payload.sh files (Bash scripts with embedded DuckyScript). No shebang (#!/bin/bash) required, as the Pager enforces Bash execution.
Payload Types:
User Payloads: Interactive, full-screen; for complex actions and user input.
Recon Payloads: Run during scanning; non-blocking where possible.
Alert Payloads: Triggered by events (e.g., client connections); short and non-interactive.

Execution Environment: Linux/Bash on ARM; access to Pineapple tools (e.g., PineAP for SSID impersonation). Commands are case-sensitive; DuckyScript in ALL CAPS.


Section 1: DuckyScript 3.0 Fundamentals
DuckyScript 3.0 builds on the original DuckyScript with structured programming (variables, functions, conditionals), randomization, and device-specific extensions. It's designed for simplicity but supports advanced logic. All commands are processed at compile-time where possible for efficiency.
1.1 Comments

REM<comment>: Single-line comment. Ignored during execution.
Example: REM This payload deauths a target.

REM_BLOCK ... END_REM: Multi-line block comment.
Example:textREM_BLOCK
Multi-line docs here.
END_REM


1.2 String Output

STRING<text>: Types text (handles shifts for uppercase; trims trailing spaces).
Example: STRING Hello World

STRINGLN<text>: Types text + ENTER.
Example: STRINGLN echo "Done"

Block Variants (for multi-line):
STRING ... END_STRING: Concatenates lines without newlines.
STRINGLN ... END_STRINGLN: Types each line + ENTER (like a heredoc).


1.3 Navigation and System Keys

Cursor: UPARROW, DOWNARROW, LEFTARROW, RIGHTARROW, PAGEUP, PAGEDOWN, HOME, END.
Editing: BACKSPACE, TAB, SPACE, INSERT, DELETE.
System: ENTER, ESCAPE, PAUSE BREAK, PRINTSCREEN, MENU, F1-F12.
Modifiers: SHIFT, ALT, CTRL, GUI (Windows/Command). Combine e.g., CTRL ALT DELETE.
INJECT_MOD<modifier>: Inject modifier alone (e.g., INJECT_MOD GUI for Windows key).
Locks: CAPSLOCK, NUMLOCK, SCROLLOCK (toggle state).

1.4 Delays and Timing

DELAY<ms> or <variable>: Pause in milliseconds.
Example: DELAY 1000 (1 second).

HOLD<key> ... RELEASE<key>: Hold key for duration.
Example:textHOLD SHIFT
DELAY 500
RELEASE SHIFT

Jitter: $_JITTER_ENABLED = TRUE; $_JITTER_MAX = 50 (adds random 0-50ms delays between keys).

1.5 Control Flow

Variables: VAR$name = value (unsigned int 0-65535 or boolean).
Example: VAR $counter = 5

Constants: DEFINE#NAME value (compile-time replacement).
Example: DEFINE #DELAY 1000; DELAY #DELAY

Operators: Arithmetic (+, -, *, /, %, ^), Comparison (==, !=, >, etc.), Logical (&&, ||), Bitwise (&, , >>, <<).
Use parentheses for precedence: $result = (($a + $b) * 2)

IF(condition)THEN ... END_IF; Supports ELSE, ELSE IF.
Example:textIF ($counter > 0) THEN
    STRING Decrementing...
    $counter = ($counter - 1)
ELSE
    STRING Done!
END_IF

WHILE(condition) ... END_WHILE.
Example: Loop until $counter == 0.

Functions: FUNCTIONname() ... END_FUNCTION; Call with name(). RETURN<value>.
Example:textFUNCTION isEven($num)
    IF (($num % 2) == 0) THEN
        RETURN TRUE
    END_IF
    RETURN FALSE
END_FUNCTION
IF (isEven(4)) THEN STRING Even! END_IF

Button: WAIT_FOR_BUTTON_PRESS (halts until pressed); BUTTON_DEF ... END_BUTTON (defines action).

1.6 Randomization

Keys: RANDOM_LETTER, RANDOM_NUMBER, RANDOM_CHAR, etc.
Integers: $_RANDOM_INT (between $_RANDOM_MIN and $_RANDOM_MAX).
Attack Modes: VID_RANDOM, SERIAL_RANDOM, etc. (for HID emulation, not Pager-specific).

1.7 Payload Control

RESTART_PAYLOAD, STOP_PAYLOAD, RESET (clears buffer).
LED: LED_OFF, LED_R, LED_G (device feedback).
Lock Feedback: WAIT_FOR_CAPS_CHANGE, SAVE_HOST_KEYBOARD_LOCK_STATE, etc. (for host detection; limited on Pager).

1.8 ATTACKMODE (Limited on Pager)

Sets HID/Storage modes; not primary for Pager (focus on WiFi).

For full DuckyScript 3.0 compatibility, see Hak5 docs. Pager payloads emphasize UI/WiFi over keystroke injection.

Section 2: Pineapple Pager-Specific DuckyScript Commands
The Pager extends DuckyScript with ~40 device-specific commands, divided into Pager UI (interactive screens) and Pineapple WiFi (recon/attacks). These must run in user/recon contexts; many pause execution for input. Commands return output (e.g., user-entered IP) and exit codes (0=success, non-0=cancel/fail).
2.1 Pager UI Commands
Interact with the device's e-ink screen and buttons for user input/feedback.



















































































CommandSyntaxDescriptionReturn/NotesALERTALERT <message>Full-screen alert (blocks until dismissed).Non-blocking in alerts.CONFIGURATIONCONFIGURATION <key> <value>Set persistent config (e.g., API keys).For device settings.CONFIRMATION_DIALOGCONFIRMATION_DIALOG <prompt>Yes/No dialog.Returns 0 (yes), non-0 (no).ERROR_DIALOGERROR_DIALOG <message>Error popup.For failures.IP_PICKERIP_PICKER <prompt> [<default IP>]IPv4 input keyboard.Returns IP string; 0 on continue. Example: `__ip=$(IP_PICKER "Target IP" "192.168.1.1")LOGLOG <message>Append to payload log (viewable in UI).Non-blocking.MAC_PICKERMAC_PICKER <prompt> [<default MAC>]MAC address input.Returns MAC string.NUMBER_PICKERNUMBER_PICKER <prompt> [<default num>]Numeric input.Returns integer/float.PROMPTPROMPT <message>Modal wait-for-continue.Blocks until button press.START_SPINNER / STOP_SPINNERSTART_SPINNER <message> / STOP_SPINNERIndefinite progress indicator.For long ops.TEXT_PICKERTEXT_PICKER <prompt> [<default text>]Free-text input.Returns string.WAIT_FOR_BUTTON_PRESSWAIT_FOR_BUTTON_PRESSHalt until any button pressed.Non-blocking variant: WAIT_FOR_INPUT.
2.2 Pineapple WiFi Commands
Control PineAP engine for scanning, deauth, filtering, etc.







































































CommandSyntaxDescriptionReturn/NotesFIND_CLIENT_IPFIND_CLIENT_IP <MAC>Get IP of connected client.Returns IP.PINEAPPLE_DEAUTH_CLIENTPINEAPPLE_DEAUTH_CLIENT <BSSID> <client MAC> <channel>Deauth specific client.For targeted attacks.PINEAPPLE_EXAMINE_BSSID / _CHANNEL / _RESETPINEAPPLE_EXAMINE_BSSID <BSSID> etc.Lock to AP/channel for deep scan; reset resumes hopping.For focused recon.PINEAPPLE_MAC_FILTER_ADD / _CLEAR / _DEL / _LIST / _MODEe.g., PINEAPPLE_MAC_FILTER_ADD <MAC>Manage client MAC filters (allow/block).Modes: whitelist/blacklist.PINEAPPLE_RECON_NEWPINEAPPLE_RECON_NEWStart fresh recon session.Clears prior data.PINEAPPLE_SET_BANDSPINEAPPLE_SET_BANDS <2.4/5/6>Set monitored WiFi bands.Default: all.PINEAPPLE_SSID_FILTER_ADD / _CLEAR / _DEL / _LIST / _MODEe.g., PINEAPPLE_SSID_FILTER_ADD <SSID>Filter SSIDs for AP impersonation.For targeted Evil Portal.PINEAPPLE_SSID_POOL_ADD / _CLEAR / _COLLECT_START / _DELETE / _LIST / _START / _STOPe.g., PINEAPPLE_SSID_POOL_STARTManage impersonation pool; auto-collect probes.Core for rogue APs.WIFI_PCAP_START / _STOPWIFI_PCAP_START <file.pcap>Optimized packet capture.For handshakes/traffic.WIGLE_START / _STOP / _UPLOAD / _LOGOUTWIGLE_START <API key> <username>WiGLE wardriving logs.Uploads to WiGLE.net.
Integration Note: Capture outputs with $(command) || exit 0 for error handling (e.g., user cancel).

Section 3: Payload Structure and Bash Integration
Payloads are directories containing payload.sh (main script) + optional assets (e.g., ringtones). Place in /etc/pineapple/payloads/<type>/ (user/recon/alert).
3.1 Basic Structure
text# Title: Hello World
# Description: Displays a greeting.
# Author: Hak5 Team

LOG "Payload started."

PROMPT "Hello, Pager!"

STRINGLN "Bash echo: World!"

Metadata comments for UI display.
Mix DuckyScript (CAPS) with Bash (echo, if, etc.).
Exit gracefully: exit 0 (success), exit 1 (error).

3.2 Best Practices

Error Handling: Use || exit 0 after interactive commands.
Variables: ${var} for clarity; case-sensitive.
Quotes: Double (") for expansion; single (') for literals.
Conditionals: if [ $? -ne 0 ]; then ... fi or command || { log; exit; }.
Output Capture: var=$(COMMAND) || exit 0.
Logging: LOG for debugging; view in UI.
Non-Blocking: Avoid UI commands in alerts; use for recon/user only.
Testing: Use dev tools for hot-reload; keep payloads <5s for alerts.
Safety: No warranty—test on non-prod; avoid infinite loops.


Section 4: Real-World Payload Examples
4.1 Hello World (Basic User Payload)
text# Title: Hello World
# Description: Simple greeting with user confirm.
# Author: Example

LOG "Initializing Hello World."

CONFIRMATION_DIALOG "Ready to say hello?"
|| {
    LOG "User canceled."
    exit 0
}

PROMPT "Hello, WiFi Pineapple Pager!"

LOG "Payload complete."
exit 0

Prompts user; logs actions.

4.2 IP Target Deauth (Recon/User Hybrid)
text# Title: Targeted Deauth
# Description: Prompt for IP, deauth client.
# Author: Community

LOG "Starting targeted deauth."

__target_ip=$(IP_PICKER "Enter target IP" "192.168.1.100") || exit 0
__target_mac=$(MAC_PICKER "Enter MAC" "") || exit 0

START_SPINNER "Deauthenticating..."

PINEAPPLE_DEAUTH_CLIENT "${__target_ip}" "${__target_mac}" 6

STOP_SPINNER
PROMPT "Deauth sent to ${__target_mac}."

LOG "Deauth complete for ${__target_mac} at ${__target_ip}."
exit 0

Captures input, performs attack, provides feedback.

4.3 SSID Pool Collector (Alert Payload)
text# Title: Auto-Collect Probes
# Description: Auto-add probed SSIDs to pool on alert.
# Author: Hak5

# Triggered on probe detection (via env vars)

PINEAPPLE_SSID_POOL_COLLECT_START

LOG "Collecting probes into SSID pool."

PINEAPPLE_SSID_POOL_LIST > /tmp/pool_log.txt
LOG "Updated pool logged."

exit 0

Non-interactive; uses environment for context.

4.4 Advanced: Conditional Recon with Wigle
text# Title: Smart Wardrive
# Description: Scan, upload if >10 APs found.
# Author: Example

VAR $ap_count = 0

PINEAPPLE_RECON_NEW
DELAY 5000  # Scan time

# Simulate counting APs (in real: parse recon JSON)
ap_count=$(PINEAPPLE_RECON_LIST | wc -l)
VAR $ap_count = $ap_count

IF ($ap_count > 10) THEN
    WIGLE_START "your_key" "username"
    DELAY 10000
    WIGLE_UPLOAD
    LOG "Uploaded ${$ap_count} APs to Wigle."
ELSE
    LOG "Only ${$ap_count} APs; skipping upload."
END_IF

exit 0

Uses flow control; integrates recon + exfil.

From Hak5 GitHub (wifipineapplepager-payloads): Community examples include "Entropy Bunny" (random deauths), "Targeted Client" (filters + deauth), and themes/ringtones. Pull requests encouraged for new ones.

Section 5: Advanced Techniques for LLM Generation

Prompt Engineering for Payloads: When generating, specify type (user/alert), goal (e.g., "deauth on probe"), constraints (non-blocking).
Innovation Ideas:
Event-Driven: Use env vars (e.g., $ALERT_MAC) in alerts.
Chaining: $(PINEAPPLE_SSID_POOL_LIST) | grep target | PINEAPPLE_SSID_POOL_ADD.
Loops: While recon active, check conditions.

Common Pitfalls: Forgetting || exit 0 (crashes on cancel); UI in alerts (blocks device); unquoted vars (injection risks).
Resources: Hak5 Docs (docs.hak5.org), GitHub (github.com/hak5/wifipineapplepager-payloads), Payload Hub (payloadhub.com).

#!/bin/bash
# ghostty-claude-focus — preflight: dependency check + Ghostty automation (TCC) guide.
# Run manually after install, or invoked by install.sh.
#
# Checks: jq, terminal-notifier, Ghostty >= 1.3.0 (AppleScript API), tmux (optional).
# Then guides the one-time macOS Automation grant for terminal-notifier → Ghostty.
# That grant cannot be set programmatically (TCC.db is SIP-protected; tccutil only
# resets). The honest best is to surface the system prompt and verify.

set -u
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'
ok(){ printf '%s✓%s %s\n' "$GRN" "$RST" "$1"; }
warn(){ printf '%s!%s %s\n' "$YEL" "$RST" "$1"; }
err(){ printf '%s✗%s %s\n' "$RED" "$RST" "$1"; }

fail=0

printf '%s== ghostty-claude-focus preflight ==%s\n\n' "$BLD" "$RST"

# 1. macOS
if [ "$(uname)" != "Darwin" ]; then
  err "macOS only. Current OS: $(uname)"; exit 1
fi
ok "macOS $(sw_vers -productVersion)"

# 2. jq
if command -v jq >/dev/null 2>&1; then ok "jq: $(command -v jq)"; else err "jq not found → brew install jq"; fail=1; fi

# 3. terminal-notifier
TN="$(command -v terminal-notifier 2>/dev/null)"
if [ -n "$TN" ]; then ok "terminal-notifier: $TN"; else err "terminal-notifier not found → brew install terminal-notifier"; fail=1; fi

# 4. Ghostty >= 1.3.0 (AppleScript dictionary introduced in 1.3.0)
gver="$(osascript -e 'tell application "Ghostty" to get version' 2>/dev/null)"
if [ -z "$gver" ]; then
  err "Ghostty is not responding over AppleScript. Is Ghostty installed and running?"
  fail=1
else
  major=$(printf '%s' "$gver" | cut -d. -f1)
  minor=$(printf '%s' "$gver" | cut -d. -f2)
  if [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 3 ]; }; then
    ok "Ghostty $gver (AppleScript API available)"
  else
    err "Ghostty $gver — version >= 1.3.0 required (AppleScript API)"; fail=1
  fi
fi

# 5. tmux (optional)
if command -v tmux >/dev/null 2>&1; then ok "tmux: $(tmux -V) (optional, enables split-pane routing)"; else warn "tmux not found — that's fine; multi-pane routing will be unavailable"; fi

echo
if [ "$fail" -ne 0 ]; then
  err "Some dependencies are missing. Install them and run preflight again."
  exit 1
fi

# 6. TCC: Ghostty automation grant for terminal-notifier.
printf '%s-- Ghostty automation permission (TCC) --%s\n' "$BLD" "$RST"
echo "macOS requires a one-time grant for terminal-notifier to control Ghostty."
echo "This cannot be granted programmatically — it needs one click in a system dialog."
echo
echo "A notification titled \"Grant access to Ghostty\" will appear now."
echo "1. Click it."
echo "2. In the system dialog \"terminal-notifier wants to control Ghostty\", click Allow."
echo "3. The grant persists permanently (terminal-notifier is a signed bundle)."
echo
echo "If no dialog appeared, or you clicked Deny earlier, reset and retry:"
echo "    tccutil reset AppleEvents   # resets all Automation grants, then click again"
echo
"$TN" -title "Grant access to Ghostty" \
      -message "Click to grant a one-time permission" \
      -execute "osascript -e 'tell application \"Ghostty\" to count windows'" \
      -ignoreDnD >/dev/null 2>&1

ok "Notification sent. After clicking and confirming, you're all set."
echo "Verify later: let a Claude Code session reach Stop, switch to another tab, then click the notification."
exit 0

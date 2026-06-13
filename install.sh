#!/bin/bash
# ghostty-claude-focus — standalone installer (no Claude Code plugin system).
# Copies hook scripts into ~/.claude/hooks and idempotently merges the hook
# registrations into ~/.claude/settings.json (preserving any existing hooks),
# then runs preflight (deps + TCC guide).
#
# Re-running is safe: it replaces only this tool's own hook entries.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/plugins/ghostty-claude-focus/scripts"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "== ghostty-claude-focus installer =="

command -v jq >/dev/null 2>&1 || { echo "jq not found → brew install jq"; exit 1; }

mkdir -p "$HOOKS_DIR"

# 1. Copy scripts.
for s in notify.sh session-register.sh focus-session.sh preflight.sh; do
  cp "$SRC/$s" "$HOOKS_DIR/$s"
  chmod +x "$HOOKS_DIR/$s"
  echo "  installed $HOOKS_DIR/$s"
done

# 2. Merge hooks into settings.json (create if missing).
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"

tmp="$(mktemp)"
jq --arg hd "$HOOKS_DIR" '
  def keepforeign($arr):
    ($arr // []) | map(select(
      ((.hooks // []) | any((.command // "") | test("/(notify|session-register)\\.sh"))) | not
    ));
  def addhook($event; $cmd):
    .hooks[$event] = ( keepforeign(.hooks[$event]) + [ { "hooks": [ { "type":"command", "command":$cmd } ] } ] );
  (.hooks //= {})
  | addhook("Notification";      "bash " + $hd + "/notify.sh Notification")
  | addhook("Stop";              "bash " + $hd + "/notify.sh Stop")
  | addhook("PermissionRequest"; "bash " + $hd + "/notify.sh PermissionRequest")
  | addhook("SessionStart";      "bash " + $hd + "/session-register.sh")
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "  merged hooks into $SETTINGS (backup saved alongside)"
echo

# 3. Preflight (deps + TCC).
bash "$HOOKS_DIR/preflight.sh" || true

echo
echo "Done. Restart Claude Code (or approve the change in /hooks) so the hooks take effect."

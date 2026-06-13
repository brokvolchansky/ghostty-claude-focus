#!/bin/bash
# ghostty-claude-focus — standalone uninstaller.
# Removes this tool's hook entries from ~/.claude/settings.json (leaving any
# other hooks intact) and deletes the installed scripts. Does NOT revoke the
# Ghostty Automation grant (manage that in System Settings → Privacy → Automation).

set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "== ghostty-claude-focus uninstaller =="

command -v jq >/dev/null 2>&1 || { echo "jq не найден → brew install jq"; exit 1; }

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
  tmp="$(mktemp)"
  jq '
    def strip($arr):
      ($arr // []) | map(select(
        ((.hooks // []) | any((.command // "") | test("/(notify|session-register)\\.sh"))) | not
      ));
    if .hooks then
      .hooks.Notification      = strip(.hooks.Notification)
      | .hooks.Stop            = strip(.hooks.Stop)
      | .hooks.PermissionRequest = strip(.hooks.PermissionRequest)
      | .hooks.SessionStart    = strip(.hooks.SessionStart)
      # drop now-empty event arrays
      | .hooks |= with_entries(select(.value | length > 0))
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "  removed hook entries from $SETTINGS (backup saved alongside)"
fi

for s in notify.sh session-register.sh focus-session.sh preflight.sh; do
  if [ -f "$HOOKS_DIR/$s" ]; then rm -f "$HOOKS_DIR/$s"; echo "  removed $HOOKS_DIR/$s"; fi
done

# Optional: clear the runtime registry.
rm -rf "${TMPDIR:-/tmp}/claude-focus" 2>/dev/null || true

echo
echo "Готово. Разрешение на автоматизацию Ghostty осталось — убрать вручную в System Settings → Privacy → Automation."

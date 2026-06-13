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
  err "Только macOS. Текущая ОС: $(uname)"; exit 1
fi
ok "macOS $(sw_vers -productVersion)"

# 2. jq
if command -v jq >/dev/null 2>&1; then ok "jq: $(command -v jq)"; else err "jq не найден → brew install jq"; fail=1; fi

# 3. terminal-notifier
TN="$(command -v terminal-notifier 2>/dev/null)"
if [ -n "$TN" ]; then ok "terminal-notifier: $TN"; else err "terminal-notifier не найден → brew install terminal-notifier"; fail=1; fi

# 4. Ghostty >= 1.3.0 (AppleScript dictionary introduced in 1.3.0)
gver="$(osascript -e 'tell application "Ghostty" to get version' 2>/dev/null)"
if [ -z "$gver" ]; then
  err "Ghostty не отвечает по AppleScript. Установлен ли Ghostty? Запущен ли он?"
  fail=1
else
  major=$(printf '%s' "$gver" | cut -d. -f1)
  minor=$(printf '%s' "$gver" | cut -d. -f2)
  if [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 3 ]; }; then
    ok "Ghostty $gver (AppleScript API доступен)"
  else
    err "Ghostty $gver — нужен >= 1.3.0 (AppleScript API)"; fail=1
  fi
fi

# 5. tmux (optional)
if command -v tmux >/dev/null 2>&1; then ok "tmux: $(tmux -V) (опционально, поддержка split-панелей)"; else warn "tmux не найден — это нормально; мульти-pane маршрутизация будет недоступна"; fi

echo
if [ "$fail" -ne 0 ]; then
  err "Не все зависимости на месте. Установи недостающее и запусти preflight снова."
  exit 1
fi

# 6. TCC: Ghostty automation grant for terminal-notifier.
printf '%s-- Разрешение на автоматизацию Ghostty (TCC) --%s\n' "$BLD" "$RST"
echo "macOS требует один раз разрешить terminal-notifier управлять Ghostty."
echo "Это нельзя выдать программно — нужен один клик в системном окне."
echo
echo "Сейчас придёт уведомление «Разрешите доступ к Ghostty»."
echo "1. Нажми на него."
echo "2. В системном окне «terminal-notifier wants to control Ghostty» нажми Allow / Разрешить."
echo "3. Разрешение сохранится навсегда (terminal-notifier — подписанный бандл)."
echo
echo "Если окно не появилось или ранее нажал Deny — сбрось запись и повтори:"
echo "    tccutil reset AppleEvents   # сбросит все Automation-разрешения, затем повтори клик"
echo
"$TN" -title "Разрешите доступ к Ghostty" \
      -message "Нажми, чтобы выдать однократное разрешение" \
      -execute "osascript -e 'tell application \"Ghostty\" to count windows'" \
      -ignoreDnD >/dev/null 2>&1

ok "Уведомление отправлено. После клика и подтверждения всё готово."
echo "Проверить позже: дай сессии Claude Code дойти до Stop, переключись на другую вкладку и кликни по баллону."
exit 0

#!/bin/bash
# ghostty-claude-focus — focus the Ghostty tab (and tmux pane) behind a notification.
# Usage: focus-session.sh <session_id> [fallback_term_pid]
#
# Runs in a clean shell spawned by terminal-notifier -execute (no $TMUX here),
# so all state is read from the registry written by session-register.sh.
#
# Primary path : tmux select-pane (if applicable) + Ghostty focus by UUID.
# Fallback path: activate the GUI terminal process by PID (legacy behaviour),
#                used when the registry is missing or holds no UUID.
#
# All Ghostty / System Events AppleScript is serialised against session-register.sh
# through a shared mkdir lock and carries `with timeout`, so concurrent access
# can't pile up into the macOS "waiting for Ghostty" dialog or hang on a busy app.

set -u
sid="${1:-}"
fallback_pid="${2:-}"

# Same path as session-register.sh. $HOME is the anchor: it is identical across
# the session process and this terminal-notifier-spawned process, unlike $TMPDIR.
dir="$HOME/.cache/ghostty-claude-focus"

# Shared serialisation lock + timeout wrapper (mirror of session-register.sh).
lock="$dir/.lock"
gcf_lock() {
  local n=0 m
  while ! mkdir "$lock" 2>/dev/null; do
    m=$(stat -f %m "$lock" 2>/dev/null)
    if [ -n "$m" ] && [ "$(( $(date +%s) - m ))" -ge 15 ]; then
      rmdir "$lock" 2>/dev/null; continue
    fi
    n=$((n + 1)); [ "$n" -ge 50 ] && return 1   # ~5s → give up, proceed
    sleep 0.1
  done
  return 0
}
gcf_unlock() { rmdir "$lock" 2>/dev/null; }
gosa() { osascript -e 'with timeout of 5 seconds' "$@" -e 'end timeout' 2>/dev/null; }

do_fallback() {
  [ -n "$fallback_pid" ] || return 0
  gosa -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $fallback_pid) to true"
}

f="$dir/$sid"
if [ -z "$sid" ] || [ ! -f "$f" ]; then
  gcf_lock; do_fallback; gcf_unlock
  exit 0
fi

# shellcheck disable=SC1090
. "$f"

# tmux: switch the attached client to the originating window/pane. Pane ids (%N)
# resolve from any shell while the tmux server lives. (Not Ghostty AS — no lock.)
if [ "${IN_TMUX:-0}" = "1" ] && [ -n "${TMUX_PANE:-}" ]; then
  tmux select-window -t "$TMUX_PANE" 2>/dev/null
  tmux select-pane   -t "$TMUX_PANE" 2>/dev/null
fi

gcf_lock   # serialise Ghostty access against session-register.sh

# Ghostty: bring the originating tab to front by its UUID. `focus` selects the
# terminal and raises its window.
if [ -n "${GHOSTTY_ID:-}" ]; then
  if gosa -e "tell application \"Ghostty\" to focus (first terminal whose id is \"$GHOSTTY_ID\")"; then
    gcf_unlock
    exit 0
  fi
fi

do_fallback
gcf_unlock
exit 0

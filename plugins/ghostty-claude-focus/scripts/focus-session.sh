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

set -u
sid="${1:-}"
fallback_pid="${2:-}"

dir="${TMPDIR:-/tmp}/claude-focus"

do_fallback() {
  [ -n "$fallback_pid" ] || return 0
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $fallback_pid) to true" 2>/dev/null
}

f="$dir/$sid"
if [ -z "$sid" ] || [ ! -f "$f" ]; then
  do_fallback
  exit 0
fi

# shellcheck disable=SC1090
. "$f"

# tmux: switch the attached client to the originating window/pane.
# Pane ids (%N) are resolvable from any shell while the tmux server lives.
if [ "${IN_TMUX:-0}" = "1" ] && [ -n "${TMUX_PANE:-}" ]; then
  tmux select-window -t "$TMUX_PANE" 2>/dev/null
  tmux select-pane   -t "$TMUX_PANE" 2>/dev/null
fi

# Ghostty: bring the originating tab to front by its UUID.
# `focus` selects the terminal and raises its window.
if [ -n "${GHOSTTY_ID:-}" ]; then
  if osascript -e "tell application \"Ghostty\" to focus (first terminal whose id is \"$GHOSTTY_ID\")" 2>/dev/null; then
    exit 0
  fi
fi

do_fallback
exit 0

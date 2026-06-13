#!/bin/bash
# ghostty-claude-focus — session → Ghostty tab registry.
# Hook: SessionStart. Reads JSON payload from stdin.
#
# Captures, keyed by full session_id, under $HOME/.cache/ghostty-claude-focus.
# $HOME is the anchor because the two scripts run in different process contexts
# (this one inside the Claude Code session; focus-session.sh from terminal-notifier)
# and $HOME is the only path component guaranteed identical across both — unlike
# $TMPDIR, which differs per process on macOS, or /tmp, which is world-readable:
#   GHOSTTY_ID  — UUID of the Ghostty terminal hosting this session's tab,
#                 taken as the focused terminal of the selected tab of the
#                 front Ghostty window at session start. This is the only
#                 stable, unique, AppleScript-queryable identifier of a tab
#                 (working directory is non-unique; name is clobbered by tmux).
#   IN_TMUX     — 1 if running inside tmux, else 0.
#   TMUX_PANE   — tmux pane id (e.g. %5) for intra-tab pane disambiguation
#                 when several sessions share one Ghostty tab via tmux splits.
#
# focus-session.sh consumes this on notification click.

set -u
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
[ -z "$sid" ] && exit 0

dir="$HOME/.cache/ghostty-claude-focus"
mkdir -p "$dir" 2>/dev/null

# UUID of the Ghostty tab focused at session start.
gid=$(osascript -e 'tell application "Ghostty" to get id of focused terminal of selected tab of front window' 2>/dev/null)

in_tmux=0
pane=""
if [ -n "${TMUX:-}" ]; then
  in_tmux=1
  pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
fi

{
  printf 'GHOSTTY_ID=%s\n' "$gid"
  printf 'IN_TMUX=%s\n' "$in_tmux"
  printf 'TMUX_PANE=%s\n' "$pane"
} > "$dir/$sid" 2>/dev/null

exit 0

#!/bin/bash
# ghostty-claude-focus — session → Ghostty surface registry.
# Hook: SessionStart. Reads JSON payload from stdin.
#
# Captures, keyed by full session_id, under $HOME/.cache/ghostty-claude-focus.
# $HOME is the anchor because the two scripts run in different process contexts
# (this one inside the Claude Code session; focus-session.sh from terminal-notifier)
# and $HOME is the only path component guaranteed identical across both — unlike
# $TMPDIR, which differs per process on macOS, or /tmp, which is world-readable:
#   GHOSTTY_ID  — UUID of THIS session's own Ghostty surface (tab).
#   IN_TMUX     — 1 if running inside tmux, else 0.
#   TMUX_PANE   — tmux pane id (e.g. %5) for intra-tab pane disambiguation
#                 when several sessions share one Ghostty tab via tmux splits.
#
# How the surface is resolved (the title-marker method)
# ─────────────────────────────────────────────────────
# Ghostty (<=1.3.1) gives a process no way to learn its own surface: the
# AppleScript `terminal` class exposes no pid/tty (ghostty-org/ghostty#11592),
# and there is no inheritable surface-id env var yet (discussion #10603; the
# GHOSTTY_SURFACE_ID / present-surface work is unreleased). Capturing whatever
# tab is FRONTMOST (`focused terminal of selected tab of front window`) records
# the WRONG tab whenever the active tab differs from this session's tab — the
# user opened/switched a tab, or the session started in a background tab. That
# was the wrong-tab-focus bug.
#
# Instead we tag OUR surface with a unique title marker written into the
# surface's own controlling tty, then ask Ghostty for the terminal whose name
# carries that marker. The marker travels down our own tty, so it can only land
# on our surface — an exact match, independent of which tab is frontmost:
#   - bare shell : our controlling tty IS the surface pty   → write to /dev/tty
#   - inside tmux: our tty is the pane pty, NOT the surface; the surface pty is
#                  the attached client's tty                → write to client_tty
# The clobbered title is restored right after (inside tmux from the expanded
# set-titles-string; a bare shell's next prompt repaints it via shell
# integration). A short retry loop covers the title-churn race.
#
# focus-session.sh consumes GHOSTTY_ID on notification click.

set -u

# ─── Teammate filter ────────────────────────────────────────────────
# Sub-agent/teammate sessions must NOT pollute the registry: notify.sh already
# suppresses their notifications, so nothing ever focuses their record. Walk the
# ancestor chain inspecting `ps -o args=` (NOT comm — macOS shows the disclaimer
# wrapper there, not `claude`) for teammate markers. Mirrors notify.sh. Ref:
# github.com/anthropics/claude-code/issues/35447.
is_teammate_invocation() {
  local pid="$PPID"
  local ppid args steps=0
  while [ "$steps" -lt 25 ]; do
    args=$(ps -o args= -p "$pid" 2>/dev/null)
    if [ -n "$args" ]; then
      if printf '%s' "$args" | grep -qE -- '(--agent-id|--agent-name|--team-name|--parent-session-id|--agent-type|--agent-color)([= ]|$)'; then
        return 0
      fi
    fi
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && return 1
    [ "$ppid" -le 1 ] && return 1
    pid="$ppid"
    steps=$((steps + 1))
  done
  return 1
}

is_teammate_invocation && exit 0

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
[ -z "$sid" ] && exit 0

dir="$HOME/.cache/ghostty-claude-focus"
mkdir -p "$dir" 2>/dev/null

in_tmux=0
pane=""
if [ -n "${TMUX:-}" ]; then
  in_tmux=1
  pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
fi

# Find the tty that maps to OUR Ghostty surface.
surface_tty=""
if [ "$in_tmux" = "1" ]; then
  # The surface pty is the tty of the client attached to our tmux session,
  # not our pane pty. (Multi-client attach is rare; take the first.)
  msess=$(tmux display-message -p '#{session_name}' 2>/dev/null)
  surface_tty=$(tmux list-clients -t "$msess" -F '#{client_tty}' 2>/dev/null | head -1)
else
  surface_tty=$(tty 2>/dev/null)
  case "$surface_tty" in /dev/*) ;; *) surface_tty="" ;; esac
fi

# Tag our surface with a unique marker and read back its UUID by that marker.
gid=""
if [ -n "$surface_tty" ] && [ -w "$surface_tty" ]; then
  marker="gcf-${sid}-$$"
  i=0
  while [ "$i" -lt 10 ]; do
    printf '\033]2;%s\007' "$marker" > "$surface_tty" 2>/dev/null
    gid=$(osascript -e "tell application \"Ghostty\" to get id of (first terminal whose name contains \"$marker\")" 2>/dev/null)
    [ -n "$gid" ] && break
    i=$((i + 1))
  done
  # Restore the title we clobbered. Inside tmux the surface title is whatever
  # set-titles-string expands to right now (#{T:...}); write that back directly,
  # because tmux won't repaint a title it didn't change. A bare shell's next
  # prompt repaints via shell-integration, so there is nothing to do there.
  if [ "$in_tmux" = "1" ]; then
    real=$(tmux display-message -p '#{T:set-titles-string}' 2>/dev/null)
    [ -z "$real" ] && real=$(tmux display-message -p '#{pane_title}' 2>/dev/null)
    [ -n "$real" ] && printf '\033]2;%s\007' "$real" > "$surface_tty" 2>/dev/null
  fi
fi

# Never regress below the old behaviour: if the marker method could not resolve
# a surface (no writable tty, AppleScript unavailable), fall back to the
# frontmost-tab capture the previous version used.
if [ -z "$gid" ]; then
  gid=$(osascript -e 'tell application "Ghostty" to get id of focused terminal of selected tab of front window' 2>/dev/null)
fi

{
  printf 'GHOSTTY_ID=%s\n' "$gid"
  printf 'IN_TMUX=%s\n' "$in_tmux"
  printf 'TMUX_PANE=%s\n' "$pane"
} > "$dir/$sid" 2>/dev/null

# ─── Prune dead records ─────────────────────────────────────────────
# The registry lives under $HOME/.cache (persistent — it does NOT clear on
# reboot), and every session that ever ran leaves a file, so it grows without
# bound. Drop records whose surface no longer exists. We only delete when we
# could enumerate live surfaces (non-empty list) and only records carrying a
# non-empty GHOSTTY_ID that is absent from it — so our just-written record (a
# live surface) and any fallback records with no UUID are preserved.
live=$(osascript -e 'tell application "Ghostty" to get id of every terminal' 2>/dev/null)
if [ -n "$live" ]; then
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    g=$(sed -n 's/^GHOSTTY_ID=//p' "$f")
    [ -z "$g" ] && continue
    case "$live" in
      *"$g"*) ;;
      *) rm -f "$f" 2>/dev/null ;;
    esac
  done
fi

exit 0

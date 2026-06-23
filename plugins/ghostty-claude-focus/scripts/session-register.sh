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
# and there is no inheritable surface-id env var yet (discussion #10603). Capturing
# whatever tab is FRONTMOST records the WRONG tab whenever the active tab differs
# from this session's tab. Instead we tag OUR surface with a unique title marker
# written into the surface's own controlling tty, then ask Ghostty for the
# terminal whose name carries that marker — an exact match, frontmost-independent:
#   - bare shell : our controlling tty IS the surface pty   → write to /dev/tty
#   - inside tmux: our tty is the pane pty, NOT the surface; the surface pty is
#                  the attached client's tty                → write to client_tty
# The clobbered title is restored right after.
#
# Not hanging Ghostty
# ───────────────────
# Ghostty serves AppleScript on one thread, so concurrent osascript calls from
# several sessions pile up and surface the macOS "waiting for Ghostty" dialog.
# Two guards: a shared mkdir lock serialises all Ghostty access to one process at
# a time, and every osascript carries `with timeout` so a busy Ghostty fails the
# call fast instead of hanging this (synchronous) hook. The registry prune only
# runs past a size threshold, to avoid an enumerate-all call on every start.
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

# ─── Ghostty access guards ──────────────────────────────────────────
# Serialise all Ghostty AppleScript via an atomic mkdir lock in the shared
# registry dir (same $HOME anchor focus-session.sh uses). Bounded wait, because
# SessionStart is synchronous and must not stall Claude's startup; a lock older
# than 15s is assumed dead and stolen.
lock="$dir/.lock"
gcf_lock() {
  local n=0 m
  while ! mkdir "$lock" 2>/dev/null; do
    m=$(stat -f %m "$lock" 2>/dev/null)
    if [ -n "$m" ] && [ "$(( $(date +%s) - m ))" -ge 15 ]; then
      rmdir "$lock" 2>/dev/null; continue
    fi
    n=$((n + 1)); [ "$n" -ge 50 ] && return 1   # ~5s elapsed → give up, proceed
    sleep 0.1
  done
  return 0
}
gcf_unlock() { rmdir "$lock" 2>/dev/null; }

# Every Ghostty osascript goes through here: a hard timeout turns a hung/busy
# Ghostty into a fast failure instead of a stalled hook.
gosa() { osascript -e 'with timeout of 5 seconds' "$@" -e 'end timeout' 2>/dev/null; }

in_tmux=0
pane=""
if [ -n "${TMUX:-}" ]; then
  in_tmux=1
  pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
fi

# Find the tty that maps to OUR Ghostty surface (no Ghostty access — pre-lock).
surface_tty=""
if [ "$in_tmux" = "1" ]; then
  msess=$(tmux display-message -p '#{session_name}' 2>/dev/null)
  surface_tty=$(tmux list-clients -t "$msess" -F '#{client_tty}' 2>/dev/null | head -1)
else
  surface_tty=$(tty 2>/dev/null)
  case "$surface_tty" in /dev/*) ;; *) surface_tty="" ;; esac
fi

gcf_lock   # serialise Ghostty access; proceeds anyway after ~5s if not acquired

# Tag our surface with a unique marker and read back its UUID by that marker.
gid=""
if [ -n "$surface_tty" ] && [ -w "$surface_tty" ]; then
  marker="gcf-${sid}-$$"
  i=0
  while [ "$i" -lt 10 ]; do
    printf '\033]2;%s\007' "$marker" > "$surface_tty" 2>/dev/null
    gid=$(gosa -e "tell application \"Ghostty\" to get id of (first terminal whose name contains \"$marker\")")
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
  gid=$(gosa -e 'tell application "Ghostty" to get id of focused terminal of selected tab of front window')
fi

{
  printf 'GHOSTTY_ID=%s\n' "$gid"
  printf 'IN_TMUX=%s\n' "$in_tmux"
  printf 'TMUX_PANE=%s\n' "$pane"
} > "$dir/$sid" 2>/dev/null

# ─── Prune dead records (throttled) ─────────────────────────────────
# The registry lives under $HOME/.cache (persistent — it does NOT clear on
# reboot), so it grows. Drop records whose surface is gone, but only once the
# directory has grown past a threshold, so the enumerate-all-terminals call does
# not run on every single start. We only delete when we could enumerate live
# surfaces and only records with a non-empty GHOSTTY_ID absent from that list, so
# our just-written record and any UUID-less fallback records are preserved.
n=0
for f in "$dir"/*; do [ -f "$f" ] && n=$((n + 1)); done
if [ "$n" -gt 40 ]; then
  live=$(gosa -e 'tell application "Ghostty" to get id of every terminal')
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
fi

gcf_unlock
exit 0

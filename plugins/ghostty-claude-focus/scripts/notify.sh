#!/bin/bash
# ghostty-claude-focus — notifier via terminal-notifier.
# https://github.com/brokvolchansky/ghostty-claude-focus
# Usage: notify.sh <event-name>
# Reads a Claude Code hook JSON payload from stdin, parses it with jq, and
# dispatches a macOS notification. Clicking the notification focuses the exact
# Ghostty tab (and tmux pane) that produced it.
#
# Portable: resolves its own directory, so it works both as a Claude Code
# plugin (under the plugin cache) and as a standalone install (~/.claude/hooks).
# terminal-notifier is located via `command -v`, not a hardcoded path.
#
# Teammate filter
# ───────────────
# Walks up the process tree, inspects `ps -o args=` of each ancestor (NOT comm,
# because on macOS comm shows the disclaimer-wrapper, not `claude`). If any
# ancestor's args carry teammate markers (--agent-id, --agent-name, --team-name,
# --parent-session-id, --agent-type, --agent-color), the invocation is from a
# teammate — exit silently. Ref: github.com/anthropics/claude-code/issues/35447.

set -u
event="${1:-Unknown}"
input=$(cat)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate terminal-notifier (Homebrew: /opt/homebrew on Apple Silicon,
# /usr/local on Intel). If absent, there is nothing to do.
TN="$(command -v terminal-notifier 2>/dev/null)"
[ -z "$TN" ] && exit 0

# ─── Teammate filter ────────────────────────────────────────────────
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

if is_teammate_invocation; then
  exit 0
fi

# ─── Payload parsing ────────────────────────────────────────────────
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
project=$(basename "${cwd:-Claude}")
session_full=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
session=$(printf '%s' "$session_full" | cut -c1-8)

# Walk up parent process chain until we find the GUI app (whose parent is launchd / PID 1).
walk_to_gui_ancestor() {
  local pid=$1
  local ppid
  while :; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break
    [ "$ppid" -le 1 ] && break
    pid=$ppid
  done
  echo "$pid"
}

# Find the GUI terminal app PID hosting this Claude session (fallback target).
# Inside tmux: real GUI is the tmux client attached to our session.
# Outside tmux: walk up from script PID directly.
find_terminal_pid() {
  if [ -n "${TMUX:-}" ]; then
    local sid cpid
    sid=$(printf '%s' "$TMUX" | awk -F, '{print $3}')
    cpid=$(tmux list-clients -t "$sid" -F '#{client_pid}' 2>/dev/null | head -1)
    if [ -n "$cpid" ]; then
      walk_to_gui_ancestor "$cpid"
      return
    fi
  fi
  walk_to_gui_ancestor "$PPID"
}

term_pid=$(find_terminal_pid)

# Click target: focus the exact Ghostty tab (+ tmux pane) that produced this
# notification, via the session→tab registry. Falls back to activating the GUI
# terminal process by PID when no UUID was captured for this session.
activate_cmd="bash $SCRIPT_DIR/focus-session.sh '$session_full' '$term_pid'"

case "$event" in
  Stop)
    "$TN" \
      -title "Claude Code — ready" \
      -subtitle "$project" \
      -message "Session ${session:-?} is waiting" \
      -sound Glass \
      -group "claude-stop-$session" \
      -execute "$activate_cmd" \
      -ignoreDnD >/dev/null 2>&1
    ;;
  PermissionRequest)
    tool=$(printf '%s' "$input" | jq -r '.tool_name // "tool"' 2>/dev/null)
    detail=$(printf '%s' "$input" | jq -r '
      .tool_input.command
      // .tool_input.file_path
      // .tool_input.url
      // .tool_input.pattern
      // .tool_input.path
      // ""' 2>/dev/null | head -c 200)
    "$TN" \
      -title "Claude Code — permission needed" \
      -subtitle "$project — $tool" \
      -message "${detail:-no request details}" \
      -sound Ping \
      -group "claude-perm-$session" \
      -execute "$activate_cmd" \
      -ignoreDnD >/dev/null 2>&1
    ;;
  Notification)
    ntype=$(printf '%s' "$input" | jq -r '.notification_type // .hook_event_name // "notification"' 2>/dev/null)
    case "$ntype" in
      idle_prompt|permission_prompt) exit 0 ;;
    esac
    msg=$(printf '%s' "$input" | jq -r '.message // ""' 2>/dev/null | head -c 200)
    "$TN" \
      -title "Claude Code" \
      -subtitle "$project — $ntype" \
      -message "${msg:-no message}" \
      -sound Glass \
      -group "claude-notif-$session" \
      -execute "$activate_cmd" \
      -ignoreDnD >/dev/null 2>&1
    ;;
  *)
    "$TN" \
      -title "Claude Code — $event" \
      -subtitle "$project" \
      -message "Hook fired" \
      -sound Glass \
      -group "claude-other-$session" \
      -execute "$activate_cmd" \
      -ignoreDnD >/dev/null 2>&1
    ;;
esac

exit 0

# ghostty-claude-focus

macOS notifications for [Claude Code](https://www.anthropic.com/claude-code) that **focus the exact [Ghostty](https://ghostty.org) tab — and tmux pane — that produced them**.

When you run several Claude Code sessions across multiple Ghostty tabs, a "Claude is waiting" notification is only useful if clicking it takes you to the *right* session. This tool does that: each notification click raises the precise tab (and, inside tmux, selects the precise pane) where that session lives.

## How it works

Ghostty's AppleScript dictionary exposes a stable per-tab UUID but **not** a TTY, and the working directory is often shared across tabs — so neither can reliably identify a tab. The approach is a two-layer registry:

1. **`SessionStart` hook** records, per Claude `session_id`, the UUID of the hosting Ghostty tab plus (if inside tmux) the tmux `pane_id`.
2. **On notification click**, the handler reads that record, runs `tmux select-pane` to switch to the originating pane (when several sessions share one tab via splits), then uses Ghostty's `focus` command to raise the tab by UUID.

If a session has no record (e.g. it predates installation), the click falls back to simply activating the terminal app.

A teammate filter suppresses notifications from Claude Code sub-agent/teammate processes, so only the lead session notifies.

## Requirements

- **macOS** (tested on Tahoe 26.x)
- **Ghostty ≥ 1.3.0** — the AppleScript API was introduced in 1.3.0
- **Claude Code**
- [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) — `brew install terminal-notifier`
- [`jq`](https://jqlang.github.io/jq/) — `brew install jq`
- **tmux** — optional; only needed for pane-level routing within a shared tab

This tool is **Ghostty-specific**: the focus logic relies on Ghostty's scripting dictionary and will not work with iTerm2, Terminal.app, WezTerm, or kitty.

## Install

### Option A — Claude Code plugin (recommended)

```
/plugin marketplace add brokvolchansky/ghostty-claude-focus
/plugin install ghostty-claude-focus@brokvolchansky
```

Hooks register automatically once you **restart Claude Code**. Then complete the one-time Automation grant — see [One-time Automation grant](#one-time-automation-grant-tcc) below.

> Replace `brokvolchansky/ghostty-claude-focus` with your own `owner/repo` if you fork it.

### Option B — standalone installer

```
git clone https://github.com/brokvolchansky/ghostty-claude-focus.git
cd ghostty-claude-focus
./install.sh
```

`install.sh` copies the scripts to `~/.claude/hooks`, idempotently merges the hooks into `~/.claude/settings.json` (leaving any existing hooks untouched), and runs preflight. Re-running is safe.

## One-time Automation grant (TCC)

macOS requires you to allow `terminal-notifier` to control Ghostty — **once**. This cannot be granted programmatically (the TCC database is SIP-protected), so it is surfaced as a normal system prompt:

- **Standalone install:** `install.sh` runs preflight, which fires a notification titled **"Grant access to Ghostty"** — click it.
- **Plugin install:** the prompt appears the first time you click any Claude Code notification. To trigger it proactively, run `preflight.sh` from the plugin's cache directory under `~/.claude/plugins/cache/`.

In the system dialog **"terminal-notifier wants to control Ghostty"**, click **Allow**. The grant persists permanently (terminal-notifier is a signed bundle with a stable bundle id).

If the dialog never appeared, or you clicked Deny earlier, reset and retry:

```bash
tccutil reset AppleEvents
# standalone: re-run preflight to fire the prompt again
bash ~/.claude/hooks/preflight.sh
```

## Verify

Let a Claude Code session reach a `Stop`, switch to another tab, then click the notification — it should jump to that session's tab.

## Notes & limitations

- **Sessions started before installation** are not in the registry; clicking their notifications falls back to activating the app (no tab switch). They register on the next `SessionStart` — e.g. after `/compact`, `/clear`, `/resume`, or a restart.
- The registry lives in `${TMPDIR}/claude-focus` and clears on reboot; it repopulates as sessions start.
- Notification strings are currently in Russian; edit `scripts/notify.sh` to change them.

## Uninstall

Standalone:

```
./uninstall.sh
```

Plugin: `/plugin uninstall ghostty-claude-focus@brokvolchansky`. The Ghostty Automation grant is left in place — remove it manually in System Settings → Privacy & Security → Automation.

## License

MIT — see [LICENSE](LICENSE).

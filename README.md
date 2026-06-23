# ghostty-claude-focus

macOS notifications for [Claude Code](https://www.anthropic.com/claude-code) that **focus the exact [Ghostty](https://ghostty.org) tab — and tmux pane — that produced them**.

When you run several Claude Code sessions across multiple Ghostty tabs, a "Claude is waiting" notification is only useful if clicking it takes you to the *right* session. This tool does that: each notification click raises the precise tab (and, inside tmux, selects the precise pane) where that session lives.

## How it works

Ghostty's AppleScript dictionary exposes a stable per-tab UUID but **not** a TTY or PID, and there is no inheritable surface-id env var ([ghostty-org/ghostty#11592](https://github.com/ghostty-org/ghostty/issues/11592), [discussion #10603](https://github.com/ghostty-org/ghostty/discussions/10603)) — so a process cannot directly tell which tab it runs in. The working directory is often shared across tabs, and the frontmost tab is just whatever the user happens to be looking at. The approach is a two-layer registry that pins the tab by a self-tag:

1. **`SessionStart` hook** writes a unique title marker into its *own* surface's controlling tty (the attached client's tty inside tmux, otherwise `/dev/tty`), then asks Ghostty for the terminal whose title carries that marker and records its UUID — keyed by Claude `session_id`, with the tmux `pane_id` when inside tmux. Because the marker travels down the session's own tty, the captured tab is exact no matter which tab is frontmost or how tabs are later reordered; the original title is restored at once.
2. **On notification click**, the handler reads that record, runs `tmux select-pane` to switch to the originating pane (when several sessions share one tab via splits), then uses Ghostty's `focus` command to raise the tab by UUID.

If a session has no record (e.g. it predates installation), the click falls back to simply activating the terminal app.

A teammate filter runs in both hooks: it suppresses notifications from Claude Code sub-agent/teammate processes (so only the lead session notifies) and keeps those sessions out of the registry.

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
- The registry lives in `$HOME/.cache/ghostty-claude-focus`. It does not clear on reboot, so each `SessionStart` also prunes records whose Ghostty surface no longer exists.
- Notification strings are currently in Russian; edit `scripts/notify.sh` to change them.

## Uninstall

Standalone:

```
./uninstall.sh
```

Plugin: `/plugin uninstall ghostty-claude-focus@brokvolchansky`. The Ghostty Automation grant is left in place — remove it manually in System Settings → Privacy & Security → Automation.

## Development

The plugin version in `plugin.json` is Claude Code's update key. A `pre-commit` hook in `.githooks/` auto-bumps the patch version whenever a commit touches `scripts/` or `hooks/`, so code changes ship as new versions without manual edits (docs-only commits don't bump). Enable it once after cloning:

```bash
git config core.hooksPath .githooks
```

## License

MIT — see [LICENSE](LICENSE).

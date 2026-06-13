# Privacy Policy

`ghostty-claude-focus` is a local macOS utility for Claude Code. It does **not**
collect, transmit, or share any personal data.

## What the plugin does

The plugin reacts to Claude Code hook events (`Stop`, `Notification`,
`PermissionRequest`, `SessionStart`). On each event it shows a local macOS
notification, and when you click that notification it focuses the Ghostty tab and
tmux pane that produced it.

## Data it stores

To map a notification back to the session that fired it, the plugin keeps a small
local registry under:

```
$HOME/.cache/ghostty-claude-focus/
```

Each entry is keyed by the Claude Code session id and contains only:

- the Ghostty terminal UUID of that session's tab,
- a flag indicating whether the session runs inside tmux,
- the tmux pane id (e.g. `%46`), if applicable.

This data never leaves your machine. It contains no message content, no file
contents, no credentials, and no personal information. The registry is recreated
on each session start and can be cleared at any time by deleting the directory
above (the uninstaller does this for you).

## Network and third parties

The plugin makes **no network requests**. It sends no telemetry or analytics and
uses no third-party service. Notifications are delivered locally via
`terminal-notifier`; tab and pane focus is performed locally via AppleScript and
tmux.

## System permissions

On first use, macOS asks you to allow `terminal-notifier` to control Ghostty (an
Automation / Apple Events permission). This permission is used solely to bring the
relevant Ghostty tab to the front. The plugin does not read or modify any other
application or its data.

## Contact

Questions or concerns: please open an issue at
<https://github.com/brokvolchansky/ghostty-claude-focus/issues>.

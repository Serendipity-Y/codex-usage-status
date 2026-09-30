# Technical review

## Current architecture

The app is intentionally split into two pieces:

- Native macOS UI: AppKit status item in `macos/CodexUsageStatus`.
- Probe/test layer: Node client and formatter tests in `src/` and `test/`.

The production app does not need Node at runtime. It directly spawns the Codex executable bundled with ChatGPT when available, or the standalone Codex app otherwise. The default ChatGPT path is:

```sh
/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex app-server --listen stdio://
```

Then it sends the official JSON-RPC method:

```json
{"method":"account/rateLimits/read","id":2}
```

## Why this is safer than patching Codex.app

Patching the packaged Codex desktop bundle breaks signing and ASAR integrity assumptions. A companion app keeps Codex untouched and relies on the same official local app-server boundary used by supported integrations.

## Menu-bar display

The default menu-bar display is a side-labeled double-ring badge.

The left ring group represents the 5-hour window and the right ring group represents the 7-day weekly window. Each label sits beside its own ring rather than inside the ring, so the ring center only has to carry the remaining percentage number. The `5H` and `7D` labels are stacked into matching two-character micro-labels for visual balance. The badge intentionally avoids a capsule background so it feels like a native lightweight menu-bar status item instead of a separate floating control.

This keeps the menu-bar footprint narrow while making the two quota windows visually distinct. The click menu is intentionally minimal: Refresh, Settings, and Quit.

The optional Large Readout style is designed for readability. It uses larger monospaced numbers as the primary visual layer, keeps `5H` / `7D` as weak labels, and moves status expression into subtle bottom lines. It also avoids the capsule background.

Hovering the badge opens a white card with the available reset count, 5-hour reset, weekly reset, and next data refresh. Clicking continues to open the menu.

The optional ChatGPT lifecycle helper starts the badge when the ChatGPT app starts and quits it when the last ChatGPT process exits. It runs separately from the badge app.

## Refresh behavior

Refresh is intentionally conservative:

- automatic refresh every 120 seconds by default
- 60-second minimum if overridden with `CODEX_USAGE_REFRESH_SECONDS`
- failed refreshes back off to 300 seconds
- no overlapping refreshes
- manual refresh from the menu
- 20-second timeout per app-server request

## Known limitations

- The default paths target `/Applications/ChatGPT.app` and `/Applications/Codex.app`; `CODEX_BIN` and lifecycle installer flags support custom locations.
- Usage depends on the local `account/rateLimits/read` app-server method, which may change in future Codex releases.
- Public release builds should be Developer ID signed and notarized.
- The menu-bar companion cannot draw inside the official Codex desktop window. That requires an upstream Codex desktop change.

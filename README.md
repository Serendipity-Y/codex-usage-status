# Codex Usage Status

An unofficial macOS menu-bar companion for viewing Codex usage at a glance. It adds a compact quota badge, a hover card with reset times and remaining reset opportunities, and an optional helper that keeps the badge open only while the ChatGPT desktop app is running.

This is a community project and is not affiliated with or endorsed by OpenAI.

The menu-bar badge shows the remaining 5-hour and weekly usage percentages. Hover over it to see the available reset count, 5-hour and weekly reset times, and the next data refresh. Click the badge to refresh, change the display style, open settings, or quit.

## Privacy and safety

- Usage comes from the local Codex app-server method `account/rateLimits/read`.
- The app does not read Codex credential files, browser cookies, sessions, OAuth credentials, or API keys.
- The optional lifecycle helper watches macOS's running-app list and matches the configured ChatGPT app bundle path. It does not inspect chat content or screenshots.
- This project does not upload usage data or send telemetry to its maintainers.
- It does not change usage limits or modify the ChatGPT or Codex app bundles.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md) for details. This app depends on a local app-server interface and app bundle paths that may change in future ChatGPT or Codex releases.

## Requirements

- macOS 13 or later
- ChatGPT desktop installed at `/Applications/ChatGPT.app` to use the automatic start/quit helper
- The Codex executable bundled with ChatGPT, or a standalone Codex app at `/Applications/Codex.app`
- Swift toolchain / Xcode Command Line Tools
- Node.js 20 or later for the CLI and JavaScript tests

If ChatGPT or Codex is installed at a different path, set `CODEX_BIN` when launching the app or pass paths to the lifecycle installer.

## Build and install

```sh
npm test
swift test --package-path macos/CodexUsageStatus
npm run build:macos
npm run install:macos
```

The app is menu-bar-only and does not appear in the Dock. To run it manually, open `CodexUsageStatus.app` from `/Applications`. On Apple Silicon the build script selects `arm64`; on Intel it selects `x86_64`. Override with `BUILD_ARCH=arm64` or `BUILD_ARCH=x86_64`.

Local builds are ad-hoc signed. The source repository does not promise signed or notarized release downloads; macOS may show a Gatekeeper warning for an app built or downloaded without Developer ID signing and notarization.

## Optional ChatGPT start/quit behavior

After building and installing the app in `/Applications`, install the per-user background listener:

```sh
python3 lifecycle/install.py install
python3 lifecycle/install.py check
```

By default it watches `/Applications/ChatGPT.app`, launches `/Applications/CodexUsageStatus.app` when ChatGPT starts, and quits the badge after the last ChatGPT process exits. Closing a ChatGPT window does not quit the app while its process remains running. The listener starts at user login, but the quota badge only starts when ChatGPT is running.

To use non-default locations:

```sh
python3 lifecycle/install.py install \
  --host-app "/Applications/ChatGPT.app" \
  --quota-app "/Applications/CodexUsageStatus.app" \
  --codex-bin "/path/to/codex"
```

Disable the listener with `python3 lifecycle/install.py disable`. This leaves the quota app installed so it can be started manually.

## CLI probe

The CLI uses the same local usage source and can help diagnose app-server responses:

```sh
CODEX_BIN="/path/to/codex" npm run usage
CODEX_BIN="/path/to/codex" npm run usage:json
```

## Package builds

```sh
npm run package:macos
npm run package:macos:all
```

The first command creates a ZIP for the current Mac architecture. The second creates architecture-specific Apple Silicon and Intel ZIPs plus `SHA256SUMS.txt` in `dist/`. These commands package the app; they do not publish a GitHub release.

## Upstream

This repository is derived from [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status). See [UPSTREAM.md](UPSTREAM.md) for the base revision and a summary of changes. The upstream MIT license and notice are retained.

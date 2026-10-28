# Codex Usage Status

An unofficial macOS menu-bar companion for viewing Codex usage at a glance. It adds a compact quota badge, a hover card with reset times and remaining reset opportunities, and an optional helper that keeps the badge open only while the ChatGPT desktop app is running.

This is a community project and is not affiliated with or endorsed by OpenAI.

Recent changes / 更新记录: [CHANGELOG.md](CHANGELOG.md).

The menu-bar badge shows the remaining 5-hour and weekly usage percentages. Hover over it to see the available reset count, 5-hour and weekly reset times, and the next data refresh. Click the badge to refresh, change the display style, open settings, or quit.

![Codex Usage Status menu-bar badge showing remaining 5-hour and weekly usage](docs/assets/menu-bar-badge.png)

![Codex Usage Status hover card with reset count, reset times, and next refresh](docs/assets/hover-card-sample.png)

*Illustrative preview with fictional sample values; it does not show a real account's quota.*

The reset count is the separate number of reset credits reported by Codex (`rateLimitResetCredits.availableCount`). It is not another usage percentage and may be unavailable if Codex does not return it.

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
- Swift toolchain / Xcode Command Line Tools and Python 3 to install the optional lifecycle helper
- Swift toolchain / Xcode Command Line Tools and Node.js 20 or later to build from source or run the JavaScript tests

If Codex is installed at a different path, set `CODEX_BIN` in the app's launch environment or pass `--codex-bin` to the lifecycle installer. The app checks the default ChatGPT and Codex locations when no override is set.

## Download a macOS app

Download the ZIP for Apple Silicon (`arm64`) or Intel (`x86_64`) from [GitHub Releases](https://github.com/Serendipity-Y/codex-usage-status/releases), unzip it, and move `CodexUsageStatus.app` to `/Applications`. Open the app to show its menu-bar badge. Optional checksum verification instructions are in the release notes.

The downloads are ad-hoc signed, without a Developer ID signature or Apple notarization. Gatekeeper may block a downloaded app. Building from source remains available using the steps below.

The download contains the menu-bar app only. The optional ChatGPT start/quit helper requires the source repository, Python 3, and Xcode Command Line Tools; see [Optional ChatGPT start/quit behavior](#optional-chatgpt-startquit-behavior).

## Quick start from source

Clone the repository and run the installer from its root:

```sh
git clone https://github.com/Serendipity-Y/codex-usage-status.git
cd codex-usage-status
npm run install:macos
```

The installer builds the app, quits any running `CodexUsageStatus` process, replaces `/Applications/CodexUsageStatus.app`, and opens the new app. To build without installing, use `npm run build:macos`.

## Development checks

```sh
npm test
swift test --package-path macos/CodexUsageStatus
npm run build:macos
```

The app is menu-bar-only and does not appear in the Dock. To run it manually, open `CodexUsageStatus.app` from `/Applications`. On Apple Silicon the build script selects `arm64`; on Intel it selects `x86_64`. Override with `BUILD_ARCH=arm64` or `BUILD_ARCH=x86_64`.

Local builds are ad-hoc signed. macOS may show a Gatekeeper warning for an app built or downloaded without Developer ID signing and notarization.

## Optional ChatGPT start/quit behavior

After installing the app in `/Applications`, obtain this source repository and install the per-user background listener from the repository root. This compiles the helper and requires Python 3 and Xcode Command Line Tools:

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

## Troubleshooting

- **Question marks after a refresh failure:** The card retains the last successful snapshot and shows the error category and last-success time. Automatic retries wait 60 seconds after the first failure, 120 after the second, and 300 thereafter. A successful read returns to the normal refresh interval. Click **Refresh** for a manual retry or **Settings...** for more detail.
- **Investigating recurring failures:** Read the local refresh diagnostics (fixed categories and retry timings; no raw account data):

  ```sh
  /usr/bin/log show --last 30m --style compact --predicate 'subsystem == "io.github.codexusagestatus" AND category == "refresh"'
  ```

- **No menu-bar badge:** The app is menu-bar-only and has no Dock icon. Check the menu-bar area, or open `CodexUsageStatus.app` from `/Applications` to start it again.
- **No usage data:** Confirm the configured Codex executable exists and can start `app-server`. The CLI probe can check the local response; set `CODEX_BIN` when using a non-default executable:

  ```sh
  CODEX_BIN="/path/to/codex" npm run usage:json
  ```

  The output contains your usage information, so review it before sharing publicly.
- **ChatGPT does not start or stop the badge:** Run `python3 lifecycle/install.py check` from the repository root and verify the saved app paths. Lifecycle logs are under `~/Library/Logs/CodexUsageStatusLifecycle/`; see [lifecycle instructions](lifecycle/README.md).

## Uninstall

If the lifecycle helper is enabled, disable it first:

```sh
python3 lifecycle/install.py disable
```

Then quit the badge from its menu and move `/Applications/CodexUsageStatus.app` to the Trash. Disabling the helper stops automatic start/quit behavior but preserves its LaunchAgent configuration, helper program, and logs. To remove those files too, delete:

- `~/Library/LaunchAgents/io.github.codexusagestatus.chatgpt-lifecycle.plist`
- `~/Library/Application Support/CodexUsageStatusLifecycle/`
- `~/Library/Logs/CodexUsageStatusLifecycle/` (optional; contains local diagnostic logs)

If you installed the app or ChatGPT in a custom location, remove the app from the location you selected.

## Upstream

This repository is derived from [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status). See [UPSTREAM.md](UPSTREAM.md) for the base revision and a summary of changes. The upstream MIT license and notice are retained.

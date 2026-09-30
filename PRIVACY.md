# Privacy

Codex Usage Status is intentionally narrow: it shows local Codex usage status in the macOS menu bar.

## What the app reads

The app reads only the structured usage response returned by the local Codex app-server method:

```json
{"method":"account/rateLimits/read","id":2}
```

Codex itself owns authentication. This companion app receives the usage percentages and reset times that Codex returns through that local interface.

## What the app does not read

- It does not read `~/.codex/auth.json`.
- It does not read browser cookies, browser storage, sessions, OAuth credentials, refresh tokens, API keys, or account passwords.
- It does not scrape Codex UI pages, browser pages, screenshots, or OCR output.
- It does not modify the official Codex app bundle.
- It does not bypass, increase, reset, purchase, or route around usage limits.

## Optional ChatGPT lifecycle helper

When installed, the helper observes macOS's running-application list and compares bundle paths to the configured ChatGPT and quota apps. It uses process identifiers only to distinguish multiple running instances and decide when to start or quit the quota app. It does not inspect windows, documents, or chat content. Lifecycle events and errors are written to local files under `~/Library/Logs/CodexUsageStatusLifecycle`; this project does not upload those logs.

## What leaves your Mac

This app does not upload usage data to this project, to the author, or to any third-party service.

The only network activity involved is whatever the official Codex app-server performs as part of Codex's own signed-in account flow. This project does not handle those credentials or proxy that traffic.

## Refresh behavior

The default refresh interval is 120 seconds. The minimum refresh interval is 60 seconds, and failed refreshes back off to 300 seconds.

Usage status does not need high-frequency polling, so the app keeps refreshes conservative.

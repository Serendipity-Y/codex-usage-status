# ChatGPT lifecycle helper

The optional macOS LaunchAgent watches the running-app list for a specific ChatGPT app bundle path. It starts the quota app when ChatGPT starts and asks it to quit after the last matching ChatGPT process exits. Closing a window leaves ChatGPT running, so the quota app stays visible. Multiple ChatGPT processes do not create duplicate quota apps.

The helper starts at user login, but the quota app only starts when ChatGPT is running. It does not inspect chat content or read authentication files. It records lifecycle events and errors locally under `~/Library/Logs/CodexUsageStatusLifecycle`.

## Install

First build and install `CodexUsageStatus.app` in `/Applications`, then run:

```sh
python3 lifecycle/install.py install
python3 lifecycle/install.py check
```

The defaults are `/Applications/ChatGPT.app` and `/Applications/CodexUsageStatus.app`. The installer finds ChatGPT's bundled Codex executable first and falls back to `/Applications/Codex.app`.

Custom paths can be supplied when installing:

```sh
python3 lifecycle/install.py install \
  --host-app "/path/to/ChatGPT.app" \
  --quota-app "/path/to/CodexUsageStatus.app" \
  --codex-bin "/path/to/codex"
```

The selected paths are stored in the per-user LaunchAgent. `check` reads that saved configuration. To stop and disable the LaunchAgent:

```sh
python3 lifecycle/install.py disable
```

Disabling the helper leaves the quota app available for manual use. It also preserves the LaunchAgent plist, helper program, and logs. Running `install` again enables it.

## Remove the helper completely

Run `disable` first so the LaunchAgent is stopped, then remove its configuration and helper files:

```sh
python3 lifecycle/install.py disable
rm -f "$HOME/Library/LaunchAgents/io.github.codexusagestatus.chatgpt-lifecycle.plist"
rm -rf "$HOME/Library/Application Support/CodexUsageStatusLifecycle"
```

The diagnostic logs are kept separately. To remove them as well:

```sh
rm -rf "$HOME/Library/Logs/CodexUsageStatusLifecycle"
```

This only removes the lifecycle helper. Quit and remove `CodexUsageStatus.app` separately if you no longer want the menu-bar app.

## Tests

```sh
python3 lifecycle/test_lifecycle.py
```

The integration test builds isolated fixture apps and exercises real macOS application-list changes. It does not terminate the user's ChatGPT app.

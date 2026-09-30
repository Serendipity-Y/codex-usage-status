#!/usr/bin/env python3
"""Install or disable the user-owned quota lifecycle listener."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
LABEL = "io.github.codexusagestatus.chatgpt-lifecycle"
SUPPORT = Path.home() / "Library/Application Support/CodexUsageStatusLifecycle"
PLIST = Path.home() / f"Library/LaunchAgents/{LABEL}.plist"
DOMAIN = f"gui/{os.getuid()}"


def run(*args, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True)


def unload():
    if run("launchctl", "print", f"{DOMAIN}/{LABEL}", check=False).returncode == 0:
        run("launchctl", "bootout", f"{DOMAIN}/{LABEL}")


def default_codex_path(host):
    candidates = [
        host / "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        Path("/Applications/Codex.app/Contents/Resources/codex"),
    ]
    return next((path for path in candidates if os.access(path, os.X_OK)), candidates[0])


def install(host_app=None, quota_app=None, codex_bin=None):
    host = Path(host_app or os.environ.get("CODEX_USAGE_HOST_APP", "/Applications/ChatGPT.app")).expanduser().resolve()
    quota = Path(quota_app or os.environ.get("CODEX_USAGE_QUOTA_APP", "/Applications/CodexUsageStatus.app")).expanduser().resolve()
    codex = Path(codex_bin or os.environ.get("CODEX_BIN") or default_codex_path(host)).expanduser().resolve()
    if not host.is_dir() or not quota.is_dir() or not os.access(codex, os.X_OK):
        raise RuntimeError("ChatGPT, quota app, or Codex executable missing")
    build = ROOT / "build/quota-lifecycle"
    build.parent.mkdir(parents=True, exist_ok=True)
    run("swiftc", "-O", "-framework", "AppKit", str(ROOT / "lifecycle/QuotaLifecycle.swift"), "-o", str(build))
    SUPPORT.mkdir(parents=True, exist_ok=True, mode=0o700)
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    logs = Path.home() / "Library/Logs/CodexUsageStatusLifecycle"
    logs.mkdir(parents=True, exist_ok=True, mode=0o700)
    unload()
    helper = SUPPORT / "quota-lifecycle"
    temporary_helper = SUPPORT / "quota-lifecycle.new"
    shutil.copy2(build, temporary_helper)
    temporary_helper.chmod(0o700)
    temporary_helper.replace(helper)
    config = {
        "Label": LABEL,
        "ProgramArguments": [str(helper), "--host-app", str(host), "--quota-app", str(quota), "--codex-bin", str(codex)],
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 10,
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": "Background",
        "StandardOutPath": str(logs / "events.log"),
        "StandardErrorPath": str(logs / "errors.log"),
    }
    temporary_plist = PLIST.with_suffix(".plist.new")
    with temporary_plist.open("wb") as stream:
        plistlib.dump(config, stream)
    temporary_plist.chmod(0o600)
    temporary_plist.replace(PLIST)
    run("plutil", "-lint", str(PLIST))
    run("launchctl", "enable", f"{DOMAIN}/{LABEL}")
    run("launchctl", "bootstrap", DOMAIN, str(PLIST))
    print(f"Enabled: {PLIST}")
    print(run(str(helper), "--host-app", str(host), "--quota-app", str(quota), "--codex-bin", str(codex), "--check").stdout.strip())


def check():
    if not PLIST.is_file():
        raise RuntimeError(f"Lifecycle agent is not installed: {PLIST}")
    with PLIST.open("rb") as stream:
        program_arguments = plistlib.load(stream).get("ProgramArguments", [])
    if not program_arguments:
        raise RuntimeError(f"Invalid lifecycle agent configuration: {PLIST}")
    helper = str(SUPPORT / "quota-lifecycle")
    if program_arguments[0] != helper:
        raise RuntimeError(f"Unexpected helper path in lifecycle configuration: {PLIST}")
    print(run(helper, *program_arguments[1:], "--check").stdout.strip())
    print(run("launchctl", "print", f"{DOMAIN}/{LABEL}").stdout)


def disable():
    unload()
    run("launchctl", "disable", f"{DOMAIN}/{LABEL}")
    print("Disabled. Quota app, helper and configuration files are preserved.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["install", "disable", "check"], default="install", nargs="?")
    parser.add_argument("--host-app", help="ChatGPT app bundle path (default: /Applications/ChatGPT.app)")
    parser.add_argument("--quota-app", help="quota app bundle path (default: /Applications/CodexUsageStatus.app)")
    parser.add_argument("--codex-bin", help="Codex executable path (defaults to ChatGPT's bundled Codex, then /Applications/Codex.app)")
    arguments = parser.parse_args()
    try:
        if arguments.action == "install":
            install(arguments.host_app, arguments.quota_app, arguments.codex_bin)
        elif arguments.action == "disable":
            disable()
        else:
            check()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        sys.exit(1)

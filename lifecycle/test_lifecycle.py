#!/usr/bin/env python3
"""Exercise actual macOS lifecycle events with isolated, invisible fixture apps."""
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = r'''
import AppKit
import Foundation
let eventPath = Bundle.main.bundleURL.appendingPathComponent("events.jsonl").path
func record(_ event: String) {
    let row: [String: Any] = ["event": event, "pid": Int(ProcessInfo.processInfo.processIdentifier), "codex": ProcessInfo.processInfo.environment["CODEX_BIN"] ?? ""]
    let data = try! JSONSerialization.data(withJSONObject: row)
    if !FileManager.default.fileExists(atPath: eventPath) { FileManager.default.createFile(atPath: eventPath, contents: nil) }
    let file = FileHandle(forWritingAtPath: eventPath)!
    file.seekToEndOfFile(); file.write(data); file.write(Data("\n".utf8)); file.closeFile()
}
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { record("started") }
    func applicationWillTerminate(_ notification: Notification) { record("quit") }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()
'''


class LifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="quota-lifecycle-test-")
        cls.base = Path(cls.temp.name)
        cls.source = cls.base / "fixture.swift"
        cls.source.write_text(FIXTURE)
        cls.binary = cls.base / "Fixture"
        subprocess.run(["swiftc", "-framework", "AppKit", str(cls.source), "-o", str(cls.binary)], check=True)
        cls.helper = cls.base / "quota-lifecycle"
        subprocess.run(["swiftc", "-O", "-framework", "AppKit", str(ROOT / "lifecycle/QuotaLifecycle.swift"), "-o", str(cls.helper)], check=True)
        cls.host = cls.make_app("Host")
        cls.quota = cls.make_app("Quota")
        cls.other = cls.make_app("Other")
        cls.args = [str(cls.helper), "--host-app", str(cls.host), "--quota-app", str(cls.quota), "--codex-bin", "/usr/bin/true"]

    @classmethod
    def make_app(cls, name):
        app = cls.base / f"{name}.app"
        macos = app / "Contents/MacOS"
        macos.mkdir(parents=True)
        (macos / name).write_bytes(cls.binary.read_bytes())
        (macos / name).chmod(0o700)
        with (app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": f"dev.local.QuotaLifecycleTest.{name}.{uuid.uuid4().hex}", "CFBundleExecutable": name,
                          "CFBundleName": name, "CFBundlePackageType": "APPL", "LSUIElement": True}, stream)
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        return app

    def state(self):
        return json.loads(subprocess.check_output(self.args + ["--check"], text=True))

    def await_state(self, predicate, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self.state()
            if predicate(state):
                return state
            time.sleep(0.15)
        self.fail(f"Timed out: {self.state()}\n{(self.base / 'listener.log').read_text()}")

    def launch(self, app):
        subprocess.run(["open", "-n", "-g", str(app)], check=True)

    @staticmethod
    def stop(pids):
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def start_listener(self):
        self.log = (self.base / "listener.log").open("w")
        self.listener = subprocess.Popen(self.args, stdout=self.log, stderr=self.log)
        deadline = time.monotonic() + 5
        while "listener started" not in (self.base / "listener.log").read_text():
            if time.monotonic() > deadline:
                self.fail("Listener did not start")
            time.sleep(0.1)

    def tearDown(self):
        if hasattr(self, "listener"):
            self.listener.terminate()
            self.listener.wait(timeout=5)
            self.log.close()
        state = self.state()
        self.stop(state["hostPIDs"] + state["quotaPIDs"])
        # Only processes launched from our unique fixture bundles are cleaned up.
        result = subprocess.run(["pgrep", "-f", str(self.other / "Contents/MacOS/Other")], text=True, capture_output=True)
        self.stop([int(pid) for pid in result.stdout.split()])
        self.await_state(lambda s: not s["hostPIDs"] and not s["quotaPIDs"])

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_launch_exit_and_relaunch(self):
        self.start_listener()
        self.assertFalse(self.state()["quotaPIDs"])
        self.launch(self.other)
        time.sleep(0.5)
        self.assertFalse(self.state()["quotaPIDs"], "Unrelated app must not start quota")
        self.launch(self.host)
        first = self.await_state(lambda s: len(s["hostPIDs"]) == 1 and len(s["quotaPIDs"]) == 1)
        # A second host instance must not create a second quota instance.
        self.launch(self.host)
        second = self.await_state(lambda s: len(s["hostPIDs"]) == 2)
        time.sleep(0.5)
        self.assertEqual(self.state()["quotaPIDs"], first["quotaPIDs"])
        self.stop([second["hostPIDs"][0]])
        self.await_state(lambda s: len(s["hostPIDs"]) == 1)
        time.sleep(0.5)
        self.assertEqual(self.state()["quotaPIDs"], first["quotaPIDs"], "One remaining host keeps quota alive")
        self.stop(self.state()["hostPIDs"])
        self.await_state(lambda s: not s["hostPIDs"] and not s["quotaPIDs"])
        rows = [json.loads(line) for line in (self.quota / "events.jsonl").read_text().splitlines()]
        self.assertTrue(any(r["event"] == "quit" for r in rows), "Quota should receive graceful quit")
        self.assertTrue(any(r["codex"] == "/usr/bin/true" for r in rows), "CODEX_BIN must be passed")
        self.launch(self.host)
        self.await_state(lambda s: len(s["quotaPIDs"]) == 1)

    def test_startup_sync_and_manual_quit(self):
        self.launch(self.host)
        self.await_state(lambda s: len(s["hostPIDs"]) == 1)
        self.start_listener()
        initial = self.await_state(lambda s: len(s["quotaPIDs"]) == 1)
        self.stop(initial["quotaPIDs"])
        self.await_state(lambda s: not s["quotaPIDs"])
        time.sleep(0.8)
        self.assertFalse(self.state()["quotaPIDs"], "Manual quit must not be immediately undone")

    def test_quota_cannot_outlive_absent_host(self):
        self.launch(self.quota)
        self.await_state(lambda s: len(s["quotaPIDs"]) == 1)
        self.start_listener()
        self.await_state(lambda s: not s["quotaPIDs"])
        self.launch(self.quota)
        self.await_state(lambda s: not s["quotaPIDs"])
        time.sleep(0.5)
        self.assertFalse(self.state()["quotaPIDs"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

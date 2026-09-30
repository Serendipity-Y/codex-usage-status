import AppKit
import Foundation

struct Configuration {
    let host: URL
    let quota: URL
    let codex: String
    let checkOnly: Bool

    init() throws {
        var options: [String: String] = [:]
        var args = Array(CommandLine.arguments.dropFirst())
        checkOnly = args.contains("--check")
        args.removeAll { $0 == "--check" }
        while !args.isEmpty {
            let key = args.removeFirst()
            guard ["--host-app", "--quota-app", "--codex-bin"].contains(key), !args.isEmpty else {
                throw NSError(domain: "QuotaLifecycle", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"])
            }
            options[key] = args.removeFirst()
        }
        host = URL(fileURLWithPath: options["--host-app"] ?? "/Applications/ChatGPT.app").resolvingSymlinksInPath()
        quota = URL(fileURLWithPath: options["--quota-app"] ?? "/Applications/CodexUsageStatus.app").resolvingSymlinksInPath()
        codex = options["--codex-bin"] ?? "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        guard host != quota else {
            throw NSError(domain: "QuotaLifecycle", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Host and quota app must differ"])
        }
    }
}

func applications(at url: URL) -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
        !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath() == url
    }
}

func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    FileHandle.standardOutput.write(Data(line.utf8))
}

final class Lifecycle {
    let configuration: Configuration
    private var observation: NSKeyValueObservation?
    private var pending: DispatchWorkItem?
    private var launching = false
    private var lastHostPIDs: Set<pid_t>?

    init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func start() {
        // Launch notifications exclude LSUIElement/background apps; KVO covers all apps.
        observation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.reconcile() }
                self.pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            }
        }
        log("listener started")
        reconcile()
    }

    private func reconcile() {
        let hosts = Set(applications(at: configuration.host).map { $0.processIdentifier })
        if hosts.isEmpty {
            if lastHostPIDs != hosts { log("host stopped") }
            lastHostPIDs = hosts
            stopQuota()
            return
        }
        // Quota/manual quits and unrelated apps do not restart the quota app.
        guard lastHostPIDs != hosts else { return }
        lastHostPIDs = hosts
        log("host running")
        guard applications(at: configuration.quota).isEmpty, !launching else {
            log("quota already running or starting")
            return
        }
        guard FileManager.default.fileExists(atPath: configuration.quota.path),
              FileManager.default.isExecutableFile(atPath: configuration.codex) else {
            log("quota app or Codex executable missing")
            return
        }
        launching = true
        let options = NSWorkspace.OpenConfiguration()
        options.activates = false
        options.createsNewApplicationInstance = false
        options.environment = ["CODEX_BIN": configuration.codex]
        NSWorkspace.shared.openApplication(at: configuration.quota, configuration: options) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.launching = false
                if let error {
                    log("quota launch failed: \(error.localizedDescription)")
                    return
                }
                log("quota started pid=\(app?.processIdentifier ?? 0)")
                // A host exit can arrive while LaunchServices is opening the app.
                if applications(at: self.configuration.host).isEmpty { self.stopQuota() }
            }
        }
    }

    private func stopQuota() {
        for app in applications(at: configuration.quota) {
            log("quota quit requested pid=\(app.processIdentifier) accepted=\(app.terminate())")
        }
    }
}

do {
    let config = try Configuration()
    if config.checkOnly {
        let state: [String: Any] = [
            "hostPIDs": applications(at: config.host).map { Int($0.processIdentifier) },
            "quotaPIDs": applications(at: config.quota).map { Int($0.processIdentifier) },
            "codexExecutableExists": FileManager.default.isExecutableFile(atPath: config.codex)
        ]
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let lifecycle = Lifecycle(config)
        lifecycle.start()
        withExtendedLifetime(lifecycle) { app.run() }
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}

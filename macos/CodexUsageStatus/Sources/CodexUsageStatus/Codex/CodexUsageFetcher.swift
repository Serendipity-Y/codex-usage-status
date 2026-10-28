import Darwin
import Foundation

enum CodexUsageFetcher {
    static func fetch() async throws -> UsageSummary {
        try await Task.detached(priority: .utility) {
            try fetchSync()
        }.value
    }

    static func fetchSync(codexPath: String? = nil,
                          timeout: DispatchTimeInterval = AppConfig.appServerTimeout) throws -> UsageSummary {
        let path = codexPath ?? ProcessInfo.processInfo.environment["CODEX_BIN"] ?? AppConfig.defaultCodexPath
        return try UsageSummary(response: readRateLimits(codexPath: path, timeout: timeout))
    }

    private static func readRateLimits(codexPath: String, timeout: DispatchTimeInterval) throws -> RateLimitsResponse {
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            throw FetchError.codexNotFound(codexPath)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        // An early server exit must produce a write error, not terminate the app with SIGPIPE.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw FetchError.connectionClosed
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        let responses = ResponseBox()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                responses.finish()
            } else {
                responses.append(data)
            }
        }
        // Drain stderr while the server runs: a full pipe can block its RPC response.
        // Do not retain server logs, which may contain account-related information.
        errors.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            terminateProcess(process, finished: finished)
        }
        try process.run()
        let deadline = DispatchTime.now() + timeout
        func send(_ line: String) throws {
            do {
                try input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
            } catch {
                throw FetchError.connectionClosed
            }
        }
        try send(#"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_usage_status_menubar","title":"Codex Usage Status","version":"0.1.1"},"capabilities":{"experimentalApi":true}}}"#)
        _ = try responses.wait(for: "1", until: deadline)
        try send(#"{"method":"initialized"}"#)
        try send(#"{"method":"account/rateLimits/read","id":2}"#)
        let result = try responses.wait(for: "2", until: deadline)
        do {
            return try JSONDecoder().decode(RateLimitsResponse.self, from: result)
        } catch {
            throw FetchError.invalidOutput
        }
    }

    private static func terminateProcess(_ process: Process, finished: DispatchSemaphore) {
        guard process.isRunning else { return }
        process.terminate()
        if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1)
        }
    }
}

final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var results: [String: Result<Data, Error>] = [:]
    private var ended = false

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        // Decode complete lines only; a pipe chunk can split a UTF-8 character.
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            consume(Data(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        if !buffer.isEmpty { consume(buffer); buffer.removeAll() }
        ended = true
        semaphore.signal()
    }

    func wait(for id: String, until deadline: DispatchTime) throws -> Data {
        while true {
            lock.lock()
            let result = results.removeValue(forKey: id)
            let closed = ended
            lock.unlock()
            if let result { return try result.get() }
            if closed { throw FetchError.missingRateLimitResponse }
            if semaphore.wait(timeout: deadline) == .timedOut { throw FetchError.timeout }
        }
    }

    private func consume(_ line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let id = (object["id"] as? String) ?? (object["id"] as? NSNumber)?.stringValue,
              id == "1" || id == "2" else { return }
        if let error = object["error"] as? [String: Any] {
            results[id] = .failure(FetchError.serverError(error))
        } else if let result = object["result"], JSONSerialization.isValidJSONObject(result),
                  let data = try? JSONSerialization.data(withJSONObject: result) {
            results[id] = .success(data)
        } else {
            results[id] = .failure(FetchError.invalidOutput)
        }
        semaphore.signal()
    }
}

enum FetchError: LocalizedError, Equatable {
    case codexNotFound(String)
    case timeout
    case connectionClosed
    case notInitialized
    case authenticationRequired
    case rateLimited
    case appServerError(Int?)
    case invalidOutput
    case missingRateLimitResponse

    static func serverError(_ object: [String: Any]) -> FetchError {
        // Classify known messages, but never retain or display raw server payloads.
        let message = (object["message"] as? String ?? "").lowercased()
        let code = object["code"] as? Int
        if message.contains("not initialized") { return .notInitialized }
        if code == 401 || message.contains("unauthorized") || message.contains("not logged in") || message.contains("authentication required") {
            return .authenticationRequired
        }
        if code == 429 || message.contains("too many requests") { return .rateLimited }
        return .appServerError(code)
    }

    var briefDescription: String {
        switch self {
        case .codexNotFound: return "未找到 Codex"
        case .timeout: return "读取超时"
        case .connectionClosed, .missingRateLimitResponse: return "读取进程已断开"
        case .notInitialized: return "初始化未完成"
        case .authenticationRequired: return "请检查 Codex 登录"
        case .rateLimited: return "服务暂时限流"
        case .appServerError: return "额度服务返回错误"
        case .invalidOutput: return "额度数据格式异常"
        }
    }

    var errorDescription: String? {
        switch self {
        case .codexNotFound(let path): return "Codex binary not found at \(path)"
        case .timeout: return "Codex app-server did not respond within 20 seconds"
        case .connectionClosed: return "Codex app-server connection closed while sending a request"
        case .notInitialized: return "Codex app-server initialization was not complete"
        case .authenticationRequired: return "Codex app-server requires sign-in; check your Codex account"
        case .rateLimited: return "Codex app-server is temporarily rate limited"
        case .appServerError(let code): return "Codex app-server returned an error (code: \(code.map(String.init) ?? "unknown"))"
        case .invalidOutput: return "Codex app-server returned unexpected usage data"
        case .missingRateLimitResponse: return "Codex app-server closed its output before responding"
        }
    }
}

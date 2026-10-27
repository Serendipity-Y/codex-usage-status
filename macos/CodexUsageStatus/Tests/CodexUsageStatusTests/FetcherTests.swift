import Foundation
import Testing
@testable import CodexUsageStatus

private let quotaReply = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300},"secondary":{"usedPercent":40,"windowDurationMins":10080}}}}"#

private func withServer(_ body: String, run: (String) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = directory.appendingPathComponent("codex")
    try ("#!/bin/bash\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    try run(script.path)
}

@Test func waitsForInitializationBeforeRequestingQuota() throws {
    try withServer("""
    IFS= read -r initialize
    if IFS= read -r -t 1 premature; then
      echo '{"id":2,"error":{"code":-32002,"message":"Not initialized"}}'
      exit 0
    fi
    echo '{"id":1,"result":{}}'
    IFS= read -r initialized
    IFS= read -r request
    echo '\(quotaReply)'
    """) { path in
        let usage = try CodexUsageFetcher.fetchSync(codexPath: path, timeout: .seconds(4))
        #expect(usage.fiveHour.remainingPercent == 75)
        #expect(usage.weekly.remainingPercent == 60)
    }
}

@Test func drainsStderrBeforeWaitingForQuota() throws {
    try withServer("""
    IFS= read -r initialize
    echo '{"id":1,"result":{}}'
    IFS= read -r initialized
    IFS= read -r request
    head -c 262144 /dev/zero >&2
    echo '\(quotaReply)'
    """) { path in
        let usage = try CodexUsageFetcher.fetchSync(codexPath: path, timeout: .seconds(4))
        #expect(usage.weekly.remainingPercent == 60)
    }
}

@Test func initializationErrorsArePromptAndDoNotExposeServerText() throws {
    try withServer("""
    IFS= read -r initialize
    echo '{"id":1,"error":{"code":401,"message":"Unauthorized: token=private-test-value"}}'
    """) { path in
        do {
            _ = try CodexUsageFetcher.fetchSync(codexPath: path, timeout: .seconds(2))
            Issue.record("Expected initialization failure")
        } catch {
            #expect(error as? FetchError == .authenticationRequired)
            #expect(!error.localizedDescription.contains("private-test-value"))
        }
    }
}

@Test func exitedServerDoesNotWaitForTimeout() throws {
    try withServer("exit 7") { path in
        let start = Date()
        do {
            _ = try CodexUsageFetcher.fetchSync(codexPath: path, timeout: .seconds(4))
            Issue.record("Expected closed connection")
        } catch {
            #expect(error as? FetchError == .missingRateLimitResponse || error as? FetchError == .connectionClosed)
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }
}

@Test func silentServerHasBoundedTimeoutAndCleanup() throws {
    try withServer("exec /bin/sleep 10") { path in
        let start = Date()
        do {
            _ = try CodexUsageFetcher.fetchSync(codexPath: path, timeout: .milliseconds(100))
            Issue.record("Expected timeout")
        } catch {
            #expect(error as? FetchError == .timeout)
        }
        #expect(Date().timeIntervalSince(start) < 3)
    }
}

@Test func pipeChunksCanSplitUTF8AndIgnoreUnrelatedOutput() throws {
    let data = Data((#"{"id":2,"result":{"note":"额度","rateLimits":{}}}"# + "\n").utf8)
    for split in 1..<data.count {
        let box = ResponseBox()
        box.append(Data("a diagnostic line\n{\"method\":\"notification\"}\n".utf8))
        box.append(Data(data.prefix(split)))
        box.append(Data(data.dropFirst(split)))
        let decoded = try JSONSerialization.jsonObject(with: box.wait(for: "2", until: .now() + 1)) as? [String: Any]
        #expect(decoded?["note"] as? String == "额度")
    }
}

@Test func finalResponseIsKeptWhenServerExitsWithoutNewline() throws {
    let box = ResponseBox()
    box.append(Data(quotaReply.utf8))
    box.finish()
    let decoded = try JSONDecoder().decode(RateLimitsResponse.self, from: box.wait(for: "2", until: .now() + 1))
    #expect(try UsageSummary(response: decoded).weekly.remainingPercent == 60)
}

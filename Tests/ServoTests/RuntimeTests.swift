import Foundation
import Darwin
import Testing
@testable import Servo

@Suite("Per-site runtimes")
struct RuntimeTests {
    @Test func oldSettingsAndSelectionsRoundTrip() throws {
        let old = Data(#"{"rootPath":"/tmp/sites","ports":{"/tmp/sites/work":8000}}"#.utf8)
        var settings = try JSONDecoder().decode(ServoSettings.self, from: old)
        #expect(settings.ports["/tmp/sites/work"] == 8000)
        #expect(settings.siteRuntimes == nil)
        let work = SiteRuntimeSelection(php: .init(path: "/php84/bin/php", version: "PHP 8.4"))
        let next = SiteRuntimeSelection(php: .init(path: "/php85/bin/php", version: "PHP 8.5"),
                                       node: .init(path: "/node24/bin/node", version: "v24"))
        settings.siteRuntimes = ["/tmp/sites/work": work, "/tmp/sites/new": next]
        let restored = try JSONDecoder().decode(ServoSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.siteRuntimes?["/tmp/sites/work"] == work)
        #expect(restored.siteRuntimes?["/tmp/sites/new"] == next)
        #expect(restored.ports == settings.ports)
    }

    @Test func missingPinnedRuntimeNeverFallsBack() throws {
        let selection = SiteRuntimeSelection(php: RuntimePin(path: "/missing/\(UUID())/php", version: "PHP 8.4"))
        #expect(throws: CommandError.self) { try selection.phpExecutable() }
        #expect(throws: CommandError.self) { try selection.environment() }
    }

    @Test func pinSurvivesGlobalSymlinkChangeAndIsolatesChildren() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func fake(_ folder: String, _ executable: String, _ version: String) throws -> URL {
            let bin = root.appendingPathComponent("\(folder)/bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let file = bin.appendingPathComponent(executable)
            try "#!/bin/sh\nprintf '%s\\n' '\(version)'\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            return file
        }
        let php84 = try fake("php84", "php", "8.4")
        let php85 = try fake("php85", "php", "8.5")
        let node22 = try fake("node22", "node", "22")
        let node24 = try fake("node24", "node", "24")
        let link = root.appendingPathComponent("current-php")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: php84)
        let work = SiteRuntimeSelection(php: RuntimePin(RuntimeInfo(kind: .php, path: link.path, version: "PHP 8.4")),
                                       node: RuntimePin(path: node22.path, version: "22"))
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: php85)
        let next = SiteRuntimeSelection(php: RuntimePin(path: php85.path, version: "8.5"),
                                       node: RuntimePin(path: node24.path, version: "24"))
        #expect(try work.phpExecutable().path == php84.resolvingSymlinksInPath().path)
        for (selection, expected) in [(work, "8.4\n22\n"), (next, "8.5\n24\n")] {
            let output = try await CommandRunner.checked(URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "php; node"], environment: selection.environment())
            #expect(output == expected)
        }
    }

    @MainActor @Test func terminalQuotesPathsWithoutExecutingContent() async throws {
        let path = "/tmp/it's a site $(printf BAD);`printf BAD`"
        let output = try await CommandRunner.checked(URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '%s' " + AppModel.shellQuote(path)])
        #expect(output == path)
    }
}

@Suite("Installed PHP integration")
struct InstalledPHPTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["SERVO_RUNTIME_SMOKE"] == "1"))
    func twoSitesServeDifferentPHPVersions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "<?php echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;".write(
            to: root.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        let server = SiteServer()
        let runtimes = await RuntimeService.scan()
        let php84 = try #require(runtimes.first { $0.kind == .php && $0.version.hasPrefix("PHP 8.4.") })
        let php85 = try #require(runtimes.first { $0.kind == .php && $0.version.hasPrefix("PHP 8.5.") })
        var running: [(Process, Pipe)] = []
        defer {
            for (process, pipe) in running {
                pipe.fileHandleForReading.readabilityHandler = nil
                if process.isRunning { process.terminate(); process.waitUntilExit() }
            }
        }
        var endpoints: [(URL, String)] = []
        for (runtime, expected) in [(php84, "8.4"), (php85, "8.5")] {
            let port = try unusedPort()
            let selection = SiteRuntimeSelection(php: RuntimePin(runtime))
            let site = Site(path: root.path, port: port, runtimeSelection: selection)
            let (process, pipe) = try server.configuredProcess(site: site,
                php: selection.phpExecutable(), host: "127.0.0.1", port: port,
                label: expected, behindHTTPSProxy: false)
            try process.run()
            running.append((process, pipe))
            endpoints.append((URL(string: "http://127.0.0.1:\(port)/")!, expected))
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for (url, expected) in endpoints {
            var body: String?
            for _ in 0..<30 {
                if let (data, _) = try? await session.data(from: url) {
                    body = String(data: data, encoding: .utf8)
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(body == expected)
        }
    }

    private func unusedPort() throws -> Int {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw CommandError.unavailable("Test socket") }
        defer { Darwin.close(socket) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let status = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard status == 0 else { throw CommandError.unavailable("Test port") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
        }
        guard result == 0 else { throw CommandError.unavailable("Test port") }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

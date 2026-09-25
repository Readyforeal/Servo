import Foundation
import CryptoKit

/// User-owned virtual hosts behind a fixed, root-owned loopback-only port-80 relay.
@MainActor final class LocalDomains {
    static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Servo")
    static let helper = "/Library/PrivilegedHelperTools/com.servo.local-domains"
    private var process: Process?
    private var logHandle: FileHandle?
    private var configuration: Data?
    private(set) var ready = false
    private(set) var routedHosts: [String: String] = [:]
    var onChange: (() -> Void)?

    static func hosts(for sites: [Site]) -> [String: String] {
        let slugs = sites.map { site in
            site.name.lowercased().unicodeScalars.map { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) ? String($0) : "-" }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return Dictionary(uniqueKeysWithValues: zip(sites, slugs).map { site, slug in
            let duplicate = slugs.filter { $0 == slug }.count > 1
            let suffix = SHA256.hash(data: Data(site.path.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
            let label = slug.isEmpty ? "site-" + suffix : String(slug.prefix(45)) + (duplicate || slug.count > 45 || slug != site.name.lowercased() ? "-" + suffix : "")
            return (site.path, label + ".test")
        })
    }
    static func validHost(_ host: String) -> Bool {
        host.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.test$"#, options: .regularExpression) != nil
    }
    static func hostsBlock(_ hosts: [String]) -> String {
        "# BEGIN SERVO LOCAL DOMAINS\n" + hosts.sorted().map { "127.0.0.1 \($0)" }.joined(separator: "\n") + "\n# END SERVO LOCAL DOMAINS\n"
    }
    static func configured(_ hosts: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: helper + "/caddy"),
              let text = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else { return false }
        return hosts.allSatisfy { host in
            text.components(separatedBy: .newlines).contains { line in
                let fields = line.components(separatedBy: "#")[0].split(whereSeparator: { $0.isWhitespace })
                return fields.first == "127.0.0.1" && fields.dropFirst().contains(Substring(host))
            }
        }
    }
    func enable(_ sites: [Site]) async throws {
        let hosts = Array(Self.hosts(for: sites).values)
        guard !hosts.isEmpty, hosts.allSatisfy(Self.validHost) else { throw CommandError.failed("Local domains", 1, "Add a site before enabling .test addresses.") }
        guard let caddy = CommandRunner.executable(named: "caddy"),
              let installer = Bundle.main.resourceURL?.appendingPathComponent("setup-local-domains.sh"), FileManager.default.fileExists(atPath: installer.path) else { throw CommandError.unavailable("Local domain installer / Caddy") }
        let command = (["/bin/sh", installer.path, caddy.path] + hosts).map(AppModel.shellQuote).joined(separator: " ")
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        _ = try await CommandRunner.checked(URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", "do shell script \"\(quoted)\" with administrator privileges"])
    }
    static func config(sites: [Site], socket: String) throws -> Data {
        let hosts = hosts(for: sites)
        let routes: [[String: Any]] = sites.map { site in
            ["match": [["host": [hosts[site.path]!]]], "handle": [
                ["handler": "subroute", "routes": [["match": [["path": ["/.well-known/servo-routing-health"]]], "handle": [["handler": "static_response", "status_code": 200, "headers": ["X-Servo-Router": ["1"]], "body": "Servo"]]]]],
                ["handler": "headers", "response": ["set": ["X-Servo-Router": ["1"]]]],
                ["handler": "reverse_proxy", "upstreams": [["dial": "127.0.0.1:\(site.port)"]]]], "terminal": true]
        }
        let fallback: [String: Any] = ["handle": [["handler": "static_response", "status_code": 404]]]
        let server: [String: Any] = ["listen": ["127.0.0.1:17880"], "automatic_https": ["disable": true], "routes": routes + [fallback]]
        let object: [String: Any] = ["admin": ["listen": "unix/" + socket], "apps": ["http": ["servers": ["local": server]]]]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    func start(_ sites: [Site]) async throws {
        guard let caddy = CommandRunner.executable(named: "caddy") else { throw CommandError.unavailable("Caddy") }
        try FileManager.default.createDirectory(at: Self.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let socket = Self.support.appendingPathComponent("domains.sock").path
        let file = Self.support.appendingPathComponent("domains.json")
        let data = try Self.config(sites: sites, socket: socket)
        if process?.isRunning == true && configuration == data && ready { return }
        try data.write(to: file, options: .atomic)
        if process?.isRunning != true {
            let task = Process(); task.executableURL = caddy; task.arguments = ["run", "--config", file.path]
            let log = Self.support.appendingPathComponent("domains.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            logHandle = try FileHandle(forWritingTo: log)
            task.standardOutput = logHandle; task.standardError = logHandle
            task.terminationHandler = { [weak self] task in Task { @MainActor in
                guard self?.process === task else { return }
                self?.ready = false; self?.onChange?()
            } }
            try task.run(); process = task
        }
        var loaded = false
        for _ in 0..<20 {
            let result = try await CommandRunner.run(caddy, arguments: ["reload", "--config", file.path, "--address", "unix/" + socket])
            if result.status == 0 { loaded = true; break }
            if process?.isRunning != true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard loaded else { throw CommandError.failed("Local domains", 1, "Could not start the local router. Check Servo/domains.log; port 17880 may already be in use.") }
        // Confirm the privileged relay reaches this router before advertising URLs.
        var request = URLRequest(url: URL(string: "http://127.0.0.1/.well-known/servo-routing-health")!, cachePolicy: .reloadIgnoringLocalCacheData); request.timeoutInterval = 3
        request.setValue(Self.hosts(for: sites).values.sorted().first, forHTTPHeaderField: "Host")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Servo-Router") == "1" else {
            throw CommandError.failed("Local domains", 1, "The port-80 relay is unavailable. Enable .test Addresses again; another server may be using port 80.")
        }
        configuration = data; routedHosts = Self.hosts(for: sites); ready = true; onChange?()
    }
    func stop() {
        ready = false; process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; try? logHandle?.close(); logHandle = nil; onChange?()
    }
}

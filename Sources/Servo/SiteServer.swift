import AppKit
import Darwin
import Foundation

@MainActor
final class SiteServer {
    struct RunningSite {
        let process: Process
        let pipe: Pipe
    }

    private(set) var running: [String: RunningSite] = [:]
    private(set) var sharedServers: [String: RunningSite] = [:]
    private(set) var httpsProxies: [String: RunningSite] = [:]
    private(set) var httpsHosts: [String: String] = [:]
    private(set) var tunnels: [String: Process] = [:]
    private(set) var publicURLs: [String: String] = [:]
    var onChange: (() -> Void)?
    var onLog: ((String) -> Void)?

    func start(_ site: Site) throws {
        stopLocal(site)
        guard let php = CommandRunner.executable(named: "php") else { throw CommandError.unavailable("PHP") }
        let (process, pipe) = try configuredProcess(
            site: site,
            php: php,
            host: "127.0.0.1",
            port: site.port,
            label: site.name,
            behindHTTPSProxy: true
        )
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.running.removeValue(forKey: site.id)
                self?.onChange?()
            }
        }
        try process.run()
        running[site.id] = RunningSite(process: process, pipe: pipe)
        onLog?("[\(site.name)] Started on 127.0.0.1:\(site.port)")
        onChange?()
    }

    func stop(_ site: Site) {
        stopExpose(site)
        stopHTTPS(site)
        stopSharing(site)
        stopLocal(site)
        onLog?("[\(site.name)] Stopped")
        onChange?()
    }

    func isRunning(_ site: Site) -> Bool { running[site.id] != nil }
    func isShared(_ site: Site) -> Bool { sharedServers[site.id] != nil }
    func sharedPort(for site: Site) -> Int { site.port + 10_000 }
    func httpsPort(for site: Site) -> Int { site.port + 20_000 }

    func startHTTPS(_ site: Site, host: String) throws {
        guard httpsProxies[site.id] == nil, isRunning(site) else { return }
        guard let caddy = CommandRunner.executable(named: "caddy") else { throw CommandError.unavailable("Caddy HTTPS") }
        let process = Process()
        let pipe = Pipe()
        let port = httpsPort(for: site)
        process.executableURL = caddy
        process.arguments = [
            "reverse-proxy",
            "--from", "https://\(host):\(port)",
            "--to", "http://127.0.0.1:\(site.port)",
            "--internal-certs",
            "--disable-redirects",
            "--header-up", "X-Forwarded-Proto: https"
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        attachLogging(to: pipe, label: "\(site.name) · HTTPS")
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.httpsProxies.removeValue(forKey: site.id)
                self?.httpsHosts.removeValue(forKey: site.id)
                if process.terminationStatus != 0 {
                    self?.onLog?("[\(site.name) · HTTPS] Proxy stopped with status \(process.terminationStatus)")
                }
                self?.onChange?()
            }
        }
        try process.run()
        httpsProxies[site.id] = RunningSite(process: process, pipe: pipe)
        httpsHosts[site.id] = host
        onLog?("[\(site.name)] HTTPS starting at https://\(host):\(port)")
        onChange?()
    }

    func stopHTTPS(_ site: Site) {
        guard let entry = httpsProxies.removeValue(forKey: site.id) else { return }
        httpsHosts.removeValue(forKey: site.id)
        terminate(entry)
        onLog?("[\(site.name)] HTTPS stopped")
        onChange?()
    }

    func isHTTPS(_ site: Site) -> Bool { httpsProxies[site.id] != nil }
    func httpsURL(for site: Site) -> String? {
        guard let host = httpsHosts[site.id] else { return nil }
        return "https://\(host):\(httpsPort(for: site))"
    }

    func startSharing(_ site: Site) throws {
        guard sharedServers[site.id] == nil, isRunning(site) else { return }
        guard let php = CommandRunner.executable(named: "php") else { throw CommandError.unavailable("PHP") }
        let port = sharedPort(for: site)
        let (process, pipe) = try configuredProcess(
            site: site,
            php: php,
            host: "0.0.0.0",
            port: port,
            label: "\(site.name) · Share",
            behindHTTPSProxy: false
        )
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.sharedServers.removeValue(forKey: site.id)
                self?.onChange?()
            }
        }
        try process.run()
        sharedServers[site.id] = RunningSite(process: process, pipe: pipe)
        onLog?("[\(site.name)] Shared on 0.0.0.0:\(port)")
        onChange?()
    }

    func stopSharing(_ site: Site) {
        guard let entry = sharedServers.removeValue(forKey: site.id) else { return }
        terminate(entry)
        onLog?("[\(site.name)] Local-network sharing stopped")
        onChange?()
    }

    func expose(_ site: Site) throws {
        if tunnels[site.id] != nil { stopExpose(site); return }
        guard isRunning(site) else { return }
        guard let cloudflared = CommandRunner.executable(named: "cloudflared") else { throw CommandError.unavailable("Cloudflare Tunnel") }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = cloudflared
        process.arguments = ["tunnel", "--url", "http://127.0.0.1:\(site.port)", "--no-autoupdate"]
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.onLog?("[\(site.name)] \(chunk.trimmingCharacters(in: .whitespacesAndNewlines))")
                if let match = chunk.range(of: #"https://[a-zA-Z0-9-]+\.trycloudflare\.com"#, options: .regularExpression) {
                    self?.publicURLs[site.id] = String(chunk[match])
                    self?.onChange?()
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.tunnels.removeValue(forKey: site.id)
                self?.publicURLs.removeValue(forKey: site.id)
                self?.onChange?()
            }
        }
        try process.run()
        tunnels[site.id] = process
        onLog?("[\(site.name)] Starting public tunnel…")
        onChange?()
    }

    func stopExpose(_ site: Site) {
        guard let process = tunnels.removeValue(forKey: site.id) else { return }
        process.terminationHandler = nil
        process.terminate()
        publicURLs.removeValue(forKey: site.id)
        onLog?("[\(site.name)] Public tunnel stopped")
        onChange?()
    }

    func isExposed(_ site: Site) -> Bool { tunnels[site.id] != nil }

    func stopAll() {
        for process in tunnels.values {
            process.terminationHandler = nil
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGTERM) }
        }
        tunnels.removeAll()
        publicURLs.removeAll()
        for entry in httpsProxies.values { terminate(entry) }
        httpsProxies.removeAll()
        httpsHosts.removeAll()
        for entry in sharedServers.values { terminate(entry) }
        sharedServers.removeAll()
        for entry in running.values { terminate(entry) }
        running.removeAll()
    }

    private func configuredProcess(
        site: Site,
        php: URL,
        host: String,
        port: Int,
        label: String,
        behindHTTPSProxy: Bool
    ) throws -> (Process, Pipe) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = php

        if behindHTTPSProxy {
            guard let prepend = securePrependURL() else {
                throw CommandError.failed("Start secure site", 1, "Servo's HTTPS request helper is missing. Rebuild or reinstall Servo and try again.")
            }
            process.currentDirectoryURL = site.documentRoot
            process.arguments = ["-d", "auto_prepend_file=\(prepend.path)", "-S", "\(host):\(port)"]
            if site.isLaravel {
                let router = site.url.appendingPathComponent("vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php")
                guard FileManager.default.fileExists(atPath: router.path) else {
                    throw CommandError.failed("Start secure site", 1, "Laravel's development server is missing. Run composer install for \(site.name) and try again.")
                }
                process.arguments?.append(router.path)
            }
        } else if site.isLaravel {
            process.currentDirectoryURL = site.url
            process.arguments = [site.url.appendingPathComponent("artisan").path, "serve", "--host=\(host)", "--port=\(port)", "--no-reload"]
        } else {
            process.currentDirectoryURL = site.url
            process.arguments = ["-S", "\(host):\(port)", "-t", site.documentRoot.path]
        }
        process.standardOutput = pipe
        process.standardError = pipe
        attachLogging(to: pipe, label: label)
        return (process, pipe)
    }

    private func securePrependURL() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("servo-https-prepend.php")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func attachLogging(to pipe: Pipe, label: String) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let line = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.onLog?("[\(label)] \(line.trimmingCharacters(in: .whitespacesAndNewlines))") }
        }
    }

    private func stopLocal(_ site: Site) {
        guard let entry = running.removeValue(forKey: site.id) else { return }
        terminate(entry)
    }

    private func terminate(_ entry: RunningSite) {
        entry.process.terminationHandler = nil
        entry.pipe.fileHandleForReading.readabilityHandler = nil
        if entry.process.isRunning {
            Darwin.kill(entry.process.processIdentifier, SIGTERM)
        }
    }
}

enum NetworkInfo {
    static func localIPAddress() -> String? {
        var firstAddress: String?
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let start = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: start, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let value = String(cString: host)
            let name = String(cString: interface.ifa_name)
            if name == "en0" { return value }
            if firstAddress == nil { firstAddress = value }
        }
        return firstAddress
    }
}

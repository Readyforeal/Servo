import AppKit
import Foundation
import Security
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var sites: [Site] = []
    @Published var runtimes: [RuntimeInfo] = []
    @Published var logs: [String] = []
    @Published var selected: SidebarItem? = .sites
    @Published var isWorking = false
    @Published var operation = ""
    @Published var errorMessage: String?
    @Published private(set) var serverRevision = 0
    @Published private(set) var localIP: String?
    @Published private(set) var httpsSiteIDs: Set<String> = []
    @Published private(set) var isTrustingHTTPS = false

    private var settings: ServoSettings
    let server = SiteServer()

    init() {
        settings = Self.loadSettings()
        server.onChange = { [weak self] in self?.serverRevision += 1 }
        server.onLog = { [weak self] message in self?.appendLog(message) }
        try? FileManager.default.createDirectory(atPath: settings.rootPath, withIntermediateDirectories: true)
        refreshSites()
        Task {
            await refreshRuntimes()
            await refreshLocalIPAddress()
        }
    }

    var rootURL: URL { URL(fileURLWithPath: settings.rootPath) }
    var rootPath: String { settings.rootPath }
    func refreshSites() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var nextPort = max(8000, (settings.ports.values.max() ?? 7999) + 1)
        sites = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.map { url in
            let port = settings.ports[url.path] ?? nextPort
            if settings.ports[url.path] == nil { settings.ports[url.path] = port; nextPort += 1 }
            return Site(path: url.path, port: port, runtimeSelection: settings.siteRuntimes?[url.path] ?? SiteRuntimeSelection())
        }
        saveSettings()
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Servo sites folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        server.stopAll()
        settings.rootPath = url.path
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        saveSettings()
        refreshSites()
    }

    func addExistingSite() {
        let panel = NSOpenPanel()
        panel.title = "Add an existing site"
        panel.prompt = "Add Site"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let destination = rootURL.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "A site named \(source.lastPathComponent) already exists in the Servo folder."
            return
        }
        do {
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
            appendLog("Added \(source.lastPathComponent) as a linked site")
            refreshSites()
        } catch { errorMessage = error.localizedDescription }
    }

    func createSite(name: String, template: SiteTemplate, runtimes: SiteRuntimeSelection = SiteRuntimeSelection()) async -> Bool {
        let slug = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard slug.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
            errorMessage = "Use letters, numbers, hyphens, or underscores for the site name."
            return false
        }
        let destination = rootURL.appendingPathComponent(slug)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "That folder already exists."
            return false
        }
        isWorking = true
        operation = "Creating \(slug)…"
        appendLog("Creating \(template.rawValue) site \(slug)")
        defer { isWorking = false; operation = "" }
        do {
            let selection = try pinnedSelection(runtimes)
            let environment = try selection.environment()
            let php = try selection.phpExecutable()
            if template == .livewire, let laravel = CommandRunner.executable(named: "laravel") {
                let output = try await CommandRunner.checked(php, arguments: [laravel.path, "new", destination.path, "--using=laravel/livewire-starter-kit", "--no-interaction"], environment: environment)
                appendLog(output)
            } else {
                guard let composer = CommandRunner.executable(named: "composer") else { throw CommandError.unavailable("Composer") }
                let package = template == .livewire ? "laravel/livewire-starter-kit" : "laravel/laravel"
                let output = try await CommandRunner.checked(php, arguments: [composer.path, "create-project", package, destination.path, "--no-interaction"], environment: environment)
                appendLog(output)
            }
            try persistSelection(selection, for: Site(path: destination.path, port: 0))
            refreshSites()
            appendLog("Created \(slug)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            appendLog("Creation failed: \(error.localizedDescription)")
            return false
        }
    }

    func toggle(_ originalSite: Site) {
        var site = originalSite
        guard !httpsSiteIDs.contains(site.id) else { return }
        if server.isRunning(site) {
            server.stop(site)
            return
        }
        httpsSiteIDs.insert(site.id)
        Task {
            defer { httpsSiteIDs.remove(site.id) }
            do {
                await refreshLocalIPAddress()
                guard let localIP else {
                    throw CommandError.failed("Start secure site", 1, "Servo could not find this Mac’s local network address. Connect to Wi-Fi or Ethernet and try again.")
                }
                site.runtimeSelection = try pinnedSelection(site.runtimeSelection)
                try persistSelection(site.runtimeSelection, for: site)
                try server.start(site)
                try server.startHTTPS(site, host: localIP)
                if !UserDefaults.standard.bool(forKey: "caddyCAWasTrusted") {
                    try? await Task.sleep(for: .milliseconds(750))
                    try trustCaddyCA()
                }
            } catch {
                if !server.isHTTPS(site) { server.stop(site) }
                if case CommandError.unavailable = error { selected = .runtimes }
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleExpose(_ site: Site) {
        do { try server.expose(site) }
        catch {
            if case CommandError.unavailable = error { selected = .runtimes }
            errorMessage = error.localizedDescription
        }
    }

    private func trustCaddyCA() throws {
        isTrustingHTTPS = true
        defer { isTrustingHTTPS = false }
        let certificate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Caddy/pki/authorities/local/root.crt")
        guard FileManager.default.fileExists(atPath: certificate.path) else {
            throw CommandError.failed("HTTPS certificate setup", 1, "Caddy has not created its local certificate authority yet. Disable HTTPS, enable it again, and retry.")
        }
        let fileData = try Data(contentsOf: certificate)
        let certificateData: Data
        if let pem = String(data: fileData, encoding: .utf8), pem.contains("-----BEGIN CERTIFICATE-----") {
            let base64 = pem
                .components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("-----") }
                .joined()
            guard let decoded = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
                throw CommandError.failed("HTTPS certificate setup", 1, "Caddy’s PEM certificate could not be decoded.")
            }
            certificateData = decoded
        } else {
            certificateData = fileData
        }
        guard let rootCertificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            throw CommandError.failed("HTTPS certificate setup", 1, "Caddy’s root certificate is not a valid X.509 certificate.")
        }

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: rootCertificate,
            kSecAttrLabel: "Servo Local HTTPS Root"
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw securityError(command: "Import HTTPS certificate", status: addStatus)
        }

        let trustStatus = SecTrustSettingsSetTrustSettings(rootCertificate, .user, nil)
        guard trustStatus == errSecSuccess else {
            throw securityError(command: "Trust HTTPS certificate", status: trustStatus)
        }
        UserDefaults.standard.set(true, forKey: "caddyCAWasTrusted")
        appendLog("Caddy’s local certificate authority is trusted by macOS")
    }

    private func securityError(command: String, status: OSStatus) -> CommandError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "macOS Security returned status \(status)."
        return .failed(command, status, message)
    }

    func open(_ site: Site) {
        let address = server.httpsURL(for: site) ?? "http://127.0.0.1:\(site.port)"
        NSWorkspace.shared.open(URL(string: address)!)
    }

    func reveal(_ site: Site) { NSWorkspace.shared.activateFileViewerSelecting([site.url]) }

    func exportHTTPSCertificate() {
        let source = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Caddy/pki/authorities/local/root.crt")
        guard FileManager.default.fileExists(atPath: source.path) else {
            errorMessage = "Enable HTTPS once before exporting the phone certificate."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Servo’s HTTPS certificate for your phone"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "Servo-Local-CA.crt"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            appendLog("Exported the phone HTTPS certificate to \(destination.path)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshRuntimes() async { runtimes = await RuntimeService.scan() }

    func installed(_ kind: RuntimeInfo.Kind) -> [RuntimeInfo] {
        runtimes.filter { $0.kind == kind }
    }

    func selectRuntime(_ runtime: RuntimeInfo, for site: Site) {
        guard !server.isRunning(site), !httpsSiteIDs.contains(site.id) else { return }
        var selection = site.runtimeSelection
        if runtime.kind == .php { selection.php = RuntimePin(runtime) }
        if runtime.kind == .node { selection.node = RuntimePin(runtime) }
        do {
            // Allow repairing one missing pin even when the other also needs replacing.
            _ = try RuntimePin(runtime).executable()
            try persistSelection(selection, for: site)
        } catch { errorMessage = error.localizedDescription }
    }

    private func persistSelection(_ selection: SiteRuntimeSelection, for site: Site) throws {
        var updated = settings
        if updated.siteRuntimes == nil { updated.siteRuntimes = [:] }
        updated.siteRuntimes?[site.path] = selection
        try JSONEncoder().encode(updated).write(to: Self.settingsURL, options: .atomic)
        settings = updated
        if let index = sites.firstIndex(where: { $0.id == site.id }) { sites[index].runtimeSelection = selection }
    }

    private func pinnedSelection(_ selection: SiteRuntimeSelection) throws -> SiteRuntimeSelection {
        var result = selection
        for kind in [RuntimeInfo.Kind.php, .node] {
            if (kind == .php ? result.php : result.node) == nil,
               let runtime = installed(kind).first {
                if kind == .php { result.php = RuntimePin(runtime) } else { result.node = RuntimePin(runtime) }
            }
        }
        guard result.php != nil else { throw CommandError.unavailable("PHP") }
        _ = try result.environment()
        return result
    }

    func installVersion(_ formula: RuntimeFormula) async {
        guard !isWorking else { return }
        isWorking = true
        operation = "Installing \(formula.label)…"
        defer { isWorking = false; operation = "" }
        do { appendLog(try await RuntimeService.installVersion(formula)) }
        catch { errorMessage = error.localizedDescription }
        await refreshRuntimes()
    }

    func openTerminal(_ site: Site) {
        do {
            let selection = try pinnedSelection(site.runtimeSelection)
            try persistSelection(selection, for: site)
            let environment = try selection.environment()
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Servo/Terminals", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let script = folder.appendingPathComponent("Site-\(UUID().uuidString).command")
            let content = "#!/bin/zsh\ncd -- \(Self.shellQuote(site.path)) || exit 1\nunset PHPRC PHP_INI_SCAN_DIR\nexport PATH=\(Self.shellQuote(environment["PATH"]!))\n/bin/rm -- \(Self.shellQuote(script.path))\nexec /bin/zsh -f\n"
            try content.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch { errorMessage = error.localizedDescription }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func refreshLocalIPAddress() async {
        localIP = await Task.detached(priority: .utility) {
            NetworkInfo.localIPAddress()
        }.value
    }

    func install(_ kind: RuntimeInfo.Kind) async {
        isWorking = true
        operation = "Installing \(kind.rawValue)…"
        defer { isWorking = false; operation = "" }
        do {
            appendLog("Installing \(kind.rawValue)")
            appendLog(try await RuntimeService.install(kind: kind))
            await refreshRuntimes()
        } catch { errorMessage = error.localizedDescription }
    }

    func installRequiredToolchain() async {
        isWorking = true
        defer { isWorking = false; operation = "" }
        do {
            for kind in RuntimeService.requiredToolchain where !RuntimeService.isInstalled(kind) {
                operation = "Installing \(kind.rawValue)…"
                appendLog("Installing \(kind.rawValue)")
                appendLog(try await RuntimeService.install(kind: kind))
            }
            await refreshRuntimes()
            appendLog("Servo's required toolchain is ready")
        } catch {
            await refreshRuntimes()
            errorMessage = error.localizedDescription
        }
    }

    private func appendLog(_ message: String) {
        guard !message.isEmpty else { return }
        logs.append("\(Date.now.formatted(date: .omitted, time: .standard))  \(message)")
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    private static var settingsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Servo")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("settings.json")
    }

    private static func loadSettings() -> ServoSettings {
        guard let data = try? Data(contentsOf: settingsURL), let value = try? JSONDecoder().decode(ServoSettings.self, from: data) else { return .initial }
        return value
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: Self.settingsURL, options: .atomic)
    }
}

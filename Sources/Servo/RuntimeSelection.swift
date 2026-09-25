import Foundation

struct RuntimePin: Codable, Hashable {
    let path: String
    let version: String

    init(_ runtime: RuntimeInfo) {
        path = URL(fileURLWithPath: runtime.path).resolvingSymlinksInPath().path
        version = runtime.version
    }

    init(path: String, version: String) {
        self.path = path
        self.version = version
    }

    func executable() throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw CommandError.failed("Selected runtime unavailable", 1,
                "\(version) is no longer installed at \(path). Install it in Runtimes and select it again for this site. Servo will not substitute another version.")
        }
        return URL(fileURLWithPath: path)
    }
}

struct SiteRuntimeSelection: Codable, Hashable {
    var php: RuntimePin?
    var node: RuntimePin?

    func phpExecutable() throws -> URL {
        if let php { return try php.executable() }
        guard let executable = CommandRunner.executable(named: "php") else {
            throw CommandError.unavailable("PHP")
        }
        return executable.resolvingSymlinksInPath()
    }

    func environment() throws -> [String: String] {
        var environment = CommandRunner.environment()
        var folders: [String] = []
        for pin in [php, node].compactMap({ $0 }) {
            folders.append(try pin.executable().deletingLastPathComponent().path)
        }
        environment["PATH"] = (folders + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        // Avoid inherited PHP configuration overriding a selected installation.
        environment.removeValue(forKey: "PHPRC")
        environment.removeValue(forKey: "PHP_INI_SCAN_DIR")
        return environment
    }
}

struct RuntimeFormula: Identifiable {
    let kind: RuntimeInfo.Kind
    let formula: String
    let label: String
    var id: String { formula }

    static let available: [RuntimeFormula] = [
        .init(kind: .php, formula: "php@8.5", label: "PHP 8.5"),
        .init(kind: .php, formula: "php@8.4", label: "PHP 8.4"),
        .init(kind: .php, formula: "php@8.3", label: "PHP 8.3"),
        .init(kind: .php, formula: "php@8.2", label: "PHP 8.2"),
        .init(kind: .node, formula: "node", label: "Node.js · current"),
        .init(kind: .node, formula: "node@24", label: "Node.js 24"),
        .init(kind: .node, formula: "node@22", label: "Node.js 22")
    ]
}

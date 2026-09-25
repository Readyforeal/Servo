import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

enum CommandError: LocalizedError {
    case unavailable(String)
    case failed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let tool): "Could not find \(tool). Install it from Runtimes and try again."
        case .failed(let command, let status, let output):
            "\(command) exited with status \(status).\n\(output)"
        }
    }
}

enum CommandRunner {
    static func executable(named name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var folders = searchFolders(home: home)
        if name == "node" || name == "npm" {
            let versionRoots = ["\(home)/.nvm/versions/node"]
            for root in versionRoots {
                let versions = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
                folders.append(contentsOf: versions.sorted().reversed().map { "\(root)/\($0)/bin" })
            }
        }
        for folder in folders {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    static func run(_ executable: URL, arguments: [String], directory: URL? = nil) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.environment = environment()
            process.standardOutput = pipe
            process.standardError = pipe
            DispatchQueue.global(qos: .utility).async {
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: CommandResult(status: process.terminationStatus, output: output))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func checked(_ executable: URL, arguments: [String], directory: URL? = nil) async throws -> String {
        let result = try await run(executable, arguments: arguments, directory: directory)
        guard result.status == 0 else {
            throw CommandError.failed(([executable.lastPathComponent] + arguments).joined(separator: " "), result.status, result.output)
        }
        return result.output
    }

    static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = searchFolders(home: home).joined(separator: ":")
        return environment
    }

    private static func searchFolders(home: String) -> [String] {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !isHerdPath($0) }
        let standard = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            "\(home)/.local/bin", "\(home)/.local/share/mise/shims", "\(home)/.asdf/shims", "\(home)/.volta/bin",
            "\(home)/.composer/vendor/bin", "\(home)/.config/composer/vendor/bin"
        ]
        var seen = Set<String>()
        return (standard + inherited).filter { seen.insert($0).inserted }
    }

    private static func isHerdPath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).pathComponents.contains { component in
            let name = component.lowercased()
            return name == "herd" || name == "herd.app"
        }
    }
}

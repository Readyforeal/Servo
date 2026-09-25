import Foundation

enum RuntimeService {
    static func scan() async -> [RuntimeInfo] {
        var results: [RuntimeInfo] = []
        for (kind, name) in [(RuntimeInfo.Kind.php, "php"), (.node, "node"), (.composer, "composer"), (.npm, "npm"), (.laravel, "laravel"), (.cloudflared, "cloudflared"), (.caddy, "caddy")] {
            guard let executable = CommandRunner.executable(named: name) else { continue }
            let arguments = kind == .composer ? ["--version"] : ["--version"]
            if let result = try? await CommandRunner.run(executable, arguments: arguments) {
                let firstLine = result.output.split(separator: "\n").first.map(String.init) ?? "Installed"
                results.append(RuntimeInfo(kind: kind, path: executable.path, version: firstLine))
            }
        }
        return results
    }

    static func install(kind: RuntimeInfo.Kind) async throws -> String {
        guard let brew = CommandRunner.executable(named: "brew") else { throw CommandError.unavailable("Homebrew") }
        let formula: String
        switch kind {
        case .php: formula = "php"
        case .node, .npm: formula = "node"
        case .composer: formula = "composer"
        case .cloudflared: formula = "cloudflared"
        case .caddy: formula = "caddy"
        case .laravel:
            guard let composer = CommandRunner.executable(named: "composer") else { throw CommandError.unavailable("Composer") }
            return try await CommandRunner.checked(composer, arguments: ["global", "require", "laravel/installer"])
        }
        return try await CommandRunner.checked(brew, arguments: ["install", formula])
    }
}

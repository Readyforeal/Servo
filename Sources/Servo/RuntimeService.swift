import AppKit
import Foundation

enum RuntimeService {
    private struct GitHubRelease: Decodable {
        let assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private static let executableNames: [(RuntimeInfo.Kind, String)] = [
        (.homebrew, "brew"),
        (.php, "php"),
        (.node, "node"),
        (.npm, "npm"),
        (.composer, "composer"),
        (.laravel, "laravel"),
        (.cloudflared, "cloudflared"),
        (.caddy, "caddy")
    ]

    static let requiredToolchain: [RuntimeInfo.Kind] = [
        .homebrew, .php, .node, .composer, .laravel, .caddy
    ]

    static func scan() async -> [RuntimeInfo] {
        var results: [RuntimeInfo] = []
        for (kind, name) in executableNames {
            guard let executable = CommandRunner.executable(named: name) else { continue }
            if let result = try? await CommandRunner.run(executable, arguments: ["--version"]) {
                let firstLine = result.output.split(separator: "\n").first.map(String.init) ?? "Installed"
                results.append(RuntimeInfo(kind: kind, path: executable.path, version: firstLine))
            }
        }
        return results
    }

    static func isInstalled(_ kind: RuntimeInfo.Kind) -> Bool {
        guard let name = executableNames.first(where: { $0.0 == kind })?.1 else { return false }
        return CommandRunner.executable(named: name) != nil
    }

    static func install(kind: RuntimeInfo.Kind) async throws -> String {
        if kind == .homebrew {
            let brew = try await ensureHomebrew()
            return try await CommandRunner.checked(brew, arguments: ["--version"])
        }

        let brew = try await ensureHomebrew()
        let formula: String
        switch kind {
        case .homebrew:
            return "Homebrew is installed."
        case .php: formula = "php"
        case .node, .npm: formula = "node"
        case .composer: formula = "composer"
        case .cloudflared: formula = "cloudflared"
        case .caddy: formula = "caddy"
        case .laravel:
            if CommandRunner.executable(named: "composer") == nil {
                _ = try await CommandRunner.checked(brew, arguments: ["install", "composer"])
            }
            guard let composer = CommandRunner.executable(named: "composer") else {
                throw CommandError.unavailable("Composer")
            }
            return try await CommandRunner.checked(composer, arguments: ["global", "require", "laravel/installer"])
        }
        return try await CommandRunner.checked(brew, arguments: ["install", formula])
    }

    private static func ensureHomebrew() async throws -> URL {
        if let brew = CommandRunner.executable(named: "brew") { return brew }

        #if arch(arm64)
        let package = try await downloadHomebrewInstaller()
        let signature = try await CommandRunner.run(
            URL(fileURLWithPath: "/usr/sbin/pkgutil"),
            arguments: ["--check-signature", package.path]
        )
        guard signature.status == 0,
              signature.output.localizedCaseInsensitiveContains("Developer ID Installer:"),
              signature.output.localizedCaseInsensitiveContains("Notarization: trusted by the Apple notary service") else {
            throw CommandError.failed("Verify Homebrew installer", signature.status, signature.output)
        }

        let opened = await MainActor.run { NSWorkspace.shared.open(package) }
        guard opened else {
            throw CommandError.failed("Open Homebrew installer", 1, "macOS could not open the downloaded installer package.")
        }

        for _ in 0..<600 {
            try Task.checkCancellation()
            if let brew = CommandRunner.executable(named: "brew"),
               let result = try? await CommandRunner.run(brew, arguments: ["--version"]),
               result.status == 0 {
                return brew
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw CommandError.failed(
            "Install Homebrew",
            1,
            "Homebrew was not detected. Complete the installer, then return to Servo and try again."
        )
        #else
        throw CommandError.failed(
            "Install Homebrew",
            1,
            "Servo's automatic Homebrew installer currently supports Apple silicon Macs."
        )
        #endif
    }

    private static func downloadHomebrewInstaller() async throws -> URL {
        let apiURL = URL(string: "https://api.github.com/repos/Homebrew/brew/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("Servo/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (releaseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CommandError.failed("Find Homebrew installer", 1, "GitHub did not return the latest Homebrew release.")
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: releaseData)
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".pkg") }) else {
            throw CommandError.failed("Find Homebrew installer", 1, "The latest Homebrew release does not include a macOS installer package.")
        }
        guard asset.browserDownloadURL.host == "github.com" else {
            throw CommandError.failed("Download Homebrew installer", 1, "The installer download did not come from GitHub.")
        }

        let (temporaryURL, downloadResponse) = try await URLSession.shared.download(from: asset.browserDownloadURL)
        guard let downloadHTTP = downloadResponse as? HTTPURLResponse, downloadHTTP.statusCode == 200 else {
            throw CommandError.failed("Download Homebrew installer", 1, "The Homebrew installer download failed.")
        }

        let installerFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Servo/Installers", isDirectory: true)
        try FileManager.default.createDirectory(at: installerFolder, withIntermediateDirectories: true)
        let destination = installerFolder.appendingPathComponent(asset.name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }
}

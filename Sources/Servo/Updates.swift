import AppKit
import SwiftUI

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              pieces.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = pieces.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    struct Asset: Decodable { let name: String; let browser_download_url: URL }
    func installer(repository: String) -> URL? {
        guard !draft, !prerelease, let version = ReleaseVersion(tag_name) else { return nil }
        let name = "Servo-" + version.parts.map(String.init).joined(separator: ".") + "-arm64.dmg"
        return assets.first { asset in
            let url = asset.browser_download_url
            return asset.name == name && url.scheme == "https" && url.host == "github.com" &&
                url.path.hasPrefix("/\(repository)/releases/download/") && url.user == nil && url.password == nil
        }?.browser_download_url
    }
}
@MainActor final class UpdateChecker: ObservableObject {
    @Published private(set) var checking = false
    static var repository: String { Bundle.main.object(forInfoDictionaryKey: "ServoUpdateRepository") as? String ?? "Readyforeal/Servo" }
    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let repo = Self.repository
        let page = URL(string: "https://github.com/\(repo)/releases")!
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
            request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Servo", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateError.message("GitHub returned an invalid response.") }
            if http.statusCode == 404 {
                show("No release available", "No stable release has been published yet. Development installers may be available on the Releases page.", url: page, action: "Open Releases")
                return
            }
            guard http.statusCode == 200 else { throw UpdateError.message("GitHub returned HTTP \(http.statusCode). Please try again later.") }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            guard !release.draft, !release.prerelease, let latest = ReleaseVersion(release.tag_name), let installed = ReleaseVersion(current) else {
                throw UpdateError.message("The release has an unsupported version number.")
            }
            guard latest > installed else { show("You’re up to date", "Servo \(current) is the latest published version."); return }
            guard let installer = release.installer(repository: repo) else {
                show("Update awaiting an installer", "Version \(release.tag_name) is available, but its Apple silicon DMG has not been published yet.", url: page, action: "Open Releases"); return
            }
            show("Servo \(release.tag_name) is available", "You have \(current). Download the macOS 14+ installer, quit Servo, and drag the new app into Applications to replace this version. Your sites and settings stay intact. Quitting Servo stops its running servers.", url: installer, action: "Download Update")
        } catch {
            show("Couldn’t check for updates", error.localizedDescription)
        }
    }
    private func show(_ title: String, _ message: String, url: URL? = nil, action: String = "OK") {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: action)
        if url != nil { alert.addButton(withTitle: "Later") }
        if alert.runModal() == .alertFirstButtonReturn, let url { NSWorkspace.shared.open(url) }
    }
}

private enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

import Foundation

struct Site: Identifiable, Hashable {
    let path: String
    var port: Int
    var runtimeSelection = SiteRuntimeSelection()

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var isLaravel: Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("artisan").path)
    }
    var documentRoot: URL {
        let publicFolder = url.appendingPathComponent("public")
        return FileManager.default.fileExists(atPath: publicFolder.path) ? publicFolder : url
    }
}

enum SiteTemplate: String, CaseIterable, Identifiable {
    case laravel = "Laravel"
    case livewire = "Laravel + Livewire"
    var id: String { rawValue }

    var detail: String {
        switch self {
        case .laravel: "A clean Laravel application"
        case .livewire: "Livewire, Flux UI, Tailwind, and authentication"
        }
    }
}

struct RuntimeInfo: Identifiable, Hashable {
    enum Kind: String {
        case homebrew = "Homebrew"
        case php = "PHP"
        case node = "Node.js"
        case composer = "Composer"
        case npm = "npm"
        case laravel = "Laravel Installer"
        case cloudflared = "Cloudflare Tunnel"
        case caddy = "Caddy HTTPS"
    }
    let kind: Kind
    let path: String
    let version: String
    var id: String { "\(kind.rawValue):\(path)" }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case sites = "Sites"
    case runtimes = "Runtimes"
    case activity = "Activity"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .sites: "macwindow"
        case .runtimes: "shippingbox"
        case .activity: "text.alignleft"
        }
    }
}

struct ServoSettings: Codable {
    var rootPath: String
    var ports: [String: Int]
    // Optional for backward compatibility with existing settings.json files.
    var siteRuntimes: [String: SiteRuntimeSelection]? = [:]

    static var initial: ServoSettings {
        ServoSettings(
            rootPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Servo").path,
            ports: [:]
        )
    }
}

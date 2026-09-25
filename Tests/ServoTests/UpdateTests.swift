import Foundation
import Testing
@testable import Servo

@Suite("GitHub updates") struct UpdateTests {
    @Test func versions() {
        #expect(ReleaseVersion("v0.10.0")! > ReleaseVersion("0.9.9")!)
        #expect(ReleaseVersion("0.2.0-beta") == nil)
        #expect(ReleaseVersion("invalid") == nil)
    }
    @Test func installerValidation() {
        let page = URL(string: "https://github.com/Readyforeal/Servo/releases")!
        let download = URL(string: "https://github.com/Readyforeal/Servo/releases/download/v0.2.0/Servo-0.2.0-arm64.dmg")!
        let asset = GitHubRelease.Asset(name: "Servo-0.2.0-arm64.dmg", browser_download_url: download)
        let release = GitHubRelease(tag_name: "v0.2.0", html_url: page, draft: false, prerelease: false, assets: [asset])
        #expect(release.installer(repository: "Readyforeal/Servo") == download)
        #expect(release.installer(repository: "other/repository") == nil)
        let development = GitHubRelease(tag_name: "v0.2.0", html_url: page, draft: false, prerelease: true, assets: [asset])
        #expect(development.installer(repository: "Readyforeal/Servo") == nil)
        let noInstaller = GitHubRelease(tag_name: "v0.2.0", html_url: page, draft: false, prerelease: false, assets: [])
        #expect(noInstaller.installer(repository: "Readyforeal/Servo") == nil)
    }
}

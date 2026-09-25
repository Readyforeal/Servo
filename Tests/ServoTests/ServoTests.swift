import Foundation
import Testing
@testable import Servo

@Suite("Site detection")
struct ServoTests {
    @Test func laravelSiteUsesPublicDocumentRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("public"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("artisan"))
        defer { try? FileManager.default.removeItem(at: root) }
        let site = Site(path: root.path, port: 8000)
        #expect(site.isLaravel)
        #expect(site.documentRoot.lastPathComponent == "public")
    }

    @Test func plainSiteUsesItsOwnRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let site = Site(path: root.path, port: 8001)
        #expect(!site.isLaravel)
        #expect(site.documentRoot.standardizedFileURL.path == root.standardizedFileURL.path)
    }
}

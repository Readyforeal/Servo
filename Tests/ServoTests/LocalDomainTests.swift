import Foundation
import Testing
@testable import Servo

@Suite("Local domains") @MainActor struct LocalDomainTests {
    @Test func namesAreSafeAndCollisionsAreDistinct() {
        let sites = [Site(path: "/sites/shop", port: 8000), Site(path: "/sites/My Shop", port: 8001), Site(path: "/sites/my-shop", port: 8002), Site(path: "/sites/☃", port: 8003)]
        let hosts = LocalDomains.hosts(for: sites)
        #expect(hosts["/sites/shop"] == "shop.test")
        #expect(Set(hosts.values).count == sites.count)
        #expect(hosts.values.allSatisfy(LocalDomains.validHost))
        #expect(!LocalDomains.validHost("bad.test;touch /tmp/bad"))
        #expect(!LocalDomains.validHost("example.com"))
        #expect(!LocalDomains.validHost("-bad.test"))
    }
    @Test func routesAreLoopbackOnlyAndPreserveProjectPorts() throws {
        let sites = [Site(path: "/sites/one", port: 8001), Site(path: "/sites/two", port: 8002)]
        let data = try LocalDomains.config(sites: sites, socket: "/tmp/servo-test.sock")
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let admin = try #require(object["admin"] as? [String: String])
        #expect(admin["listen"] == "unix//tmp/servo-test.sock")
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("127.0.0.1:17880"))
        #expect(text.contains("127.0.0.1:8001"))
        #expect(text.contains("127.0.0.1:8002"))
        #expect(text.contains("one.test")); #expect(text.contains("two.test"))
        #expect(!text.contains("0.0.0.0"))
        if let output = ProcessInfo.processInfo.environment["SERVO_TEST_CONFIG"] {
            try data.write(to: URL(fileURLWithPath: output))
        }
    }
}

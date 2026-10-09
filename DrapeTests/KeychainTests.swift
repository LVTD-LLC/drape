import XCTest
@testable import Drape

final class KeychainTests: XCTestCase {
    func testSaveUpdateAndDeleteKeyInIsolatedService() throws {
        let service = "dev.lvtd.drape.tests.\(UUID().uuidString)"
        defer { try? Keychain.save("", service: service) }
        XCTAssertEqual(try Keychain.read(service: service), "")
        try Keychain.save("test-key-not-a-secret", service: service)
        XCTAssertEqual(try Keychain.read(service: service), "test-key-not-a-secret")
        try Keychain.save("replacement-test-key", service: service)
        XCTAssertEqual(try Keychain.read(service: service), "replacement-test-key")
        try Keychain.save("", service: service)
        XCTAssertEqual(try Keychain.read(service: service), "")
    }
}

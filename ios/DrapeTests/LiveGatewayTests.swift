import XCTest
@testable import Drape

/// Explicit paid deployment check, excluded unless opted in through the test runner.
/// Uses only the synthetic fixture and never retries either paid request.
final class LiveGatewayTests: XCTestCase {
    func testSyntheticPhotoAgainstDeployedGateway() async throws {
        guard ProcessInfo.processInfo.environment["DRAPE_LIVE_GATEWAY_SMOKE"] == "1" else {
            throw XCTSkip("Opt-in paid integration check")
        }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cardigan-source", withExtension: "png"))
        let photo = try Data(contentsOf: fixture)
        let url = try XCTUnwrap(OpenRouter.developmentURL)
        XCTAssertEqual(url.absoluteString, "https://drape-ai.cr.lvtd.dev/api/v1/")
        let service = OpenRouter()
        let details = try await service.analyze(photos: [PhotoInput(data: photo)], configuration: .automatic)
        XCTAssertFalse(details.name.isEmpty)
        XCTAssertTrue(details.brand.isEmpty)
        XCTAssertTrue(details.size.isEmpty)
        XCTAssertTrue(details.care.isEmpty)
        let studio = try await service.studioPhoto(front: photo, configuration: .automatic)
        XCTAssertGreaterThan(studio.count, 1_000)
        XCTAssertNotEqual(studio, photo)
    }
}

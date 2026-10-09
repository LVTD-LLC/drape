import XCTest
@testable import Drape

final class OpenRouterTests: XCTestCase {
    func testStructuredResponseDecodingAndMissingFieldsRejection() throws {
        var details = ItemDetails(); details.name = "Navy shirt"; details.category = .tops; details.color = "Navy"
        let json = String(data: try JSONEncoder().encode(details), encoding: .utf8)!
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": json]]]])
        XCTAssertEqual(try OpenRouter.decodeDetails(response), details)
        let badResponse = Data(#"{"choices":[{"message":{"content":"{\"name\":\"Shirt\"}"}}]}"#.utf8)
        XCTAssertThrowsError(try OpenRouter.decodeDetails(badResponse))
        XCTAssertThrowsError(try OpenRouter.decodeDetails(Data(#"{"choices":[]}"#.utf8)))
    }

    func testImageResponseRejectsMalformedPayload() {
        XCTAssertThrowsError(try OpenRouter.decodeImage(Data(#"{"data":[{"b64_json":"not valid base64!"}]}"#.utf8)))
        XCTAssertThrowsError(try OpenRouter.decodeImage(Data(#"{"data":[]}"#.utf8)))
    }

    func testModelCapabilityFiltering() throws {
        let json = Data(#"{"id":"provider/model","name":"Model","architecture":{"input_modalities":["text","image"],"output_modalities":["text"]},"supported_parameters":["structured_outputs"]}"#.utf8)
        let model = try JSONDecoder().decode(ModelOption.self, from: json)
        XCTAssertTrue(model.supportsAnalysis)
        XCTAssertFalse(model.supportsImage)
    }

    func testMissingKeyDoesNotMakeNetworkRequest() async {
        let configuration = AIConfiguration(key: "", analysisModel: "model", imageModel: "model", generateStudio: false)
        do {
            _ = try await OpenRouter().analyze(photos: [], configuration: configuration)
            XCTFail("Expected missing key")
        } catch { XCTAssertEqual(error.localizedDescription, AIError.missingKey.localizedDescription) }
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseStatus = 200
    nonisolated(unsafe) private static var responseBody = Data()
    nonisolated(unsafe) private static var capturedRequest: URLRequest?
    static func configure(status: Int, body: Data) {
        lock.lock(); defer { lock.unlock() }
        responseStatus = status; responseBody = body; capturedRequest = nil
    }
    static func request() -> URLRequest? {
        lock.lock(); defer { lock.unlock() }; return capturedRequest
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let status = Self.responseStatus, body = Self.responseBody
        Self.capturedRequest = request
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class OpenRouterTransportTests: XCTestCase {
    private func service() -> OpenRouter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OpenRouter(session: URLSession(configuration: configuration))
    }
    func testAuthenticatedAnalysisUsesExpectedEndpointAndReturnsTypedDetails() async throws {
        var details = ItemDetails(); details.name = "Cream cardigan"; details.category = .outerwear
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": String(data: try JSONEncoder().encode(details), encoding: .utf8)!]]]])
        StubURLProtocol.configure(status: 200, body: response)
        let configuration = AIConfiguration(key: "test-key-not-a-secret", analysisModel: "test/model", imageModel: "test/image", generateStudio: false)
        let result = try await service().analyze(photos: [PhotoInput(role: .front, data: DemoData.photo(color: .brown, symbol: "tshirt"))], configuration: configuration)
        XCTAssertEqual(result, details)
        let request = try XCTUnwrap(StubURLProtocol.request())
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key-not-a-secret")
    }
    func testRateLimitReturnsRecoverableMessageWithoutProviderBody() async {
        StubURLProtocol.configure(status: 429, body: Data("sensitive provider payload".utf8))
        do {
            _ = try await service().models()
            XCTFail("Expected rate limit")
        } catch {
            XCTAssertEqual(error.localizedDescription, AIError.http(429).localizedDescription)
            XCTAssertFalse(error.localizedDescription.contains("sensitive"))
        }
    }
}

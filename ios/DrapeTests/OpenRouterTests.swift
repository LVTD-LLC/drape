import XCTest
@testable import Drape

final class OpenRouterTests: XCTestCase {
    func testModelDefaultsMigrateMissingAndLegacyChoicesWithoutReplacingCustomChoices() throws {
        let suite = "DrapeModelDefaultsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for (analysis, image, expectedAnalysis, expectedImage) in [
            (nil, nil, AIModelDefaults.analysis, AIModelDefaults.image),
            ("google/gemini-2.5-flash", "google/gemini-2.5-flash-image", AIModelDefaults.analysis, AIModelDefaults.image),
            ("custom/analysis", "google/gemini-2.5-flash-image", "custom/analysis", AIModelDefaults.image),
            ("google/gemini-2.5-flash", "custom/image", AIModelDefaults.analysis, "custom/image")
        ] as [(String?, String?, String, String)] {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(analysis, forKey: "analysisModel")
            defaults.set(image, forKey: "imageModel")
            AIModelDefaults.migrateSavedChoices(in: defaults)
            XCTAssertEqual(defaults.string(forKey: "analysisModel"), expectedAnalysis)
            XCTAssertEqual(defaults.string(forKey: "imageModel"), expectedImage)
        }
    }

    func testModelDefaultsMigrationDoesNotOverrideLaterSelections() throws {
        let suite = "DrapeModelDefaultsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        AIModelDefaults.migrateSavedChoices(in: defaults)
        defaults.set("google/gemini-2.5-flash", forKey: "analysisModel")
        defaults.set("google/gemini-2.5-flash-image", forKey: "imageModel")
        AIModelDefaults.migrateSavedChoices(in: defaults)
        XCTAssertEqual(defaults.string(forKey: "analysisModel"), "google/gemini-2.5-flash")
        XCTAssertEqual(defaults.string(forKey: "imageModel"), "google/gemini-2.5-flash-image")
    }

    func testStructuredResponseDecodingAndMissingFieldsRejection() throws {
        var details = ItemDetails(); details.name = "Navy shirt"; details.category = .tops; details.color = "Navy"
        let json = String(data: try JSONEncoder().encode(ItemAnalysis(details: details)), encoding: .utf8)!
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": json]]]])
        XCTAssertEqual(try OpenRouter.decodeDetails(response).details, details)
        let badResponse = Data(#"{"choices":[{"message":{"content":"{\"name\":\"Shirt\"}"}}]}"#.utf8)
        XCTAssertThrowsError(try OpenRouter.decodeDetails(badResponse))
        XCTAssertThrowsError(try OpenRouter.decodeDetails(Data(#"{"choices":[]}"#.utf8)))
    }

    func testImageResponseRejectsMalformedPayload() {
        XCTAssertThrowsError(try OpenRouter.decodeImage(Data(#"{"data":[{"b64_json":"not valid base64!"}]}"#.utf8)))
        XCTAssertThrowsError(try OpenRouter.decodeImage(Data(#"{"data":[]}"#.utf8)))
    }

    func testRichAnalysisDecodesEvidenceAndRejectsInventedSourcesOrInvalidPrices() throws {
        var details = ItemDetails(); details.category = .accessories; details.subcategory = "Hats"
        var analysis = ItemAnalysis(details: details, attributes: ItemAttributes(typeDetail: "Wide-brim hat", tags: [" SUMMER ", "summer"],
            originalPrice: OriginalPrice(amount: "25.50", currency: "EUR", source: .photo, evidence: "EUR 25.50"),
            condition: ConditionAssessment(grade: .good, source: .photo, evidence: "Light creasing on the brim")))
        func response(_ value: ItemAnalysis) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": String(data: JSONEncoder().encode(value), encoding: .utf8)!]]]])
        }
        let decoded = try OpenRouter.decodeDetails(response(analysis))
        XCTAssertEqual(decoded.attributes.tags, ["summer"])
        XCTAssertEqual(decoded.attributes.originalPrice?.amount, "25.50")
        XCTAssertEqual(decoded.attributes.condition?.grade, .good)
        analysis.attributes.originalPrice?.source = .user
        XCTAssertThrowsError(try OpenRouter.decodeDetails(response(analysis)))
        analysis.attributes.originalPrice = nil
        analysis.attributes.condition?.evidence = ""
        XCTAssertThrowsError(try OpenRouter.decodeDetails(response(analysis)))
        analysis.attributes.condition = nil; analysis.details.subcategory = "Sneakers"
        XCTAssertThrowsError(try OpenRouter.decodeDetails(response(analysis)))
    }

    func testModelCapabilityFiltering() throws {
        let json = Data(#"{"id":"provider/model","name":"Model","architecture":{"input_modalities":["text","image"],"output_modalities":["text"]},"supported_parameters":["structured_outputs"]}"#.utf8)
        let model = try JSONDecoder().decode(ModelOption.self, from: json)
        XCTAssertTrue(model.supportsAnalysis)
        XCTAssertFalse(model.supportsImage)
    }

    func testMissingServiceDoesNotMakeNetworkRequest() async {
        let configuration = AIConfiguration(analysisModel: "model", imageModel: "model", generateStudio: false)
        do {
            _ = try await OpenRouter(baseURL: nil).analyze(photos: [], configuration: configuration)
            XCTFail("Expected missing service")
        } catch { XCTAssertEqual(error.localizedDescription, AIError.serviceUnavailable.localizedDescription) }
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
    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func service() -> OpenRouter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OpenRouter(session: URLSession(configuration: configuration), baseURL: URL(string: "https://drape-ai.example/api/v1/")!, developmentToken: "test-development-token")
    }
    func testAnalysisUsesDrapeServiceWithoutProviderCredentialsAndReturnsTypedDetails() async throws {
        var details = ItemDetails(); details.name = "Cream cardigan"; details.category = .outerwear
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": String(data: try JSONEncoder().encode(ItemAnalysis(details: details)), encoding: .utf8)!]]]])
        StubURLProtocol.configure(status: 200, body: response)
        let configuration = AIConfiguration(analysisModel: AIModelDefaults.analysis, imageModel: AIModelDefaults.image, generateStudio: false)
        let result = try await service().analyze(photos: [PhotoInput(role: .front, data: DemoData.photo(color: .brown, symbol: "tshirt"))], configuration: configuration)
        XCTAssertEqual(result.details, details)
        let request = try XCTUnwrap(StubURLProtocol.request())
        XCTAssertEqual(request.url?.absoluteString, "https://drape-ai.example/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-development-token")
        XCTAssertEqual(try requestBody(request)["model"] as? String, "openai/gpt-6-luna")
    }

    func testStudioRequestUsesSeedreamComparisonSettingsOnlyForSeedream() async throws {
        let photo = DemoData.photo(color: .brown, symbol: "tshirt")
        let response = try JSONSerialization.data(withJSONObject: ["data": [["b64_json": photo.base64EncodedString()]]])
        for model in [AIModelDefaults.image, "custom/image"] {
            StubURLProtocol.configure(status: 200, body: response)
            let configuration = AIConfiguration(analysisModel: AIModelDefaults.analysis, imageModel: model, generateStudio: true)
            let result = try await service().studioPhoto(front: photo, configuration: configuration)
            XCTAssertFalse(result.isEmpty)
            let request = try XCTUnwrap(StubURLProtocol.request())
            XCTAssertEqual(request.url?.absoluteString, "https://drape-ai.example/api/v1/images")
            let body = try requestBody(request)
            XCTAssertEqual(body["model"] as? String, model)
            XCTAssertEqual(body["resolution"] as? String, model == AIModelDefaults.image ? "1K" : nil)
            XCTAssertEqual(body["aspect_ratio"] as? String, model == AIModelDefaults.image ? "3:4" : nil)
            XCTAssertEqual(body["n"] as? Int, 1)
            XCTAssertEqual((body["input_references"] as? [[String: Any]])?.count, 1)
        }
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

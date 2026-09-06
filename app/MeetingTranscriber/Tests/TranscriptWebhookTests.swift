@testable import MeetingTranscriber
import XCTest

private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.withLock { body(&stored) }
    }
}

final class TranscriptWebhookTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.errorHandler = nil
        MockURLProtocol.rawResponseHandler = nil
        MockURLProtocol.hangHandler = nil
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeWebhook(
        endpoint: String = "https://example.com/hook",
        token: String? = "secret-token",
        maxAttempts: Int = 3,
    ) -> TranscriptWebhook {
        TranscriptWebhook(
            endpoint: URL(string: endpoint)!,
            token: token,
            session: makeSession(),
            maxAttempts: maxAttempts,
            retryBackoff: .milliseconds(1),
        )
    }

    private let delivery = TranscriptDelivery(
        jobId: "11111111-2222-3333-4444-555555555555",
        meetingTitle: "Client call",
        appName: "zoom.us",
        startedAt: "2026-09-06T12:00:00Z",
        enqueuedAt: "2026-09-06T13:00:00Z",
        participants: ["Alice"],
        transcript: "[Alice] hello",
        warnings: [],
    )

    private func response(_ request: URLRequest, status: Int = 200, body: Data = Data())
        -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
            body,
        )
    }

    // MARK: - Endpoint validation

    func testValidateRejectsRemotePlaintext() {
        XCTAssertEqual(
            TranscriptWebhook.validate(endpoint: URL(string: "http://example.com/h")!),
            .insecureEndpoint,
        )
        XCTAssertNil(TranscriptWebhook.validate(endpoint: URL(string: "https://example.com/h")!))
        XCTAssertNil(TranscriptWebhook.validate(endpoint: URL(string: "http://localhost:9000/h")!))
    }

    func testValidateRejectsNonHTTPScheme() {
        XCTAssertEqual(
            TranscriptWebhook.validate(endpoint: URL(string: "ftp://example.com/h")!),
            .insecureEndpoint,
        )
    }

    // MARK: - Request shape

    func testRequestCarriesAuthAndIdempotencyKey() async throws {
        let key = delivery.jobId
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), key)
            return self.response(request)
        }
        try await makeWebhook().send(delivery)
    }

    func testNoTokenOmitsAuthorizationHeader() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return self.response(request)
        }
        try await makeWebhook(token: nil).send(delivery)
    }

    // MARK: - Retry behaviour

    func testTransportFailureIsRetriedThenSucceeds() async throws {
        let attempts = Box(0)
        MockURLProtocol.errorHandler = { _ in
            attempts.mutate { $0 += 1 }
            if attempts.value >= 2 { MockURLProtocol.errorHandler = nil }
            return URLError(.networkConnectionLost)
        }
        MockURLProtocol.handler = { request in self.response(request) }

        try await makeWebhook().send(delivery)
        XCTAssertEqual(attempts.value, 2, "expected two failures before the success")
    }

    func testUnauthorizedIsNotRetried() async {
        let attempts = Box(0)
        MockURLProtocol.handler = { request in
            attempts.mutate { $0 += 1 }
            return self.response(request, status: 401, body: Data("bad token".utf8))
        }

        do {
            try await makeWebhook().send(delivery)
            XCTFail("expected a 401 to throw")
        } catch let error as TranscriptWebhook.DeliveryError {
            XCTAssertEqual(error, .httpError(status: 401, body: "bad token"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(attempts.value, 1)
    }

    func testServerErrorExhaustsAttemptsThenThrows() async {
        let attempts = Box(0)
        MockURLProtocol.handler = { request in
            attempts.mutate { $0 += 1 }
            return self.response(request, status: 503)
        }

        do {
            try await makeWebhook(maxAttempts: 3).send(delivery)
            XCTFail("expected exhausted retries to throw")
        } catch {
            // expected
        }
        XCTAssertEqual(attempts.value, 3)
    }

    func testRetryClassification() {
        XCTAssertTrue(TranscriptWebhook.isRetryable(.transport("dropped")))
        XCTAssertTrue(TranscriptWebhook.isRetryable(.httpError(status: 500, body: "")))
        XCTAssertTrue(TranscriptWebhook.isRetryable(.httpError(status: 429, body: "")))
        XCTAssertFalse(TranscriptWebhook.isRetryable(.httpError(status: 400, body: "")))
        XCTAssertFalse(TranscriptWebhook.isRetryable(.httpError(status: 404, body: "")))
        XCTAssertFalse(TranscriptWebhook.isRetryable(.insecureEndpoint))
    }

    func testSendRefusesInsecureEndpointWithoutHittingNetwork() async {
        let called = Box(false)
        MockURLProtocol.handler = { request in
            called.value = true
            return self.response(request)
        }
        do {
            try await makeWebhook(endpoint: "http://example.com/hook").send(delivery)
            XCTFail("expected an insecure endpoint to throw")
        } catch let error as TranscriptWebhook.DeliveryError {
            XCTAssertEqual(error, .insecureEndpoint)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertFalse(called.value)
    }

    func testBodyIsCompleteJSON() async throws {
        let payload = delivery
        MockURLProtocol.handler = { request in
            let body = request.httpBody ?? request.httpBodyStream.map { stream in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(contentsOf: buffer[0 ..< read])
                }
                return data
            } ?? Data()

            let decoded = try? JSONDecoder().decode(TranscriptDelivery.self, from: body)
            XCTAssertEqual(decoded, payload, "body must round-trip to the delivery that was sent")
            return self.response(request)
        }
        try await makeWebhook().send(delivery)
    }
}

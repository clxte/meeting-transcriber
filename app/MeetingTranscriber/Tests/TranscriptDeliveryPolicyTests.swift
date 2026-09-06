@testable import MeetingTranscriber
import XCTest

final class TranscriptDeliveryPolicyTests: XCTestCase {
    private func decide(
        enabled: Bool = true,
        endpoint: String = "https://example.com/hook",
        hasTranscript: Bool = true,
    ) -> TranscriptDeliveryPolicy.Decision {
        TranscriptDeliveryPolicy.decide(
            enabled: enabled, endpoint: endpoint, hasTranscript: hasTranscript,
        )
    }

    func testHappyPath() {
        XCTAssertEqual(
            decide(),
            .send(endpoint: URL(string: "https://example.com/hook")!),
        )
    }

    func testDisabledSkips() {
        XCTAssertEqual(decide(enabled: false), .skip(.disabled))
    }

    func testEmptyEndpointIsNotAMisconfiguration() {
        XCTAssertEqual(decide(endpoint: "   "), .skip(.noEndpoint))
        XCTAssertFalse(TranscriptDeliveryPolicy.isMisconfiguration(.noEndpoint))
    }

    func testUnusableEndpointWarns() {
        XCTAssertEqual(decide(endpoint: "not a url"), .skip(.invalidEndpoint))
        XCTAssertEqual(decide(endpoint: "/just/a/path"), .skip(.invalidEndpoint))
        XCTAssertTrue(TranscriptDeliveryPolicy.isMisconfiguration(.invalidEndpoint))
    }

    func testPlaintextRemoteEndpointIsRefused() {
        XCTAssertEqual(decide(endpoint: "http://example.com/hook"), .skip(.insecureEndpoint))
        XCTAssertTrue(TranscriptDeliveryPolicy.isMisconfiguration(.insecureEndpoint))
    }

    func testLoopbackOverPlaintextIsAllowed() {
        for host in ["localhost", "127.0.0.1"] {
            XCTAssertEqual(
                decide(endpoint: "http://\(host):8080/hook"),
                .send(endpoint: URL(string: "http://\(host):8080/hook")!),
                "expected \(host) to be allowed over http",
            )
        }
    }

    func testNoTranscriptSkipsQuietly() {
        XCTAssertEqual(decide(hasTranscript: false), .skip(.noTranscript))
        XCTAssertFalse(TranscriptDeliveryPolicy.isMisconfiguration(.noTranscript))
    }

    // MARK: - Payload

    private func job(meetingStart: Date?) -> PipelineJob {
        PipelineJob(
            meetingTitle: "Client call",
            appName: "zoom.us",
            mixPath: nil, appPath: nil, micPath: nil,
            micDelay: 0,
            participants: ["Alice", "Bob"],
            meetingStartTime: meetingStart,
        )
    }

    func testDeliveryCarriesMeetingStart() {
        let start = Date(timeIntervalSince1970: 1_757_160_000)
        let delivery = TranscriptDeliveryPolicy.makeDelivery(
            job: job(meetingStart: start), transcript: "[Alice] hi",
        )
        XCTAssertEqual(delivery.startedAt, "2025-09-06T12:00:00Z")
        XCTAssertEqual(delivery.meetingTitle, "Client call")
        XCTAssertEqual(delivery.appName, "zoom.us")
        XCTAssertEqual(delivery.participants, ["Alice", "Bob"])
        XCTAssertEqual(delivery.transcript, "[Alice] hi")
    }

    func testImportSendsNullStartRatherThanProcessingTime() {
        let delivery = TranscriptDeliveryPolicy.makeDelivery(
            job: job(meetingStart: nil), transcript: "x",
        )
        XCTAssertNil(delivery.startedAt)
        XCTAssertNotNil(delivery.enqueuedAt)
    }

    func testWireFieldNamesAreStable() throws {
        let delivery = TranscriptDeliveryPolicy.makeDelivery(
            job: job(meetingStart: nil), transcript: "x",
        )
        let data = try JSONEncoder().encode(delivery)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        XCTAssertEqual(
            Set(json.keys),
            [
                "jobId", "meetingTitle", "appName", "startedAt", "enqueuedAt",
                "participants", "transcript", "warnings",
            ],
        )
    }
}

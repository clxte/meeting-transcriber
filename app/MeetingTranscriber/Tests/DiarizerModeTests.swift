import Foundation
@testable import MeetingTranscriber
import XCTest

final class DiarizerModeTests: XCTestCase {
    /// `DiarizerMode` is persisted via `PipelineSnapshot` (PipelineJob.usedDiarizerMode)
    /// and via UserDefaults (AppSettings.diarizerMode). The JSON/UserDefaults
    /// shape is keyed off the implicit rawValues `"offline"` / `"sortformer"`
    /// — a future case rename without a stable rawValue would silently break
    /// snapshot decode. This test pins the wire format so any rename forces
    /// an explicit migration decision.
    func testDiarizerModeRawValuesPinJSONShape() throws {
        XCTAssertEqual(DiarizerMode.offline.rawValue, "offline")
        XCTAssertEqual(DiarizerMode.sortformer.rawValue, "sortformer")

        let json = try JSONEncoder().encode([DiarizerMode.offline, .sortformer])
        XCTAssertEqual(String(bytes: json, encoding: .utf8), #"["offline","sortformer"]"#)

        let roundTrip = try JSONDecoder().decode([DiarizerMode].self, from: json)
        XCTAssertEqual(roundTrip, [.offline, .sortformer])
    }

    /// `DiarizerMode.speakerCap` is the single source of truth for the
    /// max-speaker constraint shared by `SpeakersSettingsView` and
    /// `SpeakerNamingView`. Lock the values so a FluidAudio bump that
    /// changes Sortformer's cap will surface here first.
    func testDiarizerModeSpeakerCap() {
        XCTAssertEqual(DiarizerMode.sortformer.speakerCap, 4)
        XCTAssertEqual(DiarizerMode.offline.speakerCap, 10)
    }
}

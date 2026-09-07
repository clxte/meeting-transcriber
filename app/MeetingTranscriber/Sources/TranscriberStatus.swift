/// Matches the JSON status file written by the Python status emitter.
struct TranscriberStatus: Codable {
    let version: Int
    let timestamp: String
    let state: TranscriberState
    let detail: String
    let meeting: MeetingInfo?
    let protocolPath: String?
    let error: String?
    let audioPath: String?
    let pid: Int?

    enum CodingKeys: String, CodingKey {
        case version, timestamp, state, detail, meeting, error, pid
        case protocolPath = "protocol_path"
        case audioPath = "audio_path"
    }
}

enum TranscriberState: String, Codable {
    case idle
    case watching
    case recording
    case transcribing
    case generatingProtocol = "generating_protocol"
    case waitingForSpeakerCount = "waiting_for_speaker_count"
    case waitingForSpeakerNames = "waiting_for_speaker_names"
    case recordingDone = "recording_done"
    case protocolReady = "protocol_ready"
    case error

    var label: String {
        switch self {
        case .idle: String(localized: "Idle")
        case .watching: String(localized: "Watching for Meetings...")
        case .recording: String(localized: "Recording")
        case .transcribing: String(localized: "Transcribing...")
        case .generatingProtocol: String(localized: "Generating Protocol...")
        case .waitingForSpeakerCount: String(localized: "Speaker Count")
        case .waitingForSpeakerNames: String(localized: "Name Speakers")
        case .recordingDone: String(localized: "Transcribing (Native)...")
        case .protocolReady: String(localized: "Protocol Ready")
        case .error: String(localized: "Error")
        }
    }

    var icon: String {
        switch self {
        case .idle: "waveform.circle"
        case .watching: "eye.fill"
        case .recording: "record.circle.fill"
        case .transcribing: "waveform"
        case .generatingProtocol: "waveform"
        case .waitingForSpeakerCount: "person.2.wave.2"
        case .waitingForSpeakerNames: "person.2.fill"
        case .recordingDone: "waveform"
        case .protocolReady: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

struct MeetingInfo: Codable {
    let app: String
    let title: String
    /// The process being recorded, or nil for a microphone-only recording,
    /// which has no owning process. Encodes as an absent key rather than a
    /// sentinel, so a reader cannot mistake it for a real PID.
    let pid: Int?
}

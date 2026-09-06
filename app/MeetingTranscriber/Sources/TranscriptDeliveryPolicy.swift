import Foundation

enum TranscriptDeliveryPolicy {
    enum Decision: Equatable {
        case send(endpoint: URL)
        case skip(Reason)
    }

    enum Reason: Equatable {
        case disabled
        case noEndpoint
        case invalidEndpoint
        case insecureEndpoint
        case noTranscript
    }

    static func isMisconfiguration(_ reason: Reason) -> Bool {
        switch reason {
        case .invalidEndpoint, .insecureEndpoint: true
        case .disabled, .noEndpoint, .noTranscript: false
        }
    }

    static func decide(
        enabled: Bool,
        endpoint rawEndpoint: String,
        hasTranscript: Bool,
    ) -> Decision {
        guard enabled else { return .skip(.disabled) }

        let trimmed = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .skip(.noEndpoint) }
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            return .skip(.invalidEndpoint)
        }
        if TranscriptWebhook.validate(endpoint: url) != nil {
            return .skip(.insecureEndpoint)
        }
        guard hasTranscript else { return .skip(.noTranscript) }
        return .send(endpoint: url)
    }

    static func makeDelivery(job: PipelineJob, transcript: String) -> TranscriptDelivery {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return TranscriptDelivery(
            jobId: job.id.uuidString,
            meetingTitle: job.meetingTitle,
            appName: job.appName,
            startedAt: job.meetingStartTime.map { iso.string(from: $0) },
            enqueuedAt: iso.string(from: job.enqueuedAt),
            participants: job.participants,
            transcript: transcript,
            warnings: job.warnings,
        )
    }
}

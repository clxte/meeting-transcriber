import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "TranscriptDelivery")

extension PipelineController {
    func deliverTranscriptIfConfigured(for job: PipelineJob) {
        let config = transcriptWebhookSettings
        let decision = TranscriptDeliveryPolicy.decide(
            enabled: config.enabled,
            endpoint: config.endpoint,
            hasTranscript: job.transcriptPath != nil,
        )
        guard case let .send(endpoint) = decision else {
            if case let .skip(reason) = decision, TranscriptDeliveryPolicy.isMisconfiguration(reason) {
                logger.warning("Transcript delivery skipped: \(String(describing: reason), privacy: .public)")
                notifyDeliveryProblem(
                    reason == .insecureEndpoint
                        ? "Transcript endpoint must use https"
                        : "Transcript endpoint is not a valid URL",
                )
            }
            return
        }
        guard let transcript = readTranscript(
            at: job.transcriptPath, outputDir: config.outputDir,
        ) else {
            logger.warning("Transcript delivery skipped: file unreadable for \(job.shortID, privacy: .public)")
            return
        }

        let delivery = TranscriptDeliveryPolicy.makeDelivery(job: job, transcript: transcript)
        let webhook = TranscriptWebhook(endpoint: endpoint, token: config.token)
        let title = job.meetingTitle
        Task { [weak self] in
            do {
                try await webhook.send(delivery)
            } catch {
                logger.error("Transcript delivery failed: \(String(describing: error), privacy: .public)")
                self?.notifyDeliveryProblem("Could not send \"\(title)\" to your server")
            }
        }
    }

    private func readTranscript(at path: URL?, outputDir: URL) -> String? {
        guard let path else { return nil }
        let accessing = outputDir.startAccessingSecurityScopedResource()
        defer { if accessing { outputDir.stopAccessingSecurityScopedResource() } }
        return try? String(contentsOf: path, encoding: .utf8)
    }
}

import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "TranscriptWebhook")

struct TranscriptDelivery: Codable, Equatable, Sendable {
    let jobId: String
    let meetingTitle: String
    let appName: String
    let startedAt: String?
    let enqueuedAt: String?
    let participants: [String]
    let transcript: String
    let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case jobId, meetingTitle, appName, startedAt, enqueuedAt
        case participants, transcript, warnings
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobId, forKey: .jobId)
        try container.encode(meetingTitle, forKey: .meetingTitle)
        try container.encode(appName, forKey: .appName)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(enqueuedAt, forKey: .enqueuedAt)
        try container.encode(participants, forKey: .participants)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(warnings, forKey: .warnings)
    }
}

struct TranscriptWebhook: Sendable {
    let endpoint: URL
    let token: String?
    let session: URLSession
    let maxAttempts: Int
    let retryBackoff: Duration

    init(
        endpoint: URL,
        token: String?,
        session: URLSession = .shared,
        maxAttempts: Int = 3,
        retryBackoff: Duration = .seconds(2),
    ) {
        self.endpoint = endpoint
        self.token = token
        self.session = session
        self.maxAttempts = maxAttempts
        self.retryBackoff = retryBackoff
    }

    enum DeliveryError: Error, Equatable {
        case insecureEndpoint
        case httpError(status: Int, body: String)
        case transport(String)
    }

    static func validate(endpoint: URL) -> DeliveryError? {
        let scheme = endpoint.scheme?.lowercased()
        if scheme == "https" { return nil }
        let host = endpoint.host?.lowercased()
        if scheme == "http", host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return nil
        }
        return .insecureEndpoint
    }

    func send(_ delivery: TranscriptDelivery) async throws {
        if let invalid = Self.validate(endpoint: endpoint) { throw invalid }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(delivery)

        var lastError: any Error = DeliveryError.transport("no attempt made")
        for attempt in 1 ... max(1, maxAttempts) {
            do {
                try await postOnce(body: body, idempotencyKey: delivery.jobId)
                logger.info("Transcript delivered for job \(delivery.jobId, privacy: .public) on attempt \(attempt)")
                return
            } catch let error as DeliveryError {
                lastError = error
                guard Self.isRetryable(error), attempt < maxAttempts else { throw error }
                logger.warning(
                    "Transcript delivery attempt \(attempt) failed, retrying: \(String(describing: error), privacy: .public)",
                )
                try? await Task.sleep(for: retryBackoff * Int(pow(4.0, Double(attempt - 1))))
            }
        }
        throw lastError
    }

    static func isRetryable(_ error: DeliveryError) -> Bool {
        switch error {
        case .insecureEndpoint: false
        case .transport: true
        case let .httpError(status, _): status == 429 || status >= 500
        }
    }

    private func postOnce(body: Data, idempotencyKey: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DeliveryError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DeliveryError.transport("non-HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let text = String(data: data.prefix(512), encoding: .utf8) ?? ""
            throw DeliveryError.httpError(status: http.statusCode, body: text)
        }
    }
}

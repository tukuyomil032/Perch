import Foundation

actor ClaudeOAuthUsageClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session

        let dec = JSONDecoder()
        // Support both "2026-06-15T21:30:00Z" and "2026-06-15T21:30:00.000Z"
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = Self.iso8601Fractional.date(from: raw) { return date }
            if let date = Self.iso8601.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date: \(raw)"
            )
        }
        self.decoder = dec
    }

    func fetchUsage(accessToken: String) async throws -> ClaudeLimitUsage {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw ClaudeProviderError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("claude-code/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let err as URLError {
            throw ClaudeProviderError.network(err)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeProviderError.invalidResponse
        }

        switch http.statusCode {
        case 200: break
        case 401: throw ClaudeProviderError.unauthorized
        case 403: throw ClaudeProviderError.forbidden
        case 429: throw ClaudeProviderError.rateLimited
        default: throw ClaudeProviderError.httpStatus(http.statusCode)
        }

        let payload: ClaudeOAuthUsageResponse
        do {
            payload = try decoder.decode(ClaudeOAuthUsageResponse.self, from: data)
        } catch {
            throw ClaudeProviderError.decoding(error)
        }

        return ClaudeLimitUsage(
            session: payload.fiveHour.map { bucket in
                UsageWindow(usedFraction: normalize(bucket.utilization), resetsAt: bucket.resetsAt)
            },
            weekly: payload.sevenDay.map { bucket in
                UsageWindow(usedFraction: normalize(bucket.utilization), resetsAt: bucket.resetsAt)
            },
            routines: payload.sevenDayRoutines.map { bucket in
                UsageWindow(usedFraction: normalize(bucket.utilization), resetsAt: bucket.resetsAt)
            },
            planName: payload.planName
        )
    }

    /// Handles cases where utilization may be expressed as 0–100 instead of 0–1.
    private func normalize(_ value: Double) -> Double {
        let fraction = value > 1 ? value / 100 : value
        return min(1, max(0, fraction))
    }

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

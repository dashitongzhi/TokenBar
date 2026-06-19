import Foundation

struct CodexUsageSnapshot: Equatable {
    var primaryUsedPercent: Double
    var primaryResetAt: Date
    var secondaryUsedPercent: Double?
    var secondaryResetAt: Date?
    var allowed: Bool
    var limitReached: Bool
    var planType: String?
    var fetchedAt: Date
    var history: [UsagePoint]
}

enum CodexUsageRefreshResult: Equatable {
    case success(CodexUsageSnapshot)
    case unavailable(String)
    case failure(String)
}

struct CodexUsageService {
    private let session: URLSession
    private let authURL: URL

    init(
        session: URLSession = .shared,
        authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    ) {
        self.session = session
        self.authURL = authURL
    }

    func refresh() async -> CodexUsageRefreshResult {
        do {
            guard let auth = try loadAuth() else {
                return .unavailable("Codex login quota requires ~/.codex/auth.json from a signed-in Codex session.")
            }
            let response = try await request(auth: auth)
            guard let primary = response.rateLimit.primaryWindow else {
                return .failure("Codex quota refresh failed: response did not include the 5-hour quota window.")
            }
            let now = Date()
            let snapshot = CodexUsageSnapshot(
                primaryUsedPercent: primary.usedPercent,
                primaryResetAt: primary.resetDate(fallback: now),
                secondaryUsedPercent: response.rateLimit.secondaryWindow?.usedPercent,
                secondaryResetAt: response.rateLimit.secondaryWindow?.resetDate(fallback: now),
                allowed: response.rateLimit.allowed ?? true,
                limitReached: response.rateLimit.limitReached ?? false,
                planType: response.planType,
                fetchedAt: now,
                history: [UsagePoint(timestamp: now, value: primary.usedPercent)]
            )
            return .success(snapshot)
        } catch let error as CodexUsageError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure("Codex quota refresh failed: \(error.localizedDescription)")
        }
    }

    private func loadAuth() throws -> CodexAuth? {
        guard FileManager.default.fileExists(atPath: authURL.path) else { return nil }
        let data = try Data(contentsOf: authURL)
        let auth = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        guard let accessToken = auth.tokens.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              accessToken.isEmpty == false else {
            return nil
        }
        let accountID = auth.tokens.accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexAuth(
            accessToken: accessToken,
            accountID: accountID?.isEmpty == false ? accountID : nil
        )
    }

    private func request(auth: CodexAuth) async throws -> CodexUsageResponse {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw CodexUsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex_vscode", forHTTPHeaderField: "originator")
        request.setValue("TokenBar", forHTTPHeaderField: "User-Agent")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexUsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CodexUsageError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }

        return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Codex quota endpoint returned an error without a JSON message."
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String {
            return message
        }
        return "Codex quota endpoint returned an error without a JSON message."
    }
}

private struct CodexAuth {
    var accessToken: String
    var accountID: String?
}

private nonisolated struct CodexAuthFile: Decodable {
    var tokens: CodexAuthTokens
}

private nonisolated struct CodexAuthTokens: Decodable {
    var accessToken: String?
    var accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
    }
}

private nonisolated struct CodexUsageResponse: Decodable {
    var planType: String?
    var rateLimit: CodexRateLimit

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

private nonisolated struct CodexRateLimit: Decodable {
    var allowed: Bool?
    var limitReached: Bool?
    var primaryWindow: CodexRateLimitWindow?
    var secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private nonisolated struct CodexRateLimitWindow: Decodable {
    var usedPercent: Double
    var resetAt: TimeInterval?
    var resetAfterSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case resetAfterSeconds = "reset_after_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeLossyDouble(forKey: .usedPercent)
        resetAt = try? container.decodeLossyDouble(forKey: .resetAt)
        resetAfterSeconds = try? container.decodeLossyDouble(forKey: .resetAfterSeconds)
    }

    func resetDate(fallback: Date) -> Date {
        if let resetAt, resetAt > 0 {
            return Date(timeIntervalSince1970: resetAt)
        }
        if let resetAfterSeconds, resetAfterSeconds > 0 {
            return fallback.addingTimeInterval(resetAfterSeconds)
        }
        return fallback
    }
}

private enum CodexUsageError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Codex quota refresh failed: invalid endpoint URL."
        case .invalidResponse:
            "Codex quota refresh failed: invalid HTTP response."
        case .httpStatus(let status, let message):
            "Codex quota refresh failed with HTTP \(status): \(message)"
        }
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decodeLossyDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decode(String.self, forKey: key), let number = Double(value) {
            return number
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a numeric value.")
    }
}

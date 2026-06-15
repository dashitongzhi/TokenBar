import Foundation

struct OpenRouterCreditsSnapshot: Equatable {
    var totalCredits: Double
    var totalUsage: Double
    var fetchedAt: Date
    var history: [UsagePoint]
}

enum OpenRouterCreditsRefreshResult: Equatable {
    case success(OpenRouterCreditsSnapshot)
    case unavailable(String)
    case failure(String)
}

struct OpenRouterCreditsService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refresh() async -> OpenRouterCreditsRefreshResult {
        guard let apiKey = await openRouterAPIKey() else {
            return .unavailable("Set OPENROUTER_API_KEY in the app environment or save it to TokenBar Keychain to enable live OpenRouter credits.")
        }

        do {
            let response = try await request(OpenRouterCreditsResponse.self, apiKey: apiKey)
            let now = Date()
            let snapshot = OpenRouterCreditsSnapshot(
                totalCredits: response.data.totalCredits,
                totalUsage: response.data.totalUsage,
                fetchedAt: now,
                history: [UsagePoint(timestamp: now, value: response.data.totalUsage)]
            )
            return .success(snapshot)
        } catch let error as OpenRouterCreditsError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure("OpenRouter credits refresh failed: \(error.localizedDescription)")
        }
    }

    private func request<T: Decodable>(_ type: T.Type, apiKey: String) async throws -> T {
        guard let url = URL(string: "https://openrouter.ai/api/v1/credits") else {
            throw OpenRouterCreditsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterCreditsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenRouterCreditsError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func openRouterAPIKey() async -> String? {
        let environment = ProcessInfo.processInfo.environment
        for name in ["OPENROUTER_API_KEY", "TOKENBAR_OPENROUTER_API_KEY", "OPENROUTER_MANAGEMENT_KEY", "TOKENBAR_OPENROUTER_MANAGEMENT_KEY"] {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false {
                return value
            }
        }

        for keyName in [
            "OPENROUTER_API_KEY",
            "TOKENBAR_OPENROUTER_API_KEY",
            "OPENROUTER_MANAGEMENT_KEY",
            "TOKENBAR_OPENROUTER_MANAGEMENT_KEY",
            "openrouter.api_key",
            "openrouter.apiKey",
            "openrouter.management_key",
            "openrouter.managementKey"
        ] {
            if let value = try? await KeychainService.shared.retrieve(key: keyName) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }

        return nil
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "OpenRouter returned an error without a JSON message."
        }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String {
            return message
        }
        return "OpenRouter returned an error without a JSON message."
    }
}

private enum OpenRouterCreditsError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "OpenRouter credits refresh failed: invalid endpoint URL."
        case .invalidResponse:
            "OpenRouter credits refresh failed: invalid HTTP response."
        case .httpStatus(let status, let message):
            "OpenRouter credits refresh failed with HTTP \(status): \(message)"
        }
    }
}

private nonisolated struct OpenRouterCreditsResponse: Decodable {
    var data: OpenRouterCreditsData
}

private nonisolated struct OpenRouterCreditsData: Decodable {
    var totalCredits: Double
    var totalUsage: Double

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCredits = try container.decodeLossyDouble(forKey: .totalCredits)
        totalUsage = try container.decodeLossyDouble(forKey: .totalUsage)
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

import Foundation

struct MiniMaxUsageSnapshot: Equatable {
    static let anthropicBaseURL = "https://api.minimaxi.com/anthropic"

    var modelCount: Int
    var sampleModels: [String]
    var fetchedAt: Date
}

enum MiniMaxUsageRefreshResult: Equatable {
    case success(MiniMaxUsageSnapshot)
    case unavailable(String)
    case failure(String)
}

struct MiniMaxUsageService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refresh() async -> MiniMaxUsageRefreshResult {
        guard let apiKey = await miniMaxAPIKey() else {
            return .unavailable("Set MINIMAX_API_KEY in the app environment or save it to TokenBar Keychain to verify MiniMax Anthropic-compatible access.")
        }

        do {
            let response = try await request(MiniMaxModelsResponse.self, apiKey: apiKey)
            let modelIDs = response.data.compactMap { $0.id }.filter { $0.isEmpty == false }
            return .success(MiniMaxUsageSnapshot(
                modelCount: modelIDs.count,
                sampleModels: Array(modelIDs.prefix(5)),
                fetchedAt: Date()
            ))
        } catch let error as MiniMaxUsageError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure("MiniMax access refresh failed: \(error.localizedDescription)")
        }
    }

    private func request<T: Decodable>(_ type: T.Type, apiKey: String) async throws -> T {
        guard let url = URL(string: "\(MiniMaxUsageSnapshot.anthropicBaseURL)/v1/models") else {
            throw MiniMaxUsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MiniMaxUsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MiniMaxUsageError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func miniMaxAPIKey() async -> String? {
        let environment = ProcessInfo.processInfo.environment
        for name in ["MINIMAX_API_KEY", "TOKENBAR_MINIMAX_API_KEY", "MINIMAX_ANTHROPIC_API_KEY"] {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false {
                return value
            }
        }

        for keyName in [
            "MINIMAX_API_KEY",
            "TOKENBAR_MINIMAX_API_KEY",
            "MINIMAX_ANTHROPIC_API_KEY",
            "minimax.api_key",
            "minimax.apiKey",
            "minimax.anthropic_api_key",
            "minimax.anthropicApiKey"
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
            return "MiniMax returned an error without a JSON message."
        }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String {
            return message
        }
        if let msg = object["msg"] as? String {
            return msg
        }
        return "MiniMax returned an error without a JSON message."
    }
}

private enum MiniMaxUsageError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "MiniMax access refresh failed: invalid endpoint URL."
        case .invalidResponse:
            "MiniMax access refresh failed: invalid HTTP response."
        case .httpStatus(let status, let message):
            "MiniMax access refresh failed with HTTP \(status): \(message)"
        }
    }
}

private struct MiniMaxModelsResponse: Decodable {
    var data: [MiniMaxModel]
}

private struct MiniMaxModel: Decodable {
    var id: String?
}

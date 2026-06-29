import Foundation

enum ProviderModelCatalogResult: Equatable {
    case success([ModelCatalogItem])
    case unavailable(String)
    case failure(String)
}

struct ProviderModelCatalogService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(providerID: String, baseURL: String? = nil, now: Date = .now) async -> ProviderModelCatalogResult {
        let provider = providerID.lowercased()
        let key = await apiKey(for: provider)

        do {
            switch provider {
            case "openai":
                guard let key else { return .unavailable("OpenAI model refresh needs an API key in Keychain or the app environment.") }
                return .success(try await fetchOpenAICompatible(providerID: provider, baseURL: baseURL ?? "https://api.openai.com/v1", apiKey: key, now: now))
            case "anthropic":
                guard let key else { return .unavailable("Anthropic model refresh needs an API key in Keychain or the app environment.") }
                return .success(try await fetchAnthropic(baseURL: baseURL ?? "https://api.anthropic.com/v1", apiKey: key, now: now))
            case "openrouter":
                return .success(try await fetchOpenAICompatible(providerID: provider, baseURL: baseURL ?? "https://openrouter.ai/api/v1", apiKey: key, now: now))
            case "deepseek":
                guard let key else { return .unavailable("DeepSeek model refresh needs an API key in Keychain, the app environment, or CC Switch config.") }
                return .success(try await fetchOpenAICompatible(providerID: provider, baseURL: baseURL ?? "https://api.deepseek.com", apiKey: key, now: now))
            case "mistral":
                guard let key else { return .unavailable("Mistral model refresh needs an API key in Keychain or the app environment.") }
                return .success(try await fetchOpenAICompatible(providerID: provider, baseURL: baseURL ?? "https://api.mistral.ai/v1", apiKey: key, now: now))
            case "google":
                guard let key else { return .unavailable("Gemini model refresh needs an API key in Keychain or the app environment.") }
                return .success(try await fetchGemini(baseURL: baseURL ?? "https://generativelanguage.googleapis.com/v1beta", apiKey: key, now: now))
            case "minimax":
                guard let key else { return .unavailable("MiniMax model refresh needs an API key in Keychain, the app environment, or CC Switch config.") }
                return .success(try await fetchOpenAICompatible(providerID: provider, baseURL: baseURL ?? "https://api.minimax.io/v1", apiKey: key, now: now))
            default:
                guard let baseURL, baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    return .unavailable("Add a Base URL to pull models for this provider.")
                }
                return .success(try await fetchOpenAICompatible(providerID: provider, baseURL: baseURL, apiKey: key, now: now))
            }
        } catch let error as ModelCatalogError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure("Model refresh failed: \(error.localizedDescription)")
        }
    }

    private func fetchOpenAICompatible(providerID: String, baseURL: String, apiKey: String?, now: Date) async throws -> [ModelCatalogItem] {
        let url = try modelsURL(baseURL: baseURL)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, apiKey.isEmpty == false {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let data = try await data(for: request)
        let decoded = try JSONDecoder().decode(FlexibleModelsResponse.self, from: data)
        return decoded.modelIDs.map {
            ModelCatalogItem(providerID: providerID, modelID: $0, displayName: $0, source: .providerAPI, baseURL: normalizedBaseURL(baseURL), configPath: nil, fetchedAt: now)
        }
    }

    private func fetchAnthropic(baseURL: String, apiKey: String, now: Date) async throws -> [ModelCatalogItem] {
        let url = try modelsURL(baseURL: baseURL)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let data = try await data(for: request)
        let decoded = try JSONDecoder().decode(FlexibleModelsResponse.self, from: data)
        return decoded.modelIDs.map {
            ModelCatalogItem(providerID: "anthropic", modelID: $0, displayName: $0, source: .providerAPI, baseURL: normalizedBaseURL(baseURL), configPath: nil, fetchedAt: now)
        }
    }

    private func fetchGemini(baseURL: String, apiKey: String, now: Date) async throws -> [ModelCatalogItem] {
        var components = URLComponents(string: normalizedBaseURL(baseURL) + "/models")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw ModelCatalogError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await data(for: request)
        let decoded = try JSONDecoder().decode(FlexibleModelsResponse.self, from: data)
        return decoded.modelIDs.map {
            ModelCatalogItem(providerID: "google", modelID: $0, displayName: $0.replacingOccurrences(of: "models/", with: ""), source: .providerAPI, baseURL: normalizedBaseURL(baseURL), configPath: nil, fetchedAt: now)
        }
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ModelCatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ModelCatalogError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }
        return data
    }

    private func modelsURL(baseURL: String) throws -> URL {
        let normalized = normalizedBaseURL(baseURL)
        let value = normalized.hasSuffix("/models") ? normalized : normalized + "/models"
        guard let url = URL(string: value) else { throw ModelCatalogError.invalidURL }
        return url
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func apiKey(for providerID: String) async -> String? {
        let env = ProcessInfo.processInfo.environment
        let candidates: [String]
        switch providerID {
        case "openai":
            candidates = ["OPENAI_API_KEY", "OPENAI_ADMIN_KEY"]
        case "anthropic":
            candidates = ["ANTHROPIC_API_KEY", "ANTHROPIC_ADMIN_KEY"]
        case "openrouter":
            candidates = ["OPENROUTER_API_KEY"]
        case "minimax":
            candidates = ["MINIMAX_API_KEY"]
        case "deepseek":
            candidates = ["DEEPSEEK_API_KEY"]
        case "mistral":
            candidates = ["MISTRAL_API_KEY"]
        case "google":
            candidates = ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
        default:
            candidates = []
        }
        for key in candidates {
            if let value = try? await KeychainService.shared.retrieve(key: key), value.isEmpty == false {
                return value
            }
            if let value = env[key], value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "provider returned an error without a JSON message."
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String {
            return message
        }
        return "provider returned an error without a JSON message."
    }
}

private enum ModelCatalogError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Model refresh failed: invalid models endpoint URL."
        case .invalidResponse:
            "Model refresh failed: invalid HTTP response."
        case .httpStatus(let status, let message):
            "Model refresh failed with HTTP \(status): \(message)"
        }
    }
}

private struct FlexibleModelsResponse: Decodable {
    var data: [FlexibleModel]?
    var models: [FlexibleModel]?

    var modelIDs: [String] {
        let ids = (data ?? models ?? []).compactMap(\.id)
        return Array(Set(ids)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

private struct FlexibleModel: Decodable {
    var id: String?
    var name: String?
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName = "display_name"
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let string = try? single.decode(String.self) {
            id = string
            name = nil
            displayName = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id))
            ?? (try? container.decode(String.self, forKey: .name))
            ?? (try? container.decode(String.self, forKey: .displayName))
        name = try? container.decode(String.self, forKey: .name)
        displayName = try? container.decode(String.self, forKey: .displayName)
    }
}

import Foundation

enum ProviderModelCatalogEndpointPolicy {
    static func validatedBaseURL(providerID: String, requestedBaseURL: String?) throws -> String {
        let provider = providerID.lowercased()
        guard let requestedBaseURL, requestedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            guard let defaultBaseURL = defaults[provider] else {
                throw ProviderModelCatalogEndpointError.baseURLRequired
            }
            return defaultBaseURL
        }

        let normalized = requestedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: normalized),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else {
            throw ProviderModelCatalogEndpointError.untrustedBaseURL
        }

        if let expectedHost = officialHosts[provider], host != expectedHost {
            throw ProviderModelCatalogEndpointError.untrustedBaseURL
        }
        return normalized
    }

    private static let defaults = [
        "openai": "https://api.openai.com/v1",
        "anthropic": "https://api.anthropic.com/v1",
        "openrouter": "https://openrouter.ai/api/v1",
        "deepseek": "https://api.deepseek.com",
        "mistral": "https://api.mistral.ai/v1",
        "google": "https://generativelanguage.googleapis.com/v1beta",
        "minimax": "https://api.minimax.io/v1"
    ]

    private static let officialHosts = [
        "openai": "api.openai.com",
        "anthropic": "api.anthropic.com",
        "openrouter": "openrouter.ai",
        "deepseek": "api.deepseek.com",
        "mistral": "api.mistral.ai",
        "google": "generativelanguage.googleapis.com",
        "minimax": "api.minimax.io"
    ]
}

enum ProviderModelCatalogEndpointError: LocalizedError {
    case baseURLRequired
    case untrustedBaseURL

    var errorDescription: String? {
        switch self {
        case .baseURLRequired:
            "Add a Base URL to pull models for this provider."
        case .untrustedBaseURL:
            "Model refresh refused: provider credentials may only be sent to the provider's official HTTPS endpoint."
        }
    }
}

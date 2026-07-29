import Foundation

enum ProviderInference {
    static func providerID(
        explicit: String? = nil,
        model: String? = nil,
        agent: AgentProvider? = nil,
        hints: [String?] = [],
        fallback: String
    ) -> String {
        if let explicit = normalizedAlias(explicit), explicit.isEmpty == false {
            return explicit
        }
        for hint in hints {
            if let provider = knownProviderID(in: hint) {
                return provider
            }
        }
        if let provider = knownProviderID(in: model) {
            return provider
        }
        switch agent {
        case .claudeCode: return "anthropic"
        case .codex: return "openai"
        default: return normalizedAlias(fallback) ?? "openai"
        }
    }

    static func model(_ model: String?, providerID: String) -> String {
        let value = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty {
            switch providerID {
            case "anthropic": return "claude-sonnet"
            case "openai": return "gpt-5"
            case "minimax": return "minimax-m1"
            case "deepseek": return "deepseek-chat"
            case "google": return "gemini-2.5-pro"
            case "mistral": return "mistral-large-latest"
            case "kimi": return "kimi-k2"
            case "glm": return "glm-4.5"
            default: return "unspecified"
            }
        }
        return value
    }

    static func knownProviderID(in value: String?) -> String? {
        guard let value else { return nil }
        let tokens = Set(value.lowercased().split { $0.isLetter == false && $0.isNumber == false })
        let mappings: [(Set<Substring>, String)] = [
            (["anthropic", "claude"], "anthropic"),
            (["openrouter"], "openrouter"),
            (["minimax", "minimaxi"], "minimax"),
            (["deepseek"], "deepseek"),
            (["mimo", "xiaomi"], "xiaomi-mimo"),
            (["gemini", "google"], "google"),
            (["mistral"], "mistral"),
            (["kimi"], "kimi"),
            (["glm"], "glm"),
            (["qwen"], "qwen"),
            (["openai", "gpt", "o1", "o3", "o4"], "openai"),
        ]
        return mappings.first { $0.0.isDisjoint(with: tokens) == false }?.1
    }

    private static func normalizedAlias(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.replacingOccurrences(of: "_", with: "-")
    }
}

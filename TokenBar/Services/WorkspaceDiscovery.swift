import Foundation

struct DiscoveredKey: Identifiable, Hashable {
    var id = UUID()
    var provider: String
    var variableName: String
    var file: String
    var line: Int
}

actor WorkspaceDiscovery {
    private let patterns: [String: [String]] = [
        "OpenAI": ["OPENAI_API_KEY", "OPENAI_KEY"],
        "Anthropic": ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"],
        "Stripe": ["STRIPE_SECRET_KEY", "STRIPE_API_KEY"],
        "OpenRouter": ["OPENROUTER_API_KEY"],
        "DeepSeek": ["DEEPSEEK_API_KEY"],
        "Mistral": ["MISTRAL_API_KEY"]
    ]

    func scan(paths: [URL]) async -> [DiscoveredKey] {
        var discovered: [DiscoveredKey] = []
        for url in paths {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            for (offset, line) in lines.enumerated() {
                for (provider, names) in patterns where names.contains(where: { line.contains($0) }) {
                    let variable = names.first(where: { line.contains($0) }) ?? provider
                    discovered.append(DiscoveredKey(provider: provider, variableName: variable, file: url.path, line: offset + 1))
                }
            }
        }
        return discovered
    }
}

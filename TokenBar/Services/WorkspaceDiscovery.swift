import Foundation

struct DiscoveredKey: Identifiable, Sendable {
    var id: String { "\(provider)-\(variableName)-\(sourceLabel)-\(line)" }
    var provider: String
    var variableName: String
    var sourceLabel: String
    var line: Int
    var secretValue: String

    var locationSummary: String {
        "\(sourceLabel), line \(line)"
    }
}

struct DiscoveryTarget: Identifiable, Hashable, Sendable {
    var id: String { "\(url.path)-\(sourceLabel)" }
    var url: URL
    var sourceLabel: String
}

actor WorkspaceDiscovery {
    private let patterns: [String: [String]] = [
        "OpenAI": ["OPENAI_API_KEY", "OPENAI_KEY", "OPENAI_ADMIN_KEY", "TOKENBAR_OPENAI_ADMIN_KEY"],
        "Anthropic": ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY", "ANTHROPIC_ADMIN_KEY", "TOKENBAR_ANTHROPIC_ADMIN_KEY"],
        "Gemini": ["GEMINI_API_KEY", "GOOGLE_API_KEY"],
        "GitHub": ["GITHUB_TOKEN", "GH_TOKEN"],
        "Stripe": ["STRIPE_SECRET_KEY", "STRIPE_API_KEY"],
        "OpenRouter": ["OPENROUTER_API_KEY", "TOKENBAR_OPENROUTER_API_KEY", "OPENROUTER_MANAGEMENT_KEY", "TOKENBAR_OPENROUTER_MANAGEMENT_KEY"],
        "DeepSeek": ["DEEPSEEK_API_KEY"],
        "Mistral": ["MISTRAL_API_KEY"],
        "Cloudflare": ["CLOUDFLARE_API_TOKEN", "CF_API_TOKEN"],
        "Vercel": ["VERCEL_TOKEN"],
        "Supabase": ["SUPABASE_ACCESS_TOKEN", "SUPABASE_SERVICE_ROLE_KEY"],
        "Groq": ["GROQ_API_KEY"]
    ]

    func scan(targets: [DiscoveryTarget]) async -> [DiscoveredKey] {
        var discovered: [DiscoveredKey] = []
        var seenIDs = Set<String>()
        for target in targets {
            guard let content = try? String(contentsOf: target.url, encoding: .utf8) else { continue }
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            for (offset, line) in lines.enumerated() {
                let text = String(line)
                guard text.trimmingCharacters(in: .whitespaces).hasPrefix("#") == false else { continue }

                for (provider, names) in patterns {
                    guard let match = names.compactMap({ variable -> (String, String)? in
                        guard let value = environmentValue(named: variable, in: text), value.isEmpty == false else { return nil }
                        return (variable, value)
                    }).first else { continue }
                    let lineNumber = offset + 1
                    let keyID = "\(provider)-\(match.0)-\(target.sourceLabel)-\(lineNumber)"
                    guard seenIDs.insert(keyID).inserted else { continue }

                    let key = DiscoveredKey(
                        provider: provider,
                        variableName: match.0,
                        sourceLabel: target.sourceLabel,
                        line: lineNumber,
                        secretValue: match.1
                    )
                    discovered.append(key)
                }
            }
        }
        return discovered.sorted {
            if $0.provider == $1.provider {
                return $0.variableName < $1.variableName
            }
            return $0.provider < $1.provider
        }
    }

    private func environmentValue(named variable: String, in line: String) -> String? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("export ") {
            trimmed.removeFirst("export ".count)
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        }

        guard trimmed.hasPrefix(variable) else { return nil }
        var remainder = String(trimmed.dropFirst(variable.count)).trimmingCharacters(in: .whitespaces)
        guard remainder.hasPrefix("=") else { return nil }
        remainder.removeFirst()
        var value = remainder.trimmingCharacters(in: .whitespaces)

        if let quote = value.first, quote == "\"" || quote == "'" {
            value.removeFirst()
            if let closingQuote = value.firstIndex(of: quote) {
                return String(value[..<closingQuote])
            }
            return value
        }

        if let commentStart = value.range(of: " #")?.lowerBound {
            value = String(value[..<commentStart]).trimmingCharacters(in: .whitespaces)
        }

        return value
    }
}

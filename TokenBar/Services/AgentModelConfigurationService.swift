import Foundation

struct AgentModelConfigurationService {
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        homeDirectory = UserHomeDirectory.url
    }

    func readConfiguredModels(now: Date = .now) -> [ModelUsageRollup] {
        var rows: [ModelUsageRollup] = []
        rows.append(contentsOf: readCodexConfig(now: now))
        rows.append(contentsOf: readClaudeConfig(now: now))
        return deduplicated(rows)
    }

    func readConfiguredModelCatalogItems(now: Date = .now) -> [ModelCatalogItem] {
        readConfiguredModels(now: now).map { row in
            ModelCatalogItem(
                providerID: row.providerID,
                modelID: row.model,
                displayName: row.model,
                source: .localAgentConfig,
                baseURL: nil,
                configPath: row.configPath,
                fetchedAt: now
            )
        }
    }

    static func inferWorkspacePolicy(
        configuredRows: [ModelUsageRollup],
        catalogItems: [ModelCatalogItem],
        fallbackPath: String
    ) -> WorkspacePolicyInference {
        let signals = configuredRows.map { row in
            InferenceSignal(
                agent: row.agent,
                providerID: policyProviderID(row.providerID),
                model: row.model,
                sourcePath: row.configPath,
                rank: row.agent == .codex ? 0 : (row.agent == .claudeCode ? 1 : 2)
            )
        } + catalogItems.map { item in
            InferenceSignal(
                agent: nil,
                providerID: policyProviderID(item.providerID),
                model: item.modelID,
                sourcePath: item.configPath,
                rank: item.source == .ccSwitchConfig ? 3 : 4
            )
        }
        let usableSignals = signals.filter { $0.providerID.isEmpty == false && $0.model.isEmpty == false }
        let preferred = usableSignals.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.model.localizedStandardCompare(rhs.model) == .orderedAscending
        }.first
        let providerIDs = orderedUnique(
            usableSignals.map(\.providerID) + (preferred.map { [$0.providerID] } ?? [])
        )
        let fallbackProviderIDs = ["openai", "anthropic", "openrouter"]
        let allowedProviderIDs = providerIDs.isEmpty ? fallbackProviderIDs : providerIDs
        let preferredProviderID = preferred?.providerID ?? allowedProviderIDs.first ?? "openai"
        let preferredModel = preferred?.model ?? "unspecified"
        let maxEstimatedRunCost = preferred.map { _ in
            defaultPerRunCap(providerID: preferredProviderID, model: preferredModel)
        } ?? 0
        let paths = orderedUnique(
            usableSignals.compactMap(\.sourcePath).filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        )
        let sourceDetail: String
        if paths.isEmpty {
            sourceDetail = "Default local policy. No Codex, Claude, or CC Switch model configuration was found yet."
        } else {
            let agentNames = orderedUnique(usableSignals.compactMap { $0.agent?.displayName })
            let sourceNames = agentNames.isEmpty ? "local agent config" : agentNames.joined(separator: ", ")
            sourceDetail = "Inferred from \(sourceNames) and local model configuration."
        }

        return WorkspacePolicyInference(
            allowedProviderIDs: allowedProviderIDs,
            preferredProviderID: preferredProviderID,
            preferredModel: preferredModel,
            maxEstimatedRunCost: maxEstimatedRunCost,
            setupSourceDetail: sourceDetail,
            configuredModelCount: usableSignals.count,
            inferredFromPaths: paths.isEmpty ? [fallbackPath] : paths
        )
    }

    private func readCodexConfig(now: Date) -> [ModelUsageRollup] {
        let url = homeDirectory.appendingPathComponent(".codex/config.toml")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let topLevel = topLevelTOMLValues(in: content)
        guard let model = topLevel["model"], model.isEmpty == false else { return [] }

        let providerHint = topLevel["model_provider"] ?? topLevel["modelProvider"]
        let providerConfig = providerHint.flatMap { tomlTableValues(in: content, path: ["model_providers", $0]) }
        let providerContext = ProviderContext(
            hint: providerHint,
            name: providerConfig?["name"],
            baseURL: providerConfig?["base_url"] ?? providerConfig?["baseURL"]
        )
        return [
            configuredRow(
                agent: .codex,
                providerID: providerID(model: model, context: providerContext, fallback: providerHint ?? "openai"),
                model: model,
                path: url.path,
                now: fileModificationDate(url) ?? now
            )
        ]
    }

    private func readClaudeConfig(now: Date) -> [ModelUsageRollup] {
        let urls = [
            homeDirectory.appendingPathComponent(".claude/settings.json"),
            homeDirectory.appendingPathComponent(".claude/config.json")
        ]

        return urls.flatMap { url -> [ModelUsageRollup] in
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                return []
            }

            let models = modelStrings(in: object)
            let updatedAt = fileModificationDate(url) ?? now
            return models.map { model in
                configuredRow(
                    agent: .claudeCode,
                    providerID: providerID(model: model, context: ProviderContext(hint: nil, name: nil, baseURL: nil), fallback: "anthropic"),
                    model: model,
                    path: url.path,
                    now: updatedAt
                )
            }
        }
    }

    private func configuredRow(agent: AgentProvider, providerID: String, model: String, path: String, now: Date) -> ModelUsageRollup {
        ModelUsageRollup(
            agent: agent,
            providerID: providerID,
            model: model,
            source: .configured,
            configPath: path,
            spendToday: 0,
            spendMonth: 0,
            tokensToday: 0,
            tokensMonth: 0,
            requestCountToday: 0,
            requestCountMonth: 0,
            dayKey: dayKey(for: now),
            monthKey: monthKey(for: now),
            lastUpdated: now
        )
    }

    private func topLevelTOMLValues(in content: String) -> [String: String] {
        var values: [String: String] = [:]
        var isTopLevel = true

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") {
                isTopLevel = false
                continue
            }
            guard isTopLevel, let separator = trimmed.firstIndex(of: "=") else { continue }

            let key = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if key.isEmpty == false && value.isEmpty == false {
                values[key] = value
            }
        }

        return values
    }

    private func tomlTableValues(in content: String, path: [String]) -> [String: String] {
        let target = path.joined(separator: ".")
        var values: [String: String] = [:]
        var inTarget = false

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let section = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                inTarget = section == target
                continue
            }
            guard inTarget, let separator = trimmed.firstIndex(of: "=") else { continue }

            let key = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if key.isEmpty == false && value.isEmpty == false {
                values[key] = value
            }
        }

        return values
    }

    private func modelStrings(in value: Any) -> [String] {
        var models: [String] = []

        func walk(_ value: Any, parentKey: String?) {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
                    if let string = child as? String,
                       ["model", "modelid", "modelname"].contains(normalized),
                       looksLikeModel(string) {
                        models.append(string)
                    }
                    if normalized == "env", let env = child as? [String: Any] {
                        for (envKey, envValue) in env {
                            guard let string = envValue as? String else { continue }
                            let normalizedEnvKey = envKey.uppercased()
                            if ["ANTHROPIC_MODEL", "CLAUDE_MODEL", "OPENAI_MODEL", "CODEX_MODEL"].contains(normalizedEnvKey),
                               looksLikeModel(string) {
                                models.append(string)
                            }
                        }
                    }
                    walk(child, parentKey: key)
                }
            } else if let array = value as? [Any] {
                for child in array {
                    walk(child, parentKey: parentKey)
                }
            }
        }

        walk(value, parentKey: nil)
        return Array(Set(models)).sorted()
    }

    private func looksLikeModel(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count >= 2, normalized.count <= 120 else { return false }
        return normalized.contains("claude") ||
            normalized.contains("gpt") ||
            normalized.contains("o3") ||
            normalized.contains("o4") ||
            normalized.contains("gemini") ||
            normalized.contains("deepseek") ||
            normalized.contains("minimax") ||
            normalized.contains("mistral") ||
            normalized.contains("kimi")
    }

    private func providerID(model: String, context: ProviderContext, fallback: String) -> String {
        for hint in [context.hint, context.name, context.baseURL] {
            if let known = knownProviderID(from: hint) {
                return known
            }
        }

        let normalized = model.lowercased()
        if normalized.contains("claude") { return "anthropic" }
        if normalized.contains("gpt") || normalized.contains("o1") || normalized.contains("o3") || normalized.contains("o4") { return "openai" }
        if normalized.contains("minimax") { return "minimax" }
        if normalized.contains("deepseek") { return "deepseek" }
        if normalized.contains("gemini") { return "google" }
        if normalized.contains("mistral") { return "mistral" }
        if normalized.contains("kimi") { return "kimi" }
        if normalized.contains("mimo") || normalized.contains("xiaomi") { return "xiaomi-mimo" }
        if normalized.contains("glm") { return "glm" }
        if normalized.contains("qwen") { return "qwen" }
        return normalizedProviderAlias(fallback)
    }

    private func knownProviderID(from value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.lowercased()
        if normalized.contains("anthropic") || normalized.contains("claude") { return "anthropic" }
        if normalized.contains("openrouter") { return "openrouter" }
        if normalized.contains("minimax") || normalized.contains("mini-max") || normalized.contains("minimaxi") { return "minimax" }
        if normalized.contains("deepseek") { return "deepseek" }
        if normalized.contains("mimo") || normalized.contains("xiaomi") { return "xiaomi-mimo" }
        if normalized.contains("gemini") || normalized.contains("google") { return "google" }
        if normalized.contains("mistral") { return "mistral" }
        if normalized.contains("kimi") { return "kimi" }
        if normalized.contains("glm") { return "glm" }
        if normalized.contains("qwen") { return "qwen" }
        if normalized.contains("openai") { return "openai" }
        if normalized.contains("kral") || normalized.contains("kralai") { return "kral" }
        return nil
    }

    private func normalizedProviderAlias(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { return "openai" }
        return normalized.replacingOccurrences(of: "_", with: "-")
    }

    private func deduplicated(_ rows: [ModelUsageRollup]) -> [ModelUsageRollup] {
        var seen = Set<String>()
        return rows.filter { row in
            let key = [row.agent.rawValue, row.providerID, row.model.lowercased(), row.configPath ?? ""].joined(separator: "|")
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }

    private func fileModificationDate(_ url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    private func dayKey(for date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func monthKey(for date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private struct InferenceSignal {
        var agent: AgentProvider?
        var providerID: String
        var model: String
        var sourcePath: String?
        var rank: Int
    }

    private struct ProviderContext {
        var hint: String?
        var name: String?
        var baseURL: String?
    }

    private static func policyProviderID(_ providerID: String) -> String {
        switch providerID {
        case "codex", "ccswitch-codex":
            return "openai"
        default:
            return providerID
        }
    }

    private static func defaultModel(providerID: String) -> String {
        switch providerID {
        case "anthropic": "claude-sonnet"
        case "openai": "gpt-5"
        case "minimax": "minimax-m1"
        case "deepseek": "deepseek-chat"
        case "google": "gemini-2.5-pro"
        case "mistral": "mistral-large-latest"
        case "kimi": "kimi-k2"
        case "glm": "glm-4.5"
        default: "unspecified"
        }
    }

    private static func defaultPerRunCap(providerID: String, model: String) -> Double {
        let normalized = "\(providerID) \(model)".lowercased()
        if normalized.contains("pro") || normalized.contains("opus") {
            return 2.50
        }
        if normalized.contains("mini") || normalized.contains("haiku") ||
            normalized.contains("deepseek") || normalized.contains("minimax") ||
            normalized.contains("kimi") || normalized.contains("glm") {
            return 0.75
        }
        return 1.50
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, seen.contains(trimmed) == false else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }
}

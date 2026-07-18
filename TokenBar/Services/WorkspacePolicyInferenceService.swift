import Foundation

enum WorkspacePolicyInferenceService {
    static func infer(
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
        let providerIDs = orderedUnique(usableSignals.map(\.providerID) + (preferred.map { [$0.providerID] } ?? []))
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

    private static func policyProviderID(_ providerID: String) -> String {
        switch providerID {
        case "codex", "ccswitch-codex": "openai"
        default: providerID
        }
    }

    private static func defaultPerRunCap(providerID: String, model: String) -> Double {
        let normalized = "\(providerID) \(model)".lowercased()
        if normalized.contains("pro") || normalized.contains("opus") { return 2.50 }
        if normalized.contains("mini") || normalized.contains("haiku") ||
            normalized.contains("deepseek") || normalized.contains("minimax") ||
            normalized.contains("kimi") || normalized.contains("glm") {
            return 0.75
        }
        return 1.50
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private struct InferenceSignal {
        var agent: AgentProvider?
        var providerID: String
        var model: String
        var sourcePath: String?
        var rank: Int
    }
}

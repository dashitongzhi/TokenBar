import Foundation

struct SmartRoutingContext {
    var input: PolicyEvaluationInput
    var workspacePolicies: [WorkspacePolicy]
    var selectedWorkspace: WorkspacePolicy?
    var providers: [ProviderUsage]
    var modelUsageRollups: [ModelUsageRollup]
    var modelCatalogItems: [ModelCatalogItem]
    var stats: SmartRoutingStatsSnapshot
    var projectedSessionSpend: Double
    var sessionBudget: Double
    var fallbackProviderID: String
}

struct SmartRoutingRecommender {
    func recommendation(for context: SmartRoutingContext) -> SmartRoutingRecommendation? {
        let workspace = context.workspacePolicies.first { $0.id == context.input.workspaceID }
            ?? context.selectedWorkspace
        let scored = candidates(context: context, workspace: workspace).compactMap { candidate -> ScoredCandidate? in
            let route = bestRouteStats(for: candidate, intent: context.input.intent, stats: context.stats.routeStats)
            guard let candidateInput = policyInput(
                for: candidate,
                baseInput: context.input,
                route: route,
                workspace: workspace
            ) else {
                return nil
            }
            let decision = PolicyEngine.evaluate(
                input: candidateInput,
                workspaces: context.workspacePolicies,
                selectedWorkspace: context.selectedWorkspace,
                providers: context.providers,
                projectedSessionSpend: context.projectedSessionSpend - context.input.estimatedCost + candidateInput.estimatedCost,
                sessionBudget: context.sessionBudget
            )
            guard decision.status != .block else { return nil }
            return ScoredCandidate(
                candidate: candidate,
                score: score(candidate: candidate, route: route, providers: context.providers),
                route: route,
                estimatedCost: candidateInput.estimatedCost
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if ($0.route?.runCount ?? 0) != ($1.route?.runCount ?? 0) {
                return ($0.route?.runCount ?? 0) > ($1.route?.runCount ?? 0)
            }
            return $0.candidate.model.localizedStandardCompare($1.candidate.model) == .orderedAscending
        }

        guard let best = scored.first else { return nil }
        let runCount = best.route?.runCount ?? 0
        let winRate = best.route?.winRate ?? 0
        let alternatives = scored.dropFirst().prefix(3).map { "\($0.candidate.providerID)/\($0.candidate.model)" }
        let reason: String
        if let route = best.route, route.runCount > 0 {
            reason = "Based on \(route.runCount) recorded \(route.taskIntent) runs with \(Int(route.winRate * 100))% win rate."
        } else if best.candidate.sourceRank <= 1 {
            reason = "Based on configured local agent models and current policy constraints."
        } else {
            reason = "Based on the current selected route and provider health."
        }

        return SmartRoutingRecommendation(
            providerID: best.candidate.providerID,
            model: best.candidate.model,
            taskIntent: context.input.intent,
            confidence: min(max(best.score, 0.1), 0.95),
            evidenceRunCount: runCount,
            winRate: winRate,
            estimatedCost: best.estimatedCost,
            reason: reason,
            alternatives: alternatives
        )
    }

    private func policyInput(
        for candidate: Candidate,
        baseInput: PolicyEvaluationInput,
        route: SmartRoutingRouteStats?,
        workspace: WorkspacePolicy?
    ) -> PolicyEvaluationInput? {
        guard candidate.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              candidate.model != "unspecified" else {
            return nil
        }
        let cost = estimatedCost(candidate: candidate, route: route, baseInput: baseInput)
        if cost == nil, (workspace?.maxEstimatedRunCost ?? 0) > 0 { return nil }
        var input = baseInput
        input.providerID = candidate.providerID
        input.model = candidate.model
        input.estimatedCost = cost ?? 0
        return input
    }

    private func candidates(context: SmartRoutingContext, workspace: WorkspacePolicy?) -> [Candidate] {
        var values: [Candidate] = []
        func add(providerID: String?, model: String?, sourceRank: Int) {
            let provider = normalizedProviderID(
                providerID,
                model: model,
                agent: context.input.agent,
                fallback: context.fallbackProviderID
            )
            let model = normalizedModel(model, providerID: provider)
            guard model != "unspecified" else { return }
            values.append(Candidate(providerID: provider, model: model, sourceRank: sourceRank))
        }

        add(providerID: context.input.providerID, model: context.input.model, sourceRank: 2)
        add(providerID: workspace?.preferredProviderID, model: workspace?.preferredModel, sourceRank: 0)
        for row in context.modelUsageRollups {
            add(providerID: row.providerID, model: row.model, sourceRank: row.source == .localAgent ? 0 : 1)
        }
        for item in context.modelCatalogItems {
            add(providerID: item.providerID, model: item.modelID, sourceRank: item.source == .localAgentConfig ? 1 : 2)
        }
        for route in context.stats.routeStats.prefix(30) {
            add(providerID: route.providerID, model: route.model, sourceRank: 0)
        }

        var seen = Set<String>()
        return values.filter { candidate in
            let key = "\(candidate.providerID)|\(candidate.model.lowercased())"
            guard seen.insert(key).inserted else { return false }
            return true
        }
    }

    private func bestRouteStats(
        for candidate: Candidate,
        intent: String,
        stats: [SmartRoutingRouteStats]
    ) -> SmartRoutingRouteStats? {
        stats
            .filter {
                $0.providerID == candidate.providerID
                    && $0.model.caseInsensitiveCompare(candidate.model) == .orderedSame
            }
            .sorted {
                let lhsExact = $0.taskIntent.caseInsensitiveCompare(intent) == .orderedSame
                let rhsExact = $1.taskIntent.caseInsensitiveCompare(intent) == .orderedSame
                if lhsExact != rhsExact { return lhsExact }
                if $0.runCount != $1.runCount { return $0.runCount > $1.runCount }
                return $0.winRate > $1.winRate
            }
            .first
    }

    private func score(candidate: Candidate, route: SmartRoutingRouteStats?, providers: [ProviderUsage]) -> Double {
        var score = max(0.1, 0.35 - Double(candidate.sourceRank) * 0.07)
        if let route {
            score = 0.35 + route.winRate * 0.45
                + min(Double(route.runCount) / 10, 1) * 0.15
                - route.followUpRate * 0.2
        }
        if let provider = providers.first(where: { $0.id == candidate.providerID }) {
            switch provider.status {
            case .healthy: score += 0.08
            case .warning: score -= 0.04
            case .critical: score -= 0.16
            }
        }
        return score
    }

    private func estimatedCost(
        candidate: Candidate,
        route: SmartRoutingRouteStats?,
        baseInput: PolicyEvaluationInput
    ) -> Double? {
        if let route, route.actualCostKnownRunCount > 0, route.actualCostTotal > 0 {
            return route.actualCostTotal / Double(route.actualCostKnownRunCount)
        }
        if candidate.providerID == baseInput.providerID,
           candidate.model.caseInsensitiveCompare(baseInput.model) == .orderedSame {
            return baseInput.estimatedCost
        }
        return nil
    }

    private func normalizedProviderID(
        _ providerID: String?,
        model: String?,
        agent: AgentProvider?,
        fallback: String
    ) -> String {
        let provider = providerID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let provider, provider.isEmpty == false { return provider }
        let model = model?.lowercased() ?? ""
        if model.contains("claude") { return "anthropic" }
        if model.contains("gpt") || model.contains("o1") || model.contains("o3") || model.contains("o4") { return "openai" }
        if model.contains("minimax") { return "minimax" }
        if model.contains("deepseek") { return "deepseek" }
        if model.contains("gemini") { return "google" }
        if model.contains("mistral") { return "mistral" }
        if model.contains("kimi") { return "kimi" }
        if model.contains("mimo") || model.contains("xiaomi") { return "xiaomi-mimo" }
        if model.contains("glm") { return "glm" }
        if model.contains("qwen") { return "qwen" }
        switch agent {
        case .claudeCode: return "anthropic"
        case .codex: return "openai"
        default: return fallback
        }
    }

    private func normalizedModel(_ model: String?, providerID: String) -> String {
        let value = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty == false { return value }
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
}

private struct Candidate {
    var providerID: String
    var model: String
    var sourceRank: Int
}

private struct ScoredCandidate {
    var candidate: Candidate
    var score: Double
    var route: SmartRoutingRouteStats?
    var estimatedCost: Double
}

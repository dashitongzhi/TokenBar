import Foundation

struct LocalUsageIngestionOutcome {
    var snapshot: LocalAgentUsageAppliedSnapshot
    var providers: [ProviderUsage]
    var workspacePolicies: [WorkspacePolicy]
    var sessionSpend: Double
    var modelUsageRollups: [ModelUsageRollup]
    var audit: ProviderRefreshAudit
}

struct LocalUsageIngestionModule {
    private let ledgerStore = LocalAgentUsageLedgerStore()
    private let modelUsageStore = LocalModelUsageStore()

    func loadModelUsageRollups(now: Date = .now) -> [ModelUsageRollup] {
        modelUsageStore.load(now: now)
    }

    func ingest(
        _ input: LocalAgentUsageIngest,
        providers: [ProviderUsage],
        workspacePolicies: [WorkspacePolicy],
        selectedWorkspaceID: String,
        selectedProviderID: String,
        sessionBudget: Double,
        sessionSpend: Double
    ) -> LocalUsageIngestionOutcome {
        let now = input.occurredAt ?? .now
        let providerID = normalizedProviderID(
            input.providerID,
            model: input.model,
            agent: input.agent,
            fallback: selectedProviderID
        )
        let agent = input.agent ?? AgentProvider.defaultAgent(forProviderID: providerID)
        let model = normalizedModel(input.model, providerID: providerID)
        var updatedPolicies = workspacePolicies
        let workspaceID = upsertWorkspacePolicy(
            from: input,
            providerID: providerID,
            selectedWorkspaceID: selectedWorkspaceID,
            policies: &updatedPolicies
        )
        for index in updatedPolicies.indices {
            _ = updatedPolicies[index].resetExpiredSpendBuckets(now: now)
        }
        var updatedProviders = providers
        ensureProvider(providerID, providers: &updatedProviders)

        let contextTokenTotal = Double(input.totalTokens ?? ((input.inputTokens ?? 0) + (input.outputTokens ?? 0)))
        let cumulativeCost = max(input.costUSD ?? 0, 0)
        let cumulativeRequests = max(input.requestCount ?? 0, 0)
        let sessionKey = localUsageSessionKey(
            input: input,
            agent: agent,
            providerID: providerID,
            model: model,
            workspaceID: workspaceID
        )
        let delta = (input.cumulative ?? true)
            ? ledgerStore.apply(
                sessionKey: sessionKey,
                cumulativeCost: cumulativeCost,
                cumulativeTokens: contextTokenTotal,
                cumulativeRequestCount: cumulativeRequests,
                now: now
            )
            : LocalAgentUsageDelta(
                costUSD: cumulativeCost,
                tokens: contextTokenTotal,
                requestCount: cumulativeRequests
            )
        let snapshot = LocalAgentUsageAppliedSnapshot(
            agent: agent,
            providerID: providerID,
            model: model,
            workspaceID: workspaceID,
            sessionKey: sessionKey,
            sourceName: input.source ?? "local_agent",
            costDelta: delta.costUSD,
            tokenDelta: delta.tokens,
            requestDelta: delta.requestCount,
            contextTokenTotal: contextTokenTotal,
            contextWindowSize: input.contextWindowSize.map(Double.init),
            rateLimitUsedPercentage: input.rateLimitUsedPercentage,
            rateLimitResetAt: input.rateLimitResetAt,
            occurredAt: now,
            sourceDetail: sourceDetail(
                input: input,
                providerID: providerID,
                costDelta: delta.costUSD,
                tokenDelta: delta.tokens
            )
        )

        if let index = updatedProviders.firstIndex(where: { $0.id == providerID }) {
            updatedProviders[index].apply(localUsage: snapshot)
        }
        if let workspaceID, let index = updatedPolicies.firstIndex(where: { $0.id == workspaceID }) {
            updatedPolicies[index].spendToday += delta.costUSD
            updatedPolicies[index].spendMonth += delta.costUSD
        }
        let updatedSessionSpend = sessionBudget > 0 ? sessionSpend + delta.costUSD : sessionSpend
        return LocalUsageIngestionOutcome(
            snapshot: snapshot,
            providers: updatedProviders,
            workspacePolicies: updatedPolicies,
            sessionSpend: updatedSessionSpend,
            modelUsageRollups: modelUsageStore.apply(snapshot: snapshot),
            audit: ProviderRefreshAudit(
                provider: agent.displayName,
                action: "usage.local",
                detail: "\(model) · \(providerID) · +$\(money(delta.costUSD)) · +\(Int(delta.tokens)) tokens"
            )
        )
    }

    private func upsertWorkspacePolicy(
        from input: LocalAgentUsageIngest,
        providerID: String,
        selectedWorkspaceID: String,
        policies: inout [WorkspacePolicy]
    ) -> String? {
        let workspaceID = input.workspaceID
            ?? workspaceIDMatching(path: input.currentDirectory ?? input.workspacePath, policies: policies)
        guard let workspaceID, workspaceID.isEmpty == false else { return selectedWorkspaceID }

        if let index = policies.firstIndex(where: { $0.id == workspaceID }) {
            policies[index].name = input.workspaceName ?? policies[index].name
            policies[index].pathHint = input.workspacePath ?? input.currentDirectory ?? policies[index].pathHint
            policies[index].client = input.workspaceClient ?? policies[index].client
            policies[index].dailyBudget = input.dailyBudget ?? policies[index].dailyBudget
            policies[index].monthlyBudget = input.monthlyBudget ?? policies[index].monthlyBudget
            policies[index].maxEstimatedRunCost = input.maxEstimatedRunCost ?? policies[index].maxEstimatedRunCost
            policies[index].maxEstimatedTokens = input.maxEstimatedTokens ?? policies[index].maxEstimatedTokens
            policies[index].allowedProviderIDs = input.allowedProviderIDs ?? policies[index].allowedProviderIDs
            policies[index].blockedModels = input.blockedModels ?? policies[index].blockedModels
            policies[index].requireCompanyKey = input.requireCompanyKey ?? policies[index].requireCompanyKey
            policies[index].preferredProviderID = policies[index].preferredProviderID ?? providerID
            policies[index].preferredModel = policies[index].preferredModel ?? normalizedModel(input.model, providerID: providerID)
        } else {
            var allowed = ["anthropic", "openai", "openrouter"]
            if allowed.contains(providerID) == false { allowed.append(providerID) }
            policies.append(WorkspacePolicy(
                id: workspaceID,
                name: input.workspaceName ?? title(workspaceID),
                pathHint: input.workspacePath ?? input.currentDirectory ?? "~",
                client: input.workspaceClient ?? "local",
                dailyBudget: input.dailyBudget ?? 0,
                monthlyBudget: input.monthlyBudget ?? 0,
                spendToday: 0,
                spendMonth: 0,
                allowedProviderIDs: input.allowedProviderIDs ?? allowed,
                blockedModels: input.blockedModels ?? [],
                maxEstimatedRunCost: input.maxEstimatedRunCost ?? 0,
                maxEstimatedTokens: input.maxEstimatedTokens ?? 0,
                requireCompanyKey: input.requireCompanyKey ?? false,
                preferredProviderID: providerID,
                preferredModel: normalizedModel(input.model, providerID: providerID),
                setupSourceDetail: "Created from local agent usage ingestion.",
                configuredModelCount: nil,
                inferredFromPaths: [input.transcriptPath, input.currentDirectory].compactMap { $0 }
            ))
        }
        return workspaceID
    }

    private func ensureProvider(_ providerID: String, providers: inout [ProviderUsage]) {
        guard providers.contains(where: { $0.id == providerID }) == false else { return }
        if let seed = AppSeedData.providers().first(where: { $0.id == providerID }) {
            let order = AppSeedData.providers().firstIndex(where: { $0.id == providerID }) ?? providers.count
            providers.insert(seed, at: min(order, providers.count))
            return
        }
        providers.append(AppSeedData.provider(
            id: providerID,
            name: title(providerID),
            category: "AI & API",
            symbol: "network",
            current: 0,
            limit: 0,
            unit: "tokens",
            spendToday: 0,
            spendMonth: 0,
            resetHours: 24 * 30,
            dataSource: .localAgent,
            sourceDetail: "Local agent usage was ingested through TokenBar's local API."
        ))
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

    private func localUsageSessionKey(
        input: LocalAgentUsageIngest,
        agent: AgentProvider,
        providerID: String,
        model: String,
        workspaceID: String?
    ) -> String {
        if let sessionID = input.sessionID, sessionID.isEmpty == false { return sessionID }
        if let transcriptPath = input.transcriptPath, transcriptPath.isEmpty == false { return transcriptPath }
        return [agent.rawValue, providerID, model, workspaceID ?? "workspace", input.currentDirectory ?? ""]
            .joined(separator: "|")
    }

    private func workspaceIDMatching(path: String?, policies: [WorkspacePolicy]) -> String? {
        guard let path, path.isEmpty == false else { return nil }
        let expanded = NSString(string: path).expandingTildeInPath
        return policies.first { policy in
            let policyPath = NSString(string: policy.pathHint).expandingTildeInPath
            return expanded.hasPrefix(policyPath) || policyPath.hasPrefix(expanded)
        }?.id
    }

    private func sourceDetail(
        input: LocalAgentUsageIngest,
        providerID: String,
        costDelta: Double,
        tokenDelta: Double
    ) -> String {
        let source = input.source ?? "local agent"
        var parts = ["\(source) usage ingested locally for \(providerID)."]
        if input.contextWindowSize != nil {
            parts.append("Context tokens are from the local session; provider billing still belongs to the provider console.")
        } else {
            parts.append("Token and cost totals are local agent data, not a provider-admin usage API.")
        }
        parts.append("Applied +$\(money(costDelta)) and +\(Int(tokenDelta)) tokens after session de-duplication.")
        if let rateLimit = input.rateLimitUsedPercentage {
            parts.append("Reported rate-limit use: \(Int(rateLimit))%.")
        }
        return parts.joined(separator: " ")
    }

    private func title(_ value: String) -> String {
        let words = value.replacingOccurrences(of: "_", with: "-").split(separator: "-")
        guard words.isEmpty == false else { return "Workspace" }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

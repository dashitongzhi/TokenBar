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
        sessionSpend: Double,
        receivedAt: Date = .now
    ) -> LocalUsageIngestionOutcome {
        let occurredAt = trustedOccurredAt(input.occurredAt, receivedAt: receivedAt)
        let providerID = ProviderInference.providerID(
            explicit: input.providerID,
            model: input.model,
            agent: input.agent,
            fallback: selectedProviderID
        )
        let agent = input.agent ?? AgentProvider.defaultAgent(forProviderID: providerID)
        let model = ProviderInference.model(input.model, providerID: providerID)
        var updatedPolicies = workspacePolicies
        let workspaceID = resolvedWorkspacePolicyID(
            from: input,
            selectedWorkspaceID: selectedWorkspaceID,
            policies: updatedPolicies
        )
        for index in updatedPolicies.indices {
            _ = updatedPolicies[index].resetExpiredSpendBuckets(now: receivedAt)
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
                now: receivedAt
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
            occurredAt: occurredAt,
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

    private func resolvedWorkspacePolicyID(
        from input: LocalAgentUsageIngest,
        selectedWorkspaceID: String,
        policies: [WorkspacePolicy]
    ) -> String? {
        if let requestedID = input.workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           requestedID.isEmpty == false {
            return policies.contains(where: { $0.id == requestedID }) ? requestedID : nil
        }
        if let matched = workspaceIDMatching(
            path: input.currentDirectory ?? input.workspacePath,
            policies: policies
        ) {
            return matched
        }
        return policies.contains(where: { $0.id == selectedWorkspaceID })
            ? selectedWorkspaceID
            : nil
    }

    private func trustedOccurredAt(_ candidate: Date?, receivedAt: Date) -> Date {
        guard let candidate,
              abs(candidate.timeIntervalSince(receivedAt)) <= 5 * 60
        else {
            return receivedAt
        }
        return candidate
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
        let candidateURL = normalizedFileURL(path)
        let homeURL = normalizedFileURL(NSHomeDirectory())
        return policies
            .compactMap { policy -> (policy: WorkspacePolicy, components: Int)? in
                let policyURL = normalizedFileURL(policy.pathHint)
                guard policyURL.path != homeURL.path || policyURL.path == candidateURL.path else {
                    return nil
                }
                let policyComponents = policyURL.pathComponents
                let candidateComponents = candidateURL.pathComponents
                guard candidateComponents.count >= policyComponents.count,
                      Array(candidateComponents.prefix(policyComponents.count)) == policyComponents
                else {
                    return nil
                }
                return (policy, policyComponents.count)
            }
            .max { $0.components < $1.components }?
            .policy.id
    }

    private func normalizedFileURL(_ path: String) -> URL {
        URL(
            fileURLWithPath: NSString(string: path).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL
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
        guard words.isEmpty == false else { return "Provider" }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

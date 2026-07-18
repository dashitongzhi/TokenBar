import Foundation

@MainActor
extension AppState {
    func policyJSON() throws -> Data {
        normalizeWorkspaceSpendBuckets()
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
        return try LocalAPIPayloadBuilder.policyJSON(currentDecision: currentDecision, workspacePolicies: workspacePolicies)
    }

    func policyDecisionJSON(input: PolicyEvaluationInput) throws -> Data {
        var verifiedInput = input
        verifiedInput.keySource = nil
        normalizeWorkspaceSpendBuckets()
        let transientWorkspacePolicies = workspacePoliciesForPolicyEvaluation(verifiedInput)
        let decision = evaluatePolicy(input: verifiedInput, shouldRecord: false, workspacePolicies: transientWorkspacePolicies)
        currentDecision = decision
        return try LocalAPIPayloadBuilder.policyDecisionJSON(decision)
    }

    func ingestLocalAgentUsageJSON(input: LocalAgentUsageIngest) throws -> Data {
        let snapshot = applyLocalAgentUsage(input)
        let policyInput = PolicyEvaluationInput(
            agent: snapshot.agent,
            workspaceID: snapshot.workspaceID ?? selectedWorkspaceID,
            providerID: snapshot.providerID,
            model: snapshot.model,
            estimatedCost: 0,
            estimatedTokens: Int(snapshot.tokenDelta),
            intent: "local_usage_ingest"
        )
        currentDecision = evaluatePolicy(input: policyInput, shouldRecord: false)
        return try LocalAPIPayloadBuilder.localAgentUsageJSON(snapshot: snapshot, decision: currentDecision)
    }

    func ingestClaudeStatuslineJSON(data: Data) throws -> Data {
        guard let input = ClaudeStatuslineParser.parse(data) else {
            return Data(#"{"error":"invalid_claude_statusline_input"}"#.utf8)
        }
        return try ingestLocalAgentUsageJSON(input: input)
    }

    func recordSmartRoutingRunJSON(input: SmartRoutingRunInput) throws -> Data {
        let record = smartRoutingLedgerStore.record(input, fallbackWorkspaceID: selectedWorkspaceID, fallbackAgent: selectedAgent)
        addAudit(
            provider: record.agent.displayName,
            action: "routing.\(record.signal.rawValue)",
            detail: "\(record.taskIntent) · \(record.providerID)/\(record.model) · $\(formatMoney(record.actualCost))"
        )
        return try LocalAPIPayloadBuilder.smartRoutingRunJSON(record: record)
    }

    func smartRoutingStatsJSON() throws -> Data {
        try LocalAPIPayloadBuilder.smartRoutingStatsJSON(snapshot: smartRoutingLedgerStore.stats())
    }

    func mcpSnapshotJSON(filteredProviderID: String? = nil) throws -> Data {
        try LocalAPIPayloadBuilder.mcpSnapshotJSON(providers: providers, filteredProviderID: filteredProviderID)
    }

    func paceJSON(providerID: String) throws -> Data {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return Data(#"{"error":"provider_not_found"}"#.utf8)
        }
        return try LocalAPIPayloadBuilder.paceJSON(provider: provider, recommendation: insightText())
    }

    private func applyLocalAgentUsage(_ input: LocalAgentUsageIngest) -> LocalAgentUsageAppliedSnapshot {
        let outcome = localUsageIngestionModule.ingest(
            input,
            providers: providers,
            workspacePolicies: workspacePolicies,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedProviderID: selectedProviderID,
            sessionBudget: sessionBudget,
            sessionSpend: sessionSpend
        )
        providers = outcome.providers
        workspacePolicies = outcome.workspacePolicies
        sessionSpend = outcome.sessionSpend
        addAudit(provider: outcome.audit.provider, action: outcome.audit.action, detail: outcome.audit.detail)
        mergeModelUsageRollups(outcome.modelUsageRollups)
        persistProviders()
        persistWorkspacePolicies()
        notifyStatusBarUpdate()
        return outcome.snapshot
    }
}

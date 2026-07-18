import Foundation

@MainActor
extension AppState {
    func resetSessionBudget() {
        sessionSpend = 0
        focusModeEnabled = true
        addAudit(provider: localized("focusMode"), action: "budget.reset", detail: "Session budget meter reset")
        notifyStatusBarUpdate()
    }

    func runPolicyCheck() {
        rebuildPolicyInput()
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: true)
        notifyStatusBarUpdate()
    }

    func evaluatePolicy(
        input: PolicyEvaluationInput,
        shouldRecord: Bool = true,
        workspacePolicies evaluationWorkspacePolicies: [WorkspacePolicy]? = nil
    ) -> PolicyDecision {
        normalizeWorkspaceSpendBuckets()
        let activeWorkspacePolicies = evaluationWorkspacePolicies ?? workspacePolicies
        var decision = PolicyEngine.evaluate(
            input: input,
            workspaces: activeWorkspacePolicies,
            selectedWorkspace: selectedWorkspace,
            providers: providers,
            projectedSessionSpend: sessionSpend + input.estimatedCost,
            sessionBudget: sessionBudget
        )
        decision.routingMode = routingMode
        if routingMode == .smartRouting {
            applySmartRoutingRecommendation(to: &decision, input: input, workspacePolicies: activeWorkspacePolicies)
        }

        if shouldRecord {
            recentDecisions.insert(decision, at: 0)
            if recentDecisions.count > 20 {
                recentDecisions.removeLast(recentDecisions.count - 20)
            }
            addAudit(provider: input.agent.displayName, action: "policy.\(decision.status.rawValue)", detail: "\(decision.workspaceName) · \(input.model) · $\(formatMoney(input.estimatedCost))")
        }
        return decision
    }

    func updateWorkspaceMaxEstimatedRunCost(id: String, value: Double) {
        guard value.isFinite else { return }
        var updated = workspacePolicies
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].maxEstimatedRunCost = max(value, 0.01)
        workspacePolicies = updated
        persistWorkspacePolicies()
        rebuildPolicyInput()
        notifyStatusBarUpdate()
    }

    func adjustWorkspaceMaxEstimatedRunCost(id: String, delta: Double) {
        guard let workspace = workspacePolicies.first(where: { $0.id == id }) else { return }
        updateWorkspaceMaxEstimatedRunCost(id: id, value: workspace.maxEstimatedRunCost + delta)
    }

    @discardableResult
    func normalizeWorkspaceSpendBuckets(now: Date = .now) -> Bool {
        var normalized = workspacePolicies
        var changed = false
        for index in normalized.indices {
            let didReset = normalized[index].resetExpiredSpendBuckets(now: now)
            changed = didReset || changed
        }
        guard changed else { return false }
        workspacePolicies = normalized
        persistWorkspacePolicies()
        return true
    }

    func rebuildPolicyInput() {
        currentPolicyInput = PolicyEvaluationInput(
            agent: selectedAgent,
            workspaceID: selectedWorkspaceID,
            providerID: selectedProviderID,
            model: selectedModel,
            estimatedCost: estimatedRunCost,
            estimatedTokens: Int(estimatedTokens),
            intent: "agent-run"
        )
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
    }

    func workspacePoliciesForPolicyEvaluation(_ input: PolicyEvaluationInput) -> [WorkspacePolicy] {
        guard input.hasTransientWorkspacePolicyFields else { return workspacePolicies }

        var evaluationWorkspacePolicies = workspacePolicies
        if let index = workspacePolicies.firstIndex(where: { $0.id == input.workspaceID }) {
            evaluationWorkspacePolicies[index].name = input.workspaceName ?? evaluationWorkspacePolicies[index].name
            evaluationWorkspacePolicies[index].pathHint = input.workspacePath ?? evaluationWorkspacePolicies[index].pathHint
            evaluationWorkspacePolicies[index].client = input.workspaceClient ?? evaluationWorkspacePolicies[index].client
            evaluationWorkspacePolicies[index].dailyBudget = input.dailyBudget ?? evaluationWorkspacePolicies[index].dailyBudget
            evaluationWorkspacePolicies[index].monthlyBudget = input.monthlyBudget ?? evaluationWorkspacePolicies[index].monthlyBudget
            evaluationWorkspacePolicies[index].maxEstimatedRunCost = input.maxEstimatedRunCost ?? evaluationWorkspacePolicies[index].maxEstimatedRunCost
            evaluationWorkspacePolicies[index].maxEstimatedTokens = input.maxEstimatedTokens ?? evaluationWorkspacePolicies[index].maxEstimatedTokens
            evaluationWorkspacePolicies[index].allowedProviderIDs = input.allowedProviderIDs ?? evaluationWorkspacePolicies[index].allowedProviderIDs
            evaluationWorkspacePolicies[index].blockedModels = input.blockedModels ?? evaluationWorkspacePolicies[index].blockedModels
            evaluationWorkspacePolicies[index].requireCompanyKey = input.requireCompanyKey ?? evaluationWorkspacePolicies[index].requireCompanyKey
            evaluationWorkspacePolicies[index].preferredProviderID = input.preferredProviderID ?? input.providerID
            evaluationWorkspacePolicies[index].preferredModel = input.preferredModel ?? input.model
            evaluationWorkspacePolicies[index].setupSourceDetail = evaluationWorkspacePolicies[index].setupSourceDetail ?? "Evaluated from tokenbar.yml via local policy check."
        } else {
            evaluationWorkspacePolicies.append(WorkspacePolicy(
                id: input.workspaceID,
                name: input.workspaceName ?? titleFromWorkspaceID(input.workspaceID),
                pathHint: input.workspacePath ?? "~",
                client: input.workspaceClient ?? "local",
                dailyBudget: input.dailyBudget ?? 0,
                monthlyBudget: input.monthlyBudget ?? 0,
                spendToday: 0,
                spendMonth: 0,
                allowedProviderIDs: input.allowedProviderIDs ?? [input.providerID],
                blockedModels: input.blockedModels ?? [],
                maxEstimatedRunCost: input.maxEstimatedRunCost ?? 0,
                maxEstimatedTokens: input.maxEstimatedTokens ?? 0,
                requireCompanyKey: input.requireCompanyKey ?? false,
                preferredProviderID: input.preferredProviderID ?? input.providerID,
                preferredModel: input.preferredModel ?? input.model,
                setupSourceDetail: "Evaluated from tokenbar.yml via local policy check.",
                configuredModelCount: nil,
                inferredFromPaths: [input.workspacePath].compactMap { $0 }
            ))
        }
        return evaluationWorkspacePolicies
    }

    func titleFromWorkspaceID(_ value: String) -> String {
        let words = value.replacingOccurrences(of: "_", with: "-").split(separator: "-")
        guard words.isEmpty == false else { return "Workspace" }
        return words.map { word in word.prefix(1).uppercased() + word.dropFirst() }.joined(separator: " ")
    }

    private func applySmartRoutingRecommendation(
        to decision: inout PolicyDecision,
        input: PolicyEvaluationInput,
        workspacePolicies evaluationWorkspacePolicies: [WorkspacePolicy]
    ) {
        guard let recommendation = smartRoutingRecommender.recommendation(for: SmartRoutingContext(
            input: input,
            workspacePolicies: evaluationWorkspacePolicies,
            selectedWorkspace: selectedWorkspace,
            providers: providers,
            modelUsageRollups: modelUsageRollups,
            modelCatalogItems: modelCatalogItems,
            stats: smartRoutingLedgerStore.stats(),
            projectedSessionSpend: sessionSpend + input.estimatedCost,
            sessionBudget: sessionBudget,
            fallbackProviderID: selectedProviderID
        )) else {
            decision.reasons.append("Smart Routing is enabled, but no eligible model route is available yet.")
            return
        }

        decision.smartRoutingRecommendation = recommendation
        let routeLabel = "\(providerDisplayName(recommendation.providerID)) / \(recommendation.model)"
        if decision.status == .block {
            decision.reasons.append("Smart Routing found \(routeLabel), but the guard policy still blocks this run.")
            return
        }
        if recommendation.providerID != input.providerID || recommendation.model != input.model {
            decision.reasons.append("Smart Routing recommends \(routeLabel).")
            decision.recommendation = "Smart Routing recommends \(routeLabel). \(recommendation.reason)"
        } else {
            decision.reasons.append("Smart Routing agrees with the selected route.")
        }
    }

    private func providerDisplayName(_ providerID: String) -> String {
        providers.first { $0.id == providerID }?.name ?? providerID
    }
}

private extension PolicyEvaluationInput {
    var hasTransientWorkspacePolicyFields: Bool {
        allowedProviderIDs != nil || blockedModels != nil || dailyBudget != nil || monthlyBudget != nil ||
            maxEstimatedRunCost != nil || maxEstimatedTokens != nil || requireCompanyKey != nil ||
            workspaceName != nil || workspacePath != nil || preferredProviderID != nil || preferredModel != nil
    }
}

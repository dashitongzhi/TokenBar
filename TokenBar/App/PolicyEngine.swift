import Foundation

struct PolicyEngine {
    static func evaluate(
        input: PolicyEvaluationInput,
        workspaces: [WorkspacePolicy],
        selectedWorkspace: WorkspacePolicy?,
        providers: [ProviderUsage],
        projectedSessionSpend: Double,
        sessionBudget: Double
    ) -> PolicyDecision {
        let workspace = workspaces.first { $0.id == input.workspaceID }
            ?? selectedWorkspace
            ?? WorkspacePolicy(
                id: "local-workspace",
                name: "Local Workspace",
                pathHint: "~",
                client: "local",
                dailyBudget: 0,
                monthlyBudget: 0,
                spendToday: 0,
                spendMonth: 0,
                allowedProviderIDs: [input.providerID],
                blockedModels: [],
                maxEstimatedRunCost: 0,
                requireCompanyKey: false
            )
        let provider = providers.first { $0.id == input.providerID }
        let projectedDailySpend = workspace.spendToday + input.estimatedCost
        let modelIsUnspecified = input.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || input.model == "unspecified"
        var status: PolicyDecisionStatus = .allow
        var reasons: [String] = []

        if workspace.allowedProviderIDs.contains(input.providerID) == false {
            status = .block
            reasons.append("Provider is not allowed for this workspace.")
        }

        if workspace.blockedModels.contains(where: { input.model.localizedCaseInsensitiveContains($0) }) {
            status = .block
            reasons.append("Model is blocked by the workspace policy.")
        }

        if workspace.maxEstimatedRunCost > 0 && input.estimatedCost > workspace.maxEstimatedRunCost {
            status = .block
            reasons.append("Estimated run cost is above the per-run cap.")
        }

        if workspace.requireCompanyKey && companyKeyRequiredButUnsatisfied(input) {
            status = .block
            reasons.append("Workspace requires a company-managed key.")
        }

        if workspace.dailyBudget > 0 && projectedDailySpend >= workspace.dailyBudget {
            status = .block
            reasons.append("Projected daily spend would exceed the workspace budget.")
        } else if workspace.dailyBudget > 0 && projectedDailySpend >= workspace.dailyBudget * 0.8 && status != .block {
            status = .warn
            reasons.append("Projected daily spend is close to the workspace budget.")
        }

        if let provider, provider.status == .critical && status != .block {
            status = .warn
            reasons.append("\(provider.name) is near its quota or reset window.")
        }

        if sessionBudget > 0 && projectedSessionSpend >= sessionBudget && status != .block {
            status = .warn
            reasons.append("Current session budget will be tight after this run.")
        }

        if modelIsUnspecified && status != .block {
            status = .warn
            reasons.append("No model has been selected yet.")
        }

        if reasons.isEmpty {
            reasons.append("Workspace, provider, model, and budget are inside policy.")
        }

        let fallback = workspace.allowedProviderIDs.first { $0 != input.providerID }
        let recommendation: String
        switch status {
        case .allow:
            recommendation = "Continue with \(input.model). Keep the agent on this workspace policy."
        case .warn:
            if modelIsUnspecified {
                recommendation = "Select a configured model before running an agent."
            } else {
                recommendation = "Continue only if this run is necessary, or switch to \(fallbackName(fallback, providers: providers)) first."
            }
        case .block:
            recommendation = "Stop this run. Switch provider/model or raise the workspace budget after review."
        }

        return PolicyDecision(
            timestamp: .now,
            status: status,
            agent: input.agent,
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            providerID: input.providerID,
            model: input.model,
            estimatedCost: input.estimatedCost,
            projectedDailySpend: projectedDailySpend,
            reasons: reasons,
            recommendation: recommendation,
            fallbackProviderID: fallback
        )
    }

    private static func fallbackName(_ providerID: String?, providers: [ProviderUsage]) -> String {
        guard let providerID, let provider = providers.first(where: { $0.id == providerID }) else {
            return "a cheaper allowed provider"
        }
        return provider.name
    }

    private static func companyKeyRequiredButUnsatisfied(_ input: PolicyEvaluationInput) -> Bool {
        guard input.providerID == "openai" else { return false }
        return companyManagedKeySources.contains(normalizedKeySource(input.keySource)) == false
    }

    private static let companyManagedKeySources: Set<String> = [
        "company",
        "company_managed",
        "managed",
        "codex_managed",
        "tokenbar_keychain",
        "tokenbar",
        "api_proxy",
        "org",
        "workspace"
    ]

    private static func normalizedKeySource(_ source: String?) -> String {
        (source ?? "").lowercased().replacingOccurrences(of: "-", with: "_")
    }
}

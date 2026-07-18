import Foundation

#if canImport(TokenBar)
@testable import TokenBar
#endif

struct PolicyContractVerificationResult {
    var verifiedCases: Int
    var failures: [String]
}

enum PolicyContractFixtureVerifier {
    static func verify(fixtureURL: URL) throws -> PolicyContractVerificationResult {
        let data = try Data(contentsOf: fixtureURL)
        guard let fixture = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VerificationError.invalidFixture("root must be a JSON object")
        }

        let defaults = dictionary(fixture["defaults"])
        let defaultInput = dictionary(defaults["input"])
        let defaultConfig = dictionary(defaults["config"])
        let managedSources = stringArray(fixture["companyManagedKeySources"])
        let cases = fixture["cases"] as? [[String: Any]] ?? []
        var failures: [String] = []
        var verifiedCases = 0

        for contractCase in cases {
            let caseID = string(contractCase["id"], fallback: "unnamed")
            let input = deepMerge(defaultInput, dictionary(contractCase["input"]))
            let config = deepMerge(defaultConfig, dictionary(contractCase["config"]))
            let expected = dictionary(contractCase["expected"])
            let configuredKeySource = optionalString(input["keySource"])
            let keySourceVariants: [String?] = configuredKeySource == "$companyManagedKeySource"
                ? managedSources.map(Optional.some)
                : [configuredKeySource]

            for keySource in keySourceVariants {
                var variantInput = input
                variantInput["keySource"] = keySource ?? NSNull()
                let suffix = configuredKeySource == "$companyManagedKeySource" ? ":\(keySource ?? "nil")" : ""
                let decision = evaluate(input: variantInput, config: config)
                verify(caseID: caseID + suffix, decision: decision, expected: expected, failures: &failures)
                verifiedCases += 1
            }
        }

        return PolicyContractVerificationResult(verifiedCases: verifiedCases, failures: failures)
    }

    private static func evaluate(input: [String: Any], config: [String: Any]) -> PolicyDecision {
        let workspaceConfig = dictionary(config["workspace"])
        let budgets = dictionary(config["budgets"])
        let rules = dictionary(config["rules"])
        let providers = dictionary(config["providers"])
        let models = dictionary(config["models"])
        let providerID = string(input["providerID"], fallback: "openai")

        let policyInput = PolicyEvaluationInput(
            agent: AgentProvider(rawValue: string(input["agent"], fallback: "custom")) ?? .custom,
            workspaceID: string(input["workspaceID"], fallback: "policy-contract"),
            providerID: providerID,
            model: string(input["model"], fallback: "unspecified"),
            estimatedCost: double(input["estimatedCost"]),
            estimatedTokens: integer(input["estimatedTokens"]),
            keySource: optionalString(input["keySource"]),
            intent: string(input["intent"], fallback: "policy-contract")
        )
        let workspace = WorkspacePolicy(
            id: string(workspaceConfig["id"], fallback: policyInput.workspaceID),
            name: string(workspaceConfig["name"], fallback: "Policy Contract"),
            pathHint: "~",
            client: "contract",
            dailyBudget: double(budgets["daily"]),
            monthlyBudget: double(budgets["monthly"]),
            spendToday: double(budgets["spend_today"]),
            spendMonth: double(budgets["spend_month"]),
            allowedProviderIDs: stringArray(providers["allowed"]),
            blockedModels: stringArray(models["blocked"]),
            maxEstimatedRunCost: double(budgets["max_run"]),
            maxEstimatedTokens: integer(rules["max_estimated_tokens"]),
            requireCompanyKey: boolean(providers["require_company_key"]),
            preferredProviderID: optionalString(providers["preferred"]),
            preferredModel: optionalString(models["default"])
        )

        return PolicyEngine.evaluate(
            input: policyInput,
            workspaces: [workspace],
            selectedWorkspace: workspace,
            providers: [],
            projectedSessionSpend: 0,
            sessionBudget: 0
        )
    }

    private static func verify(
        caseID: String,
        decision: PolicyDecision,
        expected: [String: Any],
        failures: inout [String]
    ) {
        let expectedStatus = string(expected["status"], fallback: "")
        if decision.status.rawValue != expectedStatus {
            failures.append("\(caseID): status=\(decision.status.rawValue), expected=\(expectedStatus)")
        }
        for reason in stringArray(expected["reasonsInclude"]) where decision.reasons.contains(reason) == false {
            failures.append("\(caseID): missing reason \(reason)")
        }
        for reason in stringArray(expected["reasonsExclude"]) where decision.reasons.contains(reason) {
            failures.append("\(caseID): unexpected reason \(reason)")
        }
        verifyNumber("projectedDailySpend", actual: decision.projectedDailySpend, expected: expected, caseID: caseID, failures: &failures)
        verifyNumber("projectedMonthlySpend", actual: decision.projectedMonthlySpend, expected: expected, caseID: caseID, failures: &failures)
    }

    private static func verifyNumber(
        _ key: String,
        actual: Double,
        expected: [String: Any],
        caseID: String,
        failures: inout [String]
    ) {
        guard expected[key] != nil else { return }
        let expectedValue = double(expected[key])
        if abs(actual - expectedValue) > 0.000_001 {
            failures.append("\(caseID): \(key)=\(actual), expected=\(expectedValue)")
        }
    }

    private static func deepMerge(_ base: [String: Any], _ override: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in override {
            if let left = result[key] as? [String: Any], let right = value as? [String: Any] {
                result[key] = deepMerge(left, right)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private static func string(_ value: Any?, fallback: String) -> String {
        optionalString(value) ?? fallback
    }

    private static func optionalString(_ value: Any?) -> String? {
        guard let value, value is NSNull == false else { return nil }
        return value as? String
    }

    private static func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func double(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }

    private static func integer(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func boolean(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    enum VerificationError: Error {
        case invalidFixture(String)
    }
}

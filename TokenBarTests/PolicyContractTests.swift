import XCTest
@testable import TokenBar

final class PolicyContractTests: XCTestCase {
    func testSwiftPolicyEngineMatchesSharedRubyContract() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot.appendingPathComponent("script/fixtures/policy_contract.json")
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixtureObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        let expectedCases = try XCTUnwrap(fixtureObject["cases"] as? [[String: Any]])
        let managedSources = try XCTUnwrap(fixtureObject["companyManagedKeySources"] as? [String])
        let expectedVariants = expectedCases.reduce(into: 0) { count, contractCase in
            let input = contractCase["input"] as? [String: Any]
            count += input?["keySource"] as? String == "$companyManagedKeySource"
                ? managedSources.count
                : 1
        }

        let result = try PolicyContractFixtureVerifier.verify(fixtureURL: fixtureURL)

        XCTAssertEqual(result.verifiedCases, expectedVariants)
        XCTAssertTrue(result.failures.isEmpty, result.failures.joined(separator: "\n"))
    }

    func testWorkspaceSpendBucketsResetAtCalendarBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 14 * 60 * 60)!
        let initial = calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 31, hour: 23
        ))!
        let nextDay = calendar.date(byAdding: .hour, value: 2, to: initial)!

        var policy = workspacePolicy()
        XCTAssertTrue(policy.resetExpiredSpendBuckets(now: initial, calendar: calendar))
        policy.spendToday = 9
        policy.spendMonth = 19

        XCTAssertTrue(policy.resetExpiredSpendBuckets(now: nextDay, calendar: calendar))
        XCTAssertEqual(policy.spendToday, 0)
        XCTAssertEqual(policy.spendMonth, 0)
        XCTAssertEqual(policy.spendDayKey, "2026-02-01")
        XCTAssertEqual(policy.spendMonthKey, "2026-02")
    }

    func testProviderUsageBurnRatePredictionAndSeverity() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var usage = providerUsage(
            current: 95,
            limit: 100,
            history: [
                UsagePoint(timestamp: start, value: 80),
                UsagePoint(timestamp: start.addingTimeInterval(2 * 3_600), value: 90),
            ]
        )

        XCTAssertEqual(usage.burnRatePerHour, 5, accuracy: 0.0001)
        XCTAssertNotNil(usage.predictedExhaustion)
        XCTAssertEqual(usage.status, .critical)

        usage.current = 75
        usage.history = []
        XCTAssertEqual(usage.status, .warning)
    }

    func testLocalizationDictionariesHaveIdenticalKeys() {
        XCTAssertTrue(
            L10n.hasMatchingLanguageKeys,
            "Missing zh: \(L10n.missingChineseKeys); missing en: \(L10n.missingEnglishKeys)"
        )
    }

    func testProviderInferenceUsesTokenBoundariesAndOneDefaultCatalog() {
        XCTAssertEqual(
            ProviderInference.providerID(model: "gpt-5.1-codex", fallback: "custom"),
            "openai"
        )
        XCTAssertEqual(
            ProviderInference.providerID(model: "claude-sonnet-4", fallback: "custom"),
            "anthropic"
        )
        XCTAssertEqual(
            ProviderInference.providerID(model: "neo4j-agent", fallback: "custom"),
            "custom"
        )
        XCTAssertEqual(
            ProviderInference.providerID(model: "solar-pro1", fallback: "custom"),
            "custom"
        )
        XCTAssertEqual(ProviderInference.model(nil, providerID: "google"), "gemini-2.5-pro")
    }

    func testLegacyPolicyDecisionDefaultsMissingRoutingMode() throws {
        let decision = PolicyDecision(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            status: .allow,
            agent: .codex,
            workspaceID: "legacy",
            workspaceName: "Legacy Workspace",
            providerID: "openai",
            model: "gpt-5",
            estimatedCost: 0.25,
            projectedDailySpend: 1,
            projectedMonthlySpend: 4,
            reasons: ["Legacy payload"],
            recommendation: "Continue",
            fallbackProviderID: nil
        )
        let encoded = try JSONEncoder.tokenBar.encode(decision)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "routingMode")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

        let decoded = try JSONDecoder.tokenBar.decode(PolicyDecision.self, from: legacyData)

        XCTAssertEqual(decoded.routingMode, .guardOnly)
        XCTAssertEqual(decoded.workspaceID, decision.workspaceID)
        XCTAssertEqual(decoded.recommendation, decision.recommendation)
    }

    private func workspacePolicy() -> WorkspacePolicy {
        WorkspacePolicy(
            id: "test",
            name: "Test",
            pathHint: "/tmp/test",
            client: "codex",
            dailyBudget: 10,
            monthlyBudget: 100,
            spendToday: 5,
            spendMonth: 50,
            allowedProviderIDs: ["openai"],
            blockedModels: [],
            maxEstimatedRunCost: 5,
            requireCompanyKey: false
        )
    }

    private func providerUsage(
        current: Double,
        limit: Double,
        history: [UsagePoint]
    ) -> ProviderUsage {
        ProviderUsage(
            id: "test",
            name: "Test",
            category: "Test",
            symbolName: "bolt",
            current: current,
            limit: limit,
            unit: "tokens",
            spendToday: 0,
            spendMonth: 0,
            resetAt: .distantFuture,
            lastUpdated: .now,
            history: history
        )
    }
}

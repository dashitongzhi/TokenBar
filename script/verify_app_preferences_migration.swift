import Foundation

enum AppLanguage: String {
    case english = "en"
    case chinese = "zh-Hans"
}

enum StatusBarContent: String {
    case guardDecision
    case activeWorkspace
    case sessionBudget
    case totalSpend
    case customText
    case iconOnly
}

enum AppIconChoice: String {
    case classic
    case glass
    case frost
    case midnight
}

enum MainSection: String {
    case guardrail
    case workspaces
    case summary
    case integrations
}

enum RoutingMode: String {
    case guardOnly
    case smartRouting
}

enum AgentProvider: String {
    case claudeCode
    case codex
    case cursor
    case continueDev
    case custom
}

private enum VerificationFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let value):
            return value
        }
    }
}

@main
private enum VerifyAppPreferencesMigration {
    static func main() throws {
        let suiteName = "TokenBar.AppPreferencesMigrationVerifier.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw VerificationFailure.message("Could not create temporary UserDefaults suite.")
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        seedOldV1MigratedDemoDefaults(defaults)

        let store = AppPreferencesStore(preferences: defaults)
        let snapshot = store.load()

        try expect(defaults.object(forKey: "selectedProviderID") == nil, "selectedProviderID should be removed.")
        try expect(snapshot.selectedProviderID == "openai", "selectedProviderID should fall back to openai.")
        try expect(snapshot.hasSelectedProviderPreference == false, "provider should not remain an explicit preference.")

        try expect(defaults.object(forKey: "selectedWorkspaceID") == nil, "selectedWorkspaceID should be removed.")
        try expect(snapshot.selectedWorkspaceID == "local-workspace", "selectedWorkspaceID should fall back to local-workspace.")
        try expect(snapshot.hasSelectedWorkspacePreference == false, "workspace should not remain an explicit preference.")

        try expect(defaults.object(forKey: "selectedModel") == nil, "selectedModel should be removed.")
        try expect(defaults.object(forKey: "selectedAgent") == nil, "selectedAgent should be removed.")
        try expect(snapshot.selectedModel == "unspecified", "selectedModel should fall back to unspecified.")
        try expect(snapshot.selectedAgent == .codex, "selectedAgent should fall back to codex.")
        try expect(snapshot.hasSelectedModelPreference == false, "model should not remain an explicit preference.")
        try expect(snapshot.hasSelectedAgentPreference == false, "agent should not remain an explicit preference.")

        try expect(number(defaults, "estimatedRunCost") == 0, "estimatedRunCost should be reset.")
        try expect(number(defaults, "estimatedTokens") == 0, "estimatedTokens should be reset.")
        try expect(number(defaults, "sessionBudget") == 0, "sessionBudget should be reset.")
        try expect(number(defaults, "sessionSpend") == 0, "sessionSpend should be reset.")
        try expect(defaults.object(forKey: "focusModeEnabled") as? Bool == false, "focusModeEnabled should be reset.")
        try expect(defaults.string(forKey: "statusBarContent") == StatusBarContent.iconOnly.rawValue, "statusBarContent should be iconOnly.")
        try expect(defaults.object(forKey: "removedDemoSeedDefaultsV1") as? Bool == true, "legacy V1 marker should stay set.")
        try expect(defaults.integer(forKey: "demoSeedDefaultsCleanupVersion") == 2, "cleanup version should advance to 2.")

        let idempotentSnapshot = store.load()
        try expect(idempotentSnapshot.selectedProviderID == snapshot.selectedProviderID, "second load should keep provider fallback stable.")
        try expect(idempotentSnapshot.selectedWorkspaceID == snapshot.selectedWorkspaceID, "second load should keep workspace fallback stable.")
        try expect(defaults.integer(forKey: "demoSeedDefaultsCleanupVersion") == 2, "second load should keep cleanup version stable.")

        print("Verified old V1 migrated demo defaults are cleaned by AppPreferencesStore V2 migration.")
    }

    private static func seedOldV1MigratedDemoDefaults(_ defaults: UserDefaults) {
        defaults.set(true, forKey: "removedDemoSeedDefaultsV1")
        defaults.set("cursor", forKey: "selectedProviderID")
        defaults.set("client-app", forKey: "selectedWorkspaceID")
        defaults.set("claude-opus", forKey: "selectedModel")
        defaults.set(AgentProvider.cursor.rawValue, forKey: "selectedAgent")
        defaults.set(1.2, forKey: "estimatedRunCost")
        defaults.set(120_000, forKey: "estimatedTokens")
        defaults.set(5, forKey: "sessionBudget")
        defaults.set(1.2, forKey: "sessionSpend")
        defaults.set(true, forKey: "focusModeEnabled")
        defaults.set(StatusBarContent.guardDecision.rawValue, forKey: "statusBarContent")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if condition() == false {
            throw VerificationFailure.message(message)
        }
    }

    private static func number(_ defaults: UserDefaults, _ key: String) -> Double? {
        guard let value = defaults.object(forKey: key) else { return nil }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }
}

import Foundation

struct AppPreferencesSnapshot {
    var language: AppLanguage
    var statusBarContent: StatusBarContent
    var routingMode: RoutingMode
    var selectedMainSection: MainSection
    var selectedProviderID: String
    var selectedWorkspaceID: String
    var selectedAgent: AgentProvider
    var selectedModel: String
    var estimatedRunCost: Double
    var estimatedTokens: Double
    var customStatusText: String
    var sessionBudget: Double
    var sessionSpend: Double
    var focusModeEnabled: Bool
    var localAPIEnabled: Bool
    var selectedAppIcon: AppIconChoice
    var hasSelectedProviderPreference: Bool
    var hasSelectedWorkspacePreference: Bool
    var hasSelectedAgentPreference: Bool
    var hasSelectedModelPreference: Bool
}

struct AppPreferencesStore {
    private let preferences: UserDefaults
    private enum DemoDefaultsCleanup {
        static let legacyV1Key = "removedDemoSeedDefaultsV1"
        static let versionKey = "demoSeedDefaultsCleanupVersion"
        static let latestVersion = 2
        static let demoProviderIDs = ["cursor", "github", "stripe"]
        static let demoWorkspaceIDs = ["client-app", "personal-lab", "production-fix"]
    }

    private struct DemoDefaultsMigration {
        var resetSelectedProvider = false
        var resetSelectedWorkspace = false
        var resetSelectedAgent = false
        var resetSelectedModel = false
    }

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
    }

    func load() -> AppPreferencesSnapshot {
        let migration = migrateDemoDefaultsIfNeeded()
        return AppPreferencesSnapshot(
            language: AppLanguage(rawValue: preferences.string(forKey: "language") ?? "") ?? .english,
            statusBarContent: StatusBarContent(rawValue: preferences.string(forKey: "statusBarContent") ?? "") ?? .iconOnly,
            routingMode: RoutingMode(rawValue: preferences.string(forKey: "routingMode") ?? "") ?? .guardOnly,
            selectedMainSection: MainSection(rawValue: preferences.string(forKey: "selectedMainSection") ?? "") ?? .guardrail,
            selectedProviderID: preferences.string(forKey: "selectedProviderID") ?? "openai",
            selectedWorkspaceID: preferences.string(forKey: "selectedWorkspaceID") ?? "local-workspace",
            selectedAgent: AgentProvider(rawValue: preferences.string(forKey: "selectedAgent") ?? "") ?? .codex,
            selectedModel: preferences.string(forKey: "selectedModel") ?? "unspecified",
            estimatedRunCost: number(forKey: "estimatedRunCost") ?? 0,
            estimatedTokens: number(forKey: "estimatedTokens") ?? 0,
            customStatusText: preferences.string(forKey: "customStatusText") ?? "TokenBar",
            sessionBudget: number(forKey: "sessionBudget") ?? 0,
            sessionSpend: number(forKey: "sessionSpend") ?? 0,
            focusModeEnabled: preferences.object(forKey: "focusModeEnabled") as? Bool ?? false,
            localAPIEnabled: preferences.object(forKey: "localAPIEnabled") as? Bool ?? true,
            selectedAppIcon: AppIconChoice(rawValue: preferences.string(forKey: "selectedAppIcon") ?? "") ?? .classic,
            hasSelectedProviderPreference: preferences.object(forKey: "selectedProviderID") != nil && migration.resetSelectedProvider == false,
            hasSelectedWorkspacePreference: preferences.object(forKey: "selectedWorkspaceID") != nil && migration.resetSelectedWorkspace == false,
            hasSelectedAgentPreference: preferences.object(forKey: "selectedAgent") != nil && migration.resetSelectedAgent == false,
            hasSelectedModelPreference: preferences.object(forKey: "selectedModel") != nil && migration.resetSelectedModel == false
        )
    }

    func save(_ snapshot: AppPreferencesSnapshot) {
        preferences.set(snapshot.language.rawValue, forKey: "language")
        preferences.set(snapshot.selectedMainSection.rawValue, forKey: "selectedMainSection")
        preferences.set(snapshot.statusBarContent.rawValue, forKey: "statusBarContent")
        preferences.set(snapshot.routingMode.rawValue, forKey: "routingMode")
        saveOptionalPreference(snapshot.selectedProviderID, hasExplicitValue: snapshot.hasSelectedProviderPreference, key: "selectedProviderID")
        saveOptionalPreference(snapshot.selectedWorkspaceID, hasExplicitValue: snapshot.hasSelectedWorkspacePreference, key: "selectedWorkspaceID")
        saveOptionalPreference(snapshot.selectedAgent.rawValue, hasExplicitValue: snapshot.hasSelectedAgentPreference, key: "selectedAgent")
        saveOptionalPreference(snapshot.selectedModel, hasExplicitValue: snapshot.hasSelectedModelPreference, key: "selectedModel")
        preferences.set(snapshot.estimatedRunCost, forKey: "estimatedRunCost")
        preferences.set(snapshot.estimatedTokens, forKey: "estimatedTokens")
        preferences.set(snapshot.customStatusText, forKey: "customStatusText")
        preferences.set(snapshot.sessionBudget, forKey: "sessionBudget")
        preferences.set(snapshot.sessionSpend, forKey: "sessionSpend")
        preferences.set(snapshot.focusModeEnabled, forKey: "focusModeEnabled")
        preferences.set(snapshot.localAPIEnabled, forKey: "localAPIEnabled")
        preferences.set(snapshot.selectedAppIcon.rawValue, forKey: "selectedAppIcon")
    }

    private func migrateDemoDefaultsIfNeeded() -> DemoDefaultsMigration {
        var migration = DemoDefaultsMigration()
        let completedVersion = preferences.integer(forKey: DemoDefaultsCleanup.versionKey)
        let needsLegacyV1Marker = preferences.object(forKey: DemoDefaultsCleanup.legacyV1Key) == nil
        let needsV2Cleanup = completedVersion < DemoDefaultsCleanup.latestVersion
        guard needsLegacyV1Marker || needsV2Cleanup else { return migration }

        let hadDemoProvider = DemoDefaultsCleanup.demoProviderIDs.contains(preferences.string(forKey: "selectedProviderID") ?? "")
        let hadDemoWorkspace = DemoDefaultsCleanup.demoWorkspaceIDs.contains(preferences.string(forKey: "selectedWorkspaceID") ?? "")
        let hadDemoModel = preferences.string(forKey: "selectedModel") == "claude-opus"
        let hadDemoCost = number(forKey: "estimatedRunCost") == 1.2
        let hadDemoTokens = number(forKey: "estimatedTokens") == 120_000
        let hadDemoSessionBudget = number(forKey: "sessionBudget") == 5
        let hadDemoSignature = hadDemoProvider || hadDemoWorkspace || hadDemoModel || hadDemoCost || hadDemoTokens || hadDemoSessionBudget

        if hadDemoProvider {
            preferences.removeObject(forKey: "selectedProviderID")
            migration.resetSelectedProvider = true
        }
        if hadDemoWorkspace {
            preferences.removeObject(forKey: "selectedWorkspaceID")
            preferences.set(StatusBarContent.iconOnly.rawValue, forKey: "statusBarContent")
            migration.resetSelectedWorkspace = true
        }
        if hadDemoModel || hadDemoCost || hadDemoTokens {
            preferences.removeObject(forKey: "selectedModel")
            preferences.removeObject(forKey: "selectedAgent")
            preferences.set(0, forKey: "estimatedRunCost")
            preferences.set(0, forKey: "estimatedTokens")
            migration.resetSelectedAgent = true
            migration.resetSelectedModel = true
        }
        if hadDemoSessionBudget {
            preferences.set(0, forKey: "sessionBudget")
            preferences.set(0, forKey: "sessionSpend")
        }
        if number(forKey: "sessionSpend") == 1.2 || hadDemoSignature {
            preferences.set(0, forKey: "sessionSpend")
        }
        if hadDemoSignature && preferences.object(forKey: "focusModeEnabled") as? Bool == true {
            preferences.set(false, forKey: "focusModeEnabled")
        }
        if hadDemoSignature && preferences.string(forKey: "statusBarContent") == StatusBarContent.guardDecision.rawValue {
            preferences.set(StatusBarContent.iconOnly.rawValue, forKey: "statusBarContent")
        }
        preferences.set(true, forKey: DemoDefaultsCleanup.legacyV1Key)
        preferences.set(DemoDefaultsCleanup.latestVersion, forKey: DemoDefaultsCleanup.versionKey)
        preferences.synchronize()
        return migration
    }

    private func saveOptionalPreference(_ value: String, hasExplicitValue: Bool, key: String) {
        if hasExplicitValue {
            preferences.set(value, forKey: key)
        } else {
            preferences.removeObject(forKey: key)
        }
    }

    private func number(forKey key: String) -> Double? {
        guard let value = preferences.object(forKey: key) else { return nil }
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

import Foundation

struct AppPreferencesSnapshot {
    var language: AppLanguage
    var statusBarContent: StatusBarContent
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

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
    }

    func load() -> AppPreferencesSnapshot {
        migrateDemoDefaultsIfNeeded()
        return AppPreferencesSnapshot(
            language: AppLanguage(rawValue: preferences.string(forKey: "language") ?? "") ?? .english,
            statusBarContent: StatusBarContent(rawValue: preferences.string(forKey: "statusBarContent") ?? "") ?? .iconOnly,
            selectedMainSection: MainSection(rawValue: preferences.string(forKey: "selectedMainSection") ?? "") ?? .guardrail,
            selectedProviderID: preferences.string(forKey: "selectedProviderID") ?? "openai",
            selectedWorkspaceID: preferences.string(forKey: "selectedWorkspaceID") ?? "local-workspace",
            selectedAgent: AgentProvider(rawValue: preferences.string(forKey: "selectedAgent") ?? "") ?? .codex,
            selectedModel: preferences.string(forKey: "selectedModel") ?? "gpt-5",
            estimatedRunCost: number(forKey: "estimatedRunCost") ?? 0,
            estimatedTokens: number(forKey: "estimatedTokens") ?? 0,
            customStatusText: preferences.string(forKey: "customStatusText") ?? "TokenBar",
            sessionBudget: number(forKey: "sessionBudget") ?? 0,
            sessionSpend: number(forKey: "sessionSpend") ?? 0,
            focusModeEnabled: preferences.object(forKey: "focusModeEnabled") as? Bool ?? false,
            localAPIEnabled: preferences.object(forKey: "localAPIEnabled") as? Bool ?? true,
            selectedAppIcon: AppIconChoice(rawValue: preferences.string(forKey: "selectedAppIcon") ?? "") ?? .classic,
            hasSelectedProviderPreference: preferences.object(forKey: "selectedProviderID") != nil,
            hasSelectedWorkspacePreference: preferences.object(forKey: "selectedWorkspaceID") != nil,
            hasSelectedAgentPreference: preferences.object(forKey: "selectedAgent") != nil,
            hasSelectedModelPreference: preferences.object(forKey: "selectedModel") != nil
        )
    }

    func save(_ snapshot: AppPreferencesSnapshot) {
        preferences.set(snapshot.language.rawValue, forKey: "language")
        preferences.set(snapshot.selectedMainSection.rawValue, forKey: "selectedMainSection")
        preferences.set(snapshot.statusBarContent.rawValue, forKey: "statusBarContent")
        preferences.set(snapshot.selectedProviderID, forKey: "selectedProviderID")
        preferences.set(snapshot.selectedWorkspaceID, forKey: "selectedWorkspaceID")
        preferences.set(snapshot.selectedAgent.rawValue, forKey: "selectedAgent")
        preferences.set(snapshot.selectedModel, forKey: "selectedModel")
        preferences.set(snapshot.estimatedRunCost, forKey: "estimatedRunCost")
        preferences.set(snapshot.estimatedTokens, forKey: "estimatedTokens")
        preferences.set(snapshot.customStatusText, forKey: "customStatusText")
        preferences.set(snapshot.sessionBudget, forKey: "sessionBudget")
        preferences.set(snapshot.sessionSpend, forKey: "sessionSpend")
        preferences.set(snapshot.focusModeEnabled, forKey: "focusModeEnabled")
        preferences.set(snapshot.localAPIEnabled, forKey: "localAPIEnabled")
        preferences.set(snapshot.selectedAppIcon.rawValue, forKey: "selectedAppIcon")
    }

    private func migrateDemoDefaultsIfNeeded() {
        guard preferences.object(forKey: "removedDemoSeedDefaultsV1") == nil else { return }

        let demoWorkspaceIDs = ["client-app", "personal-lab", "production-fix"]
        let hadDemoWorkspace = demoWorkspaceIDs.contains(preferences.string(forKey: "selectedWorkspaceID") ?? "")
        let hadDemoModel = preferences.string(forKey: "selectedModel") == "claude-opus"
        let hadDemoCost = number(forKey: "estimatedRunCost") == 1.2
        let hadDemoTokens = number(forKey: "estimatedTokens") == 120_000
        let hadDemoSessionBudget = number(forKey: "sessionBudget") == 5
        let hadDemoSignature = hadDemoWorkspace || hadDemoModel || hadDemoCost || hadDemoTokens || hadDemoSessionBudget
        var changed = false

        if hadDemoWorkspace {
            preferences.set("local-workspace", forKey: "selectedWorkspaceID")
            preferences.set(StatusBarContent.iconOnly.rawValue, forKey: "statusBarContent")
            changed = true
        }
        if hadDemoModel || hadDemoCost || hadDemoTokens {
            preferences.set("gpt-5", forKey: "selectedModel")
            preferences.set(AgentProvider.codex.rawValue, forKey: "selectedAgent")
            preferences.set(0, forKey: "estimatedRunCost")
            preferences.set(0, forKey: "estimatedTokens")
            changed = true
        }
        if hadDemoSessionBudget {
            preferences.set(0, forKey: "sessionBudget")
            preferences.set(0, forKey: "sessionSpend")
            changed = true
        }
        if number(forKey: "sessionSpend") == 1.2 || hadDemoSignature {
            preferences.set(0, forKey: "sessionSpend")
            changed = true
        }
        if hadDemoSignature && preferences.object(forKey: "focusModeEnabled") as? Bool == true {
            preferences.set(false, forKey: "focusModeEnabled")
            changed = true
        }
        if hadDemoSignature && preferences.string(forKey: "statusBarContent") == StatusBarContent.guardDecision.rawValue {
            preferences.set(StatusBarContent.iconOnly.rawValue, forKey: "statusBarContent")
            changed = true
        }
        preferences.set(true, forKey: "removedDemoSeedDefaultsV1")
        preferences.synchronize()
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

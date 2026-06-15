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
}

struct AppPreferencesStore {
    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
    }

    func load() -> AppPreferencesSnapshot {
        AppPreferencesSnapshot(
            language: AppLanguage(rawValue: preferences.string(forKey: "language") ?? "") ?? .english,
            statusBarContent: StatusBarContent(rawValue: preferences.string(forKey: "statusBarContent") ?? "") ?? .guardDecision,
            selectedMainSection: MainSection(rawValue: preferences.string(forKey: "selectedMainSection") ?? "") ?? .guardrail,
            selectedProviderID: preferences.string(forKey: "selectedProviderID") ?? "openai",
            selectedWorkspaceID: preferences.string(forKey: "selectedWorkspaceID") ?? "client-app",
            selectedAgent: AgentProvider(rawValue: preferences.string(forKey: "selectedAgent") ?? "") ?? .claudeCode,
            selectedModel: preferences.string(forKey: "selectedModel") ?? "claude-opus",
            estimatedRunCost: preferences.object(forKey: "estimatedRunCost") as? Double ?? 1.2,
            estimatedTokens: preferences.object(forKey: "estimatedTokens") as? Double ?? 120_000,
            customStatusText: preferences.string(forKey: "customStatusText") ?? "TokenBar",
            sessionBudget: preferences.object(forKey: "sessionBudget") as? Double ?? 5,
            sessionSpend: preferences.object(forKey: "sessionSpend") as? Double ?? 1.2,
            focusModeEnabled: preferences.object(forKey: "focusModeEnabled") as? Bool ?? true,
            localAPIEnabled: preferences.object(forKey: "localAPIEnabled") as? Bool ?? true,
            selectedAppIcon: AppIconChoice(rawValue: preferences.string(forKey: "selectedAppIcon") ?? "") ?? .classic
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
}

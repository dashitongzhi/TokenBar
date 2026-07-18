import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var language: AppLanguage {
        didSet { savePreferencesAndNotify() }
    }

    @Published var statusBarContent: StatusBarContent {
        didSet { savePreferencesAndNotify() }
    }

    @Published var routingMode: RoutingMode {
        didSet {
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedProviderID: String {
        didSet {
            markExplicitSelection(\.hasExplicitSelectedProviderPreference)
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedMainSection: MainSection {
        didSet { savePreferencesAndNotify() }
    }

    @Published var selectedWorkspaceID: String {
        didSet {
            markExplicitSelection(\.hasExplicitSelectedWorkspacePreference)
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedAgent: AgentProvider {
        didSet {
            markExplicitSelection(\.hasExplicitSelectedAgentPreference)
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedModel: String {
        didSet {
            markExplicitSelection(\.hasExplicitSelectedModelPreference)
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var estimatedRunCost: Double {
        didSet {
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var estimatedTokens: Double {
        didSet {
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var customStatusText: String {
        didSet { savePreferencesAndNotify() }
    }

    @Published var sessionBudget: Double {
        didSet { savePreferencesAndNotify() }
    }

    @Published var sessionSpend: Double {
        didSet { savePreferencesAndNotify() }
    }

    @Published var focusModeEnabled: Bool {
        didSet { savePreferencesAndNotify() }
    }

    @Published var localAPIEnabled: Bool {
        didSet {
            savePreferencesAndNotify()
            LocalAPIServer.shared.syncWithPreference()
        }
    }

    @Published var selectedAppIcon: AppIconChoice {
        didSet {
            savePreferencesAndNotify()
            applySelectedAppIcon()
        }
    }

    @Published var providers: [ProviderUsage] = []
    @Published private(set) var apiMonitors: [APIMonitorSpec] = APIMonitorCatalog.all
    @Published var workspacePolicies: [WorkspacePolicy] = []
    @Published var currentPolicyInput = PolicyEvaluationInput(
        agent: .codex,
        workspaceID: "local-workspace",
        providerID: "openai",
        model: "unspecified",
        estimatedCost: 0,
        estimatedTokens: 0,
        intent: "code"
    )
    @Published var currentDecision = PolicyDecision(
        timestamp: .now,
        status: .allow,
        agent: .codex,
        workspaceID: "local-workspace",
        workspaceName: "Local Workspace",
        providerID: "openai",
        model: "unspecified",
        estimatedCost: 0,
        projectedDailySpend: 0,
        projectedMonthlySpend: 0,
        reasons: ["Workspace, provider, model, and budget are inside policy."],
        recommendation: "Select a model before running an agent.",
        fallbackProviderID: "anthropic"
    )
    @Published var recentDecisions: [PolicyDecision] = []
    @Published var auditEvents: [AuditEvent] = []
    @Published var modelUsageRollups: [ModelUsageRollup] = []
    @Published var modelCatalogItems: [ModelCatalogItem] = []
    @Published private(set) var lastRefresh: Date = .now
    @Published private(set) var isRefreshingUsage = false
    @Published var isRefreshingModelCatalog = false
    @Published var modelCatalogMessage = ""
    @Published var localAPIStatus: LocalAPIStatus = .stopped

    private let preferencesStore = AppPreferencesStore()
    private let providerStore = ProviderUsageStore()
    private let workspacePolicyStore = WorkspacePolicyStore()
    let auditEventStore = AuditEventStore()
    let localUsageIngestionModule = LocalUsageIngestionModule()
    let smartRoutingLedgerStore = SmartRoutingLedgerStore()
    let agentModelConfigurationService = AgentModelConfigurationService()
    let providerModelCatalogService = ProviderModelCatalogService()
    let providerRefreshModule = ProviderRefreshModule()
    let smartRoutingRecommender = SmartRoutingRecommender()
    let ccSwitchUsageService = CCSwitchUsageService()
    private var hasExplicitSelectedProviderPreference = false
    private var hasExplicitSelectedWorkspacePreference = false
    private var hasExplicitSelectedAgentPreference = false
    private var hasExplicitSelectedModelPreference = false
    private var isApplyingInferredSelections = false
    #if DEBUG
    var isPersistenceSuppressedForVerification = false
    #endif

    private init() {
        let savedPreferences = preferencesStore.load()
        hasExplicitSelectedProviderPreference = savedPreferences.hasSelectedProviderPreference
        hasExplicitSelectedWorkspacePreference = savedPreferences.hasSelectedWorkspacePreference
        hasExplicitSelectedAgentPreference = savedPreferences.hasSelectedAgentPreference
        hasExplicitSelectedModelPreference = savedPreferences.hasSelectedModelPreference
        language = savedPreferences.language
        statusBarContent = savedPreferences.statusBarContent
        routingMode = savedPreferences.routingMode
        selectedMainSection = savedPreferences.selectedMainSection
        selectedProviderID = savedPreferences.selectedProviderID
        selectedWorkspaceID = savedPreferences.selectedWorkspaceID
        selectedAgent = savedPreferences.selectedAgent
        selectedModel = savedPreferences.selectedModel
        estimatedRunCost = savedPreferences.estimatedRunCost
        estimatedTokens = savedPreferences.estimatedTokens
        customStatusText = savedPreferences.customStatusText
        sessionBudget = savedPreferences.sessionBudget
        sessionSpend = savedPreferences.sessionSpend
        focusModeEnabled = savedPreferences.focusModeEnabled
        localAPIEnabled = savedPreferences.localAPIEnabled
        selectedAppIcon = savedPreferences.selectedAppIcon

        let configuredModelRows = agentModelConfigurationService.readConfiguredModels()
        let configuredCatalogItems = agentModelConfigurationService.readConfiguredModelCatalogItems()
            + ccSwitchUsageService.configuredModelCatalogItems()
        let inferredPolicy = AgentModelConfigurationService.inferWorkspacePolicy(
            configuredRows: configuredModelRows,
            catalogItems: configuredCatalogItems,
            fallbackPath: UserHomeDirectory.url.path
        )

        providers = providerStore.load(defaults: AppSeedData.providers())
        workspacePolicies = workspacePolicyStore.load(defaults: AppSeedData.workspacePolicies(inference: inferredPolicy))
        auditEvents = auditEventStore.load(defaults: AppSeedData.auditEvents())
        normalizeSelectionsAfterLoad()
        mergeModelUsageRollups(localUsageIngestionModule.loadModelUsageRollups())
        mergeModelCatalogItems(configuredCatalogItems, replacingProviderID: nil)
        rebuildPolicyInput()
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
        recentDecisions = [currentDecision]
        applySelectedAppIcon()
    }

    func refreshAll() {
        guard isRefreshingUsage == false else { return }
        isRefreshingUsage = true
        reloadModelUsageRollups()
        reloadModelCatalogFromLocalSources()

        Task {
            let outcome = await providerRefreshModule.refresh(providers: providers)
            applyProviderRefreshOutcome(outcome)
        }
    }

    func applyProviderRefreshOutcome(_ outcome: ProviderRefreshOutcome) {
        providers = outcome.providers
        for audit in outcome.audits {
            addAudit(provider: audit.provider, action: audit.action, detail: audit.detail)
        }
        lastRefresh = .now
        isRefreshingUsage = false
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
        persistProviders()
        if CommandLine.arguments.contains("--tokenbar-verify-local-api") == false,
           CommandLine.arguments.contains("--tokenbar-verify-minimax-ccswitch-fallback-audit") == false {
            NotificationService.shared.notifyIfNeeded(appState: self)
        }
        notifyStatusBarUpdate()
    }

    private func savePreferencesAndNotify() {
        preferencesStore.save(AppPreferencesSnapshot(
            language: language,
            statusBarContent: statusBarContent,
            routingMode: routingMode,
            selectedMainSection: selectedMainSection,
            selectedProviderID: selectedProviderID,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedAgent: selectedAgent,
            selectedModel: selectedModel,
            estimatedRunCost: estimatedRunCost,
            estimatedTokens: estimatedTokens,
            customStatusText: customStatusText,
            sessionBudget: sessionBudget,
            sessionSpend: sessionSpend,
            focusModeEnabled: focusModeEnabled,
            localAPIEnabled: localAPIEnabled,
            selectedAppIcon: selectedAppIcon,
            hasSelectedProviderPreference: hasExplicitSelectedProviderPreference,
            hasSelectedWorkspacePreference: hasExplicitSelectedWorkspacePreference,
            hasSelectedAgentPreference: hasExplicitSelectedAgentPreference,
            hasSelectedModelPreference: hasExplicitSelectedModelPreference
        ))
        notifyStatusBarUpdate()
    }

    private func normalizeSelectionsAfterLoad() {
        isApplyingInferredSelections = true
        defer { isApplyingInferredSelections = false }

        for providerID in workspacePolicies.flatMap(\.allowedProviderIDs) {
            ensureProviderExists(providerID: providerID)
        }
        if hasExplicitSelectedWorkspacePreference == false,
           let inferredWorkspace = workspacePolicies.first(where: { $0.preferredProviderID != nil || $0.preferredModel != nil }) {
            selectedWorkspaceID = inferredWorkspace.id
        }
        if providers.contains(where: { $0.id == selectedProviderID }) == false {
            hasExplicitSelectedProviderPreference = false
            selectedProviderID = providers.first?.id ?? "openai"
        }
        if workspacePolicies.contains(where: { $0.id == selectedWorkspaceID }) == false {
            hasExplicitSelectedWorkspacePreference = false
            selectedWorkspaceID = workspacePolicies.first?.id ?? "local-workspace"
        }
        if hasExplicitSelectedProviderPreference == false,
           let preferredProviderID = selectedWorkspace?.preferredProviderID,
           preferredProviderID.isEmpty == false {
            ensureProviderExists(providerID: preferredProviderID)
            selectedProviderID = preferredProviderID
        }
        if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasExplicitSelectedModelPreference = false
        }
        if hasExplicitSelectedModelPreference == false,
           let preferredModel = selectedWorkspace?.preferredModel,
           preferredModel.isEmpty == false {
            selectedModel = preferredModel
        }
        if hasExplicitSelectedAgentPreference == false {
            selectedAgent = AgentProvider.defaultAgent(forProviderID: selectedProviderID)
        }
        if sessionBudget <= 0 {
            sessionSpend = 0
            focusModeEnabled = false
        }
    }

    private func markExplicitSelection(_ keyPath: ReferenceWritableKeyPath<AppState, Bool>) {
        guard isApplyingInferredSelections == false else { return }
        self[keyPath: keyPath] = true
    }

    func notifyStatusBarUpdate() {
        NotificationCenter.default.post(name: .tokenBarStateDidChange, object: self)
    }

    func addAudit(provider: String, action: String, detail: String) {
        auditEvents.insert(AuditEvent(timestamp: .now, provider: provider, action: action, detail: detail), at: 0)
        if auditEvents.count > 100 {
            auditEvents.removeLast(auditEvents.count - 100)
        }
        #if DEBUG
        guard isPersistenceSuppressedForVerification == false else { return }
        #endif
        auditEventStore.save(auditEvents)
    }

    func persistProviders() {
        #if DEBUG
        guard isPersistenceSuppressedForVerification == false else { return }
        #endif
        providerStore.save(providers)
    }

    func persistWorkspacePolicies() {
        #if DEBUG
        guard isPersistenceSuppressedForVerification == false else { return }
        #endif
        workspacePolicyStore.save(workspacePolicies)
    }

}

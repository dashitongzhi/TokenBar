import Foundation

@MainActor
final class AppPersistenceController {
    struct Delays {
        var preferences: TimeInterval = 0.25
        var audit: TimeInterval = 0.15
        var providers: TimeInterval = 0.15
        var workspaces: TimeInterval = 0.15
    }

    private let preferencesStore: AppPreferencesStore
    private let providerStore: ProviderUsageStore
    private let workspacePolicyStore: WorkspacePolicyStore
    private let auditEventStore: AuditEventStore
    private let queue: DispatchQueue
    private let delays: Delays
    private var preferencesWorkItem: DispatchWorkItem?
    private var auditWorkItem: DispatchWorkItem?
    private var providersWorkItem: DispatchWorkItem?
    private var workspacesWorkItem: DispatchWorkItem?

    init(
        preferencesStore: AppPreferencesStore? = nil,
        providerStore: ProviderUsageStore? = nil,
        workspacePolicyStore: WorkspacePolicyStore? = nil,
        auditEventStore: AuditEventStore? = nil,
        queue: DispatchQueue = DispatchQueue(label: "TokenBar.Persistence", qos: .utility),
        delays: Delays? = nil
    ) {
        self.preferencesStore = preferencesStore ?? AppPreferencesStore()
        self.providerStore = providerStore ?? ProviderUsageStore()
        self.workspacePolicyStore = workspacePolicyStore ?? WorkspacePolicyStore()
        self.auditEventStore = auditEventStore ?? AuditEventStore()
        self.queue = queue
        self.delays = delays ?? Delays()
    }

    func loadPreferences() -> AppPreferencesSnapshot {
        preferencesStore.load()
    }

    func loadProviders(defaults: [ProviderUsage]) -> [ProviderUsage] {
        providerStore.load(defaults: defaults)
    }

    func loadWorkspacePolicies(defaults: [WorkspacePolicy]) -> [WorkspacePolicy] {
        workspacePolicyStore.load(defaults: defaults)
    }

    func loadAuditEvents(defaults: [AuditEvent]) -> [AuditEvent] {
        auditEventStore.load(defaults: defaults)
    }

    func schedulePreferences(_ snapshot: AppPreferencesSnapshot) {
        preferencesWorkItem?.cancel()
        let store = preferencesStore
        let item = DispatchWorkItem { store.save(snapshot) }
        preferencesWorkItem = item
        queue.asyncAfter(deadline: .now() + delays.preferences, execute: item)
    }

    func scheduleAuditEvents(_ events: [AuditEvent]) {
        auditWorkItem?.cancel()
        let store = auditEventStore
        let item = DispatchWorkItem { store.save(events) }
        auditWorkItem = item
        queue.asyncAfter(deadline: .now() + delays.audit, execute: item)
    }

    func scheduleProviders(_ providers: [ProviderUsage]) {
        providersWorkItem?.cancel()
        let store = providerStore
        let item = DispatchWorkItem { store.save(providers) }
        providersWorkItem = item
        queue.asyncAfter(deadline: .now() + delays.providers, execute: item)
    }

    func scheduleWorkspacePolicies(_ policies: [WorkspacePolicy]) {
        workspacesWorkItem?.cancel()
        let store = workspacePolicyStore
        let item = DispatchWorkItem { store.save(policies) }
        workspacesWorkItem = item
        queue.asyncAfter(deadline: .now() + delays.workspaces, execute: item)
    }

    func flush(
        preferences: AppPreferencesSnapshot,
        auditEvents: [AuditEvent],
        providers: [ProviderUsage],
        workspacePolicies: [WorkspacePolicy]
    ) {
        preferencesWorkItem?.cancel()
        auditWorkItem?.cancel()
        providersWorkItem?.cancel()
        workspacesWorkItem?.cancel()
        let preferencesStore = preferencesStore
        let auditEventStore = auditEventStore
        let providerStore = providerStore
        let workspacePolicyStore = workspacePolicyStore
        queue.sync {
            preferencesStore.save(preferences)
            auditEventStore.save(auditEvents)
            providerStore.save(providers)
            workspacePolicyStore.save(workspacePolicies)
        }
    }
}

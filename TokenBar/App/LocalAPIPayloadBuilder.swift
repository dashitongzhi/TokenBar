import Foundation

@MainActor
enum LocalAPIPayloadBuilder {
    static func policyJSON(currentDecision: PolicyDecision, workspacePolicies: [WorkspacePolicy]) throws -> Data {
        try encode(LocalAPIWire.PolicyDocument(
            timestamp: timestamp(),
            decision: .init(currentDecision),
            workspaces: workspacePolicies.map(LocalAPIWire.Workspace.init)
        ))
    }

    static func policyDecisionJSON(_ decision: PolicyDecision) throws -> Data {
        try encode(LocalAPIWire.PolicyDecisionDocument(
            timestamp: timestamp(),
            decision: .init(decision)
        ))
    }

    static func localAgentUsageJSON(snapshot: LocalAgentUsageAppliedSnapshot, decision: PolicyDecision) throws -> Data {
        try encode(LocalAPIWire.LocalAgentUsageDocument(
            timestamp: timestamp(),
            source: snapshot.sourceName,
            usage: .init(snapshot),
            decision: .init(decision)
        ))
    }

    static func smartRoutingRunJSON(record: SmartRoutingRunRecord) throws -> Data {
        try encode(LocalAPIWire.SmartRoutingRunDocument(
            timestamp: timestamp(),
            routingRun: .init(record)
        ))
    }

    static func smartRoutingStatsJSON(snapshot: SmartRoutingStatsSnapshot) throws -> Data {
        try encode(LocalAPIWire.SmartRoutingStatsDocument(
            timestamp: timestamp(snapshot.generatedAt),
            stats: .init(snapshot),
            routes: snapshot.routeStats.map(LocalAPIWire.SmartRoutingRoute.init),
            recentRuns: snapshot.recentRuns.map(LocalAPIWire.SmartRoutingRun.init)
        ))
    }

    static func mcpSnapshotJSON(providers: [ProviderUsage], filteredProviderID: String? = nil) throws -> Data {
        let selected = filteredProviderID.map { id in providers.filter { $0.id == id } } ?? providers
        return try encode(LocalAPIWire.QuotaDocument(
            timestamp: timestamp(),
            quotas: selected.map(LocalAPIWire.Quota.init)
        ))
    }

    static func paceJSON(provider: ProviderUsage, recommendation: String) throws -> Data {
        try encode(LocalAPIWire.Pace(provider: provider, recommendation: recommendation))
    }

    private static func timestamp(_ date: Date = .now) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}

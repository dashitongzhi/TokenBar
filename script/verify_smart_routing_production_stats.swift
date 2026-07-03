import Foundation

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
private enum VerifySmartRoutingProductionStats {
    private struct RecordedRoute: Equatable {
        var providerID: String
        var model: String
        var marker: SmartRoutingRecommendationMarker
        var isWin: Bool

        var routeKey: String {
            [
                providerID,
                model.lowercased(),
                (marker.taskIntent ?? "unspecified").lowercased()
            ].joined(separator: "|")
        }
    }

    private struct RouteStats: Equatable {
        var providerID: String
        var model: String
        var runCount: Int
        var winRate: Double
    }

    static func main() throws {
        if CommandLine.arguments.count > 1 {
            try verifyLedger(at: CommandLine.arguments[1])
            return
        }

        let smokeOpenAI = SmartRoutingRecommendationMarker(
            taskIntent: "implement",
            workspaceID: "smoke-routing-ledger",
            workspaceName: nil,
            sessionID: nil,
            taskID: nil,
            selectedBy: "smoke",
            model: "gpt-5-pro",
            routingReason: nil,
            metadata: [:]
        )
        let smokeUnknownCost = SmartRoutingRecommendationMarker(
            taskIntent: "implement",
            workspaceID: "smoke-routing-ledger",
            workspaceName: nil,
            sessionID: nil,
            taskID: nil,
            selectedBy: "smoke",
            model: "claude-opus-unknown-cost",
            routingReason: nil,
            metadata: [:]
        )
        let metadataSynthetic = SmartRoutingRecommendationMarker(
            taskIntent: "implementation",
            workspaceID: "tokenbar",
            workspaceName: "TokenBar",
            sessionID: "session-1",
            taskID: "task-1",
            selectedBy: "smart-routing",
            model: "gpt-5",
            routingReason: nil,
            metadata: ["synthetic": "true"]
        )
        let production = SmartRoutingRecommendationMarker(
            taskIntent: "implementation",
            workspaceID: "tokenbar",
            workspaceName: "TokenBar",
            sessionID: "session-2",
            taskID: "task-2",
            selectedBy: "smart-routing",
            model: "gpt-5",
            routingReason: "Based on recorded production runs.",
            metadata: ["source": "local-agent"]
        )
        let productionWithFreeformReason = SmartRoutingRecommendationMarker(
            taskIntent: "implementation",
            workspaceID: "tokenbar",
            workspaceName: "TokenBar",
            sessionID: "session-3",
            taskID: "task-3",
            selectedBy: "smart-routing",
            model: "gpt-5",
            routingReason: "Not synthetic; replaces smoke baseline with live evidence.",
            metadata: ["source": "local-agent"]
        )

        let markers = [smokeOpenAI, smokeUnknownCost, metadataSynthetic, production, productionWithFreeformReason]
        let eligible = markers.filter(SmartRoutingRecommendationEligibility.isProductionRecommendationEligible)

        try expect(eligible.count == 2, "only the production markers should remain eligible.")
        try expect(
            eligible == [production, productionWithFreeformReason],
            "smoke-routing-ledger, synthetic metadata, and unknown-cost smoke models must be excluded."
        )
        try expect(
            SmartRoutingRecommendationEligibility.isProductionRecommendationEligible(smokeUnknownCost) == false,
            "claude-opus-unknown-cost smoke success must not become recommendation evidence."
        )
        try expect(
            SmartRoutingRecommendationEligibility.isProductionRecommendationEligible(productionWithFreeformReason),
            "free-form routing reasons must not exclude production evidence."
        )

        let records = [
            RecordedRoute(providerID: "openai", model: "gpt-5-pro", marker: smokeOpenAI, isWin: true),
            RecordedRoute(providerID: "anthropic", model: "claude-opus-unknown-cost", marker: smokeUnknownCost, isWin: true),
            RecordedRoute(providerID: "anthropic", model: "claude-opus-unknown-cost", marker: smokeUnknownCost, isWin: true),
            RecordedRoute(providerID: "openai", model: "gpt-5", marker: production, isWin: true)
        ]
        let productionStats = routeStats(from: records.filter {
            SmartRoutingRecommendationEligibility.isProductionRecommendationEligible($0.marker)
        })

        try expect(productionStats.count == 1, "only production routes should contribute to recommendation stats.")
        try expect(
            productionStats.first?.providerID == "openai" && productionStats.first?.model == "gpt-5",
            "the recommended evidence must come from the real production route, not smoke winners."
        )
        try expect(
            productionStats.contains { $0.model == "claude-opus-unknown-cost" } == false,
            "synthetic unknown-cost smoke winners must not be route candidates."
        )

        print("Verified Smart Routing production recommendation stats exclude smoke/test/synthetic runs.")
    }

    private static func verifyLedger(at path: String) throws {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        let data = try Data(contentsOf: url)
        guard let rawRecords = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw VerificationFailure.message("ledger JSON should be an array of records.")
        }

        let markers = rawRecords.map(marker)
        let eligible = markers.filter(SmartRoutingRecommendationEligibility.isProductionRecommendationEligible)
        let excludedCount = markers.count - eligible.count
        let pollutedEligible = eligible.filter { marker in
            marker.workspaceID == "smoke-routing-ledger" ||
                marker.selectedBy == "smoke" ||
                (marker.model ?? "").lowercased().hasSuffix("-unknown-cost")
        }

        try expect(excludedCount > 0, "ledger should exclude at least one non-production run.")
        try expect(pollutedEligible.isEmpty, "polluted smoke/synthetic runs must not remain eligible.")

        print("Verified local Smart Routing ledger production stats: eligible \(eligible.count), excluded \(excludedCount), total \(markers.count).")
    }

    private static func routeStats(from records: [RecordedRoute]) -> [RouteStats] {
        Dictionary(grouping: records, by: \.routeKey)
            .map { _, values in
                let first = values[0]
                let winCount = values.filter(\.isWin).count
                return RouteStats(
                    providerID: first.providerID,
                    model: first.model,
                    runCount: values.count,
                    winRate: values.isEmpty ? 0 : Double(winCount) / Double(values.count)
                )
            }
            .sorted {
                if $0.runCount != $1.runCount { return $0.runCount > $1.runCount }
                return $0.winRate > $1.winRate
            }
    }

    private static func marker(from raw: [String: Any]) -> SmartRoutingRecommendationMarker {
        SmartRoutingRecommendationMarker(
            taskIntent: raw["taskIntent"] as? String,
            workspaceID: raw["workspaceID"] as? String,
            workspaceName: raw["workspaceName"] as? String,
            sessionID: raw["sessionID"] as? String,
            taskID: raw["taskID"] as? String,
            selectedBy: raw["selectedBy"] as? String,
            model: raw["model"] as? String,
            routingReason: raw["routingReason"] as? String,
            metadata: raw["metadata"] as? [String: String] ?? [:]
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if condition() == false {
            throw VerificationFailure.message(message)
        }
    }
}

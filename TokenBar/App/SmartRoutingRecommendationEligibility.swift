import Foundation

struct SmartRoutingRecommendationMarker: Equatable {
    var taskIntent: String?
    var workspaceID: String?
    var workspaceName: String?
    var sessionID: String?
    var taskID: String?
    var selectedBy: String?
    var model: String?
    var routingReason: String?
    var metadata: [String: String]
}

enum SmartRoutingRecommendationEligibility {
    nonisolated private static let nonProductionWords: Set<String> = ["smoke", "test", "synthetic", "fixture"]
    nonisolated private static let nonProductionIDs: Set<String> = ["smoke-routing-ledger"]
    nonisolated private static let nonProductionMetadataKeys: Set<String> = [
        "fixture",
        "non-production",
        "nonproduction",
        "smoke",
        "synthetic",
        "test",
        "tokenbar.fixture",
        "tokenbar.smoke",
        "tokenbar.synthetic",
        "tokenbar.test"
    ]
    nonisolated private static let truthyMetadataValues: Set<String> = ["1", "true", "yes", "y"]

    nonisolated static func isProductionRecommendationEligible(_ marker: SmartRoutingRecommendationMarker) -> Bool {
        if isNonProductionWord(marker.taskIntent) || isNonProductionWord(marker.selectedBy) {
            return false
        }
        if isNonProductionIdentifier(marker.workspaceID) ||
            isNonProductionIdentifier(marker.workspaceName) ||
            isNonProductionIdentifier(marker.sessionID) ||
            isNonProductionIdentifier(marker.taskID) {
            return false
        }
        if isSyntheticModel(marker.model) || containsExplicitSyntheticReason(marker.routingReason) {
            return false
        }
        return hasNonProductionMetadata(marker.metadata) == false
    }

    nonisolated private static func isNonProductionWord(_ value: String?) -> Bool {
        guard let normalized = normalized(value), normalized.isEmpty == false else { return false }
        return nonProductionWords.contains(normalized)
    }

    nonisolated private static func isNonProductionIdentifier(_ value: String?) -> Bool {
        guard let normalized = normalized(value), normalized.isEmpty == false else { return false }
        if nonProductionIDs.contains(normalized) {
            return true
        }
        for word in nonProductionWords {
            if normalized == word ||
                normalized.hasPrefix("\(word)-") ||
                normalized.hasSuffix("-\(word)") ||
                normalized.contains("-\(word)-") {
                return true
            }
        }
        return false
    }

    nonisolated private static func isSyntheticModel(_ value: String?) -> Bool {
        guard let normalized = normalized(value), normalized.isEmpty == false else { return false }
        return normalized.hasSuffix("-unknown-cost") || normalized.contains("-synthetic-")
    }

    nonisolated private static func containsExplicitSyntheticReason(_ value: String?) -> Bool {
        guard let normalized = normalized(value), normalized.isEmpty == false else { return false }
        return normalized.contains("synthetic") || normalized.contains("smoke")
    }

    nonisolated private static func hasNonProductionMetadata(_ metadata: [String: String]) -> Bool {
        for (key, value) in metadata {
            guard let normalizedKey = normalized(key) else { continue }
            let normalizedValue = normalized(value) ?? ""
            if nonProductionMetadataKeys.contains(normalizedKey) &&
                (normalizedValue.isEmpty || truthyMetadataValues.contains(normalizedValue) || nonProductionWords.contains(normalizedValue)) {
                return true
            }
            if normalizedKey == "environment" || normalizedKey == "env" {
                if nonProductionWords.contains(normalizedValue) {
                    return true
                }
            }
        }
        return false
    }

    nonisolated private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

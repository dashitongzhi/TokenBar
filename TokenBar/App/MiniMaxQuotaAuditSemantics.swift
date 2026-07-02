import Foundation

enum MiniMaxQuotaAuditSemantics {
    static func hasCCSwitchQuotaFallback(
        sourceKindRawValue: String,
        unit: String,
        hasKnownQuotaLimit: Bool
    ) -> Bool {
        sourceKindRawValue == "ccSwitch"
            && unit == "percent"
            && hasKnownQuotaLimit
    }

    static func unavailableAudit(hasCCSwitchQuotaFallback: Bool) -> (action: String, detail: String) {
        if hasCCSwitchQuotaFallback {
            return (
                "quota.fallback",
                "Direct MiniMax key unavailable; using MiniMax Token Plan quota fetched through CC Switch provider key."
            )
        }
        return (
            "quota.needs_key",
            "MiniMax quota refresh skipped because no API key is available"
        )
    }
}

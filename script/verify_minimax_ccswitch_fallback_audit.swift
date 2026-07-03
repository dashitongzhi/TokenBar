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
private enum VerifyMiniMaxCCSwitchFallbackAudit {
    static func main() throws {
        let hasFallback = MiniMaxQuotaAuditSemantics.hasCCSwitchQuotaFallback(
            sourceKindRawValue: "ccSwitch",
            unit: "percent",
            hasKnownQuotaLimit: true
        )
        let hasOnlyRollups = MiniMaxQuotaAuditSemantics.hasCCSwitchQuotaFallback(
            sourceKindRawValue: "ccSwitch",
            unit: "tokens",
            hasKnownQuotaLimit: false
        )
        let hasMissingKey = MiniMaxQuotaAuditSemantics.hasCCSwitchQuotaFallback(
            sourceKindRawValue: "liveUnavailable",
            unit: "percent",
            hasKnownQuotaLimit: false
        )

        try expect(hasFallback, "CC Switch MiniMax percent quota should be treated as a fallback quota source.")
        let fallbackAudit = MiniMaxQuotaAuditSemantics.unavailableAudit(hasCCSwitchQuotaFallback: hasFallback)
        try expect(fallbackAudit.action == "quota.fallback", "fallback audit action should be quota.fallback.")
        try expect(
            fallbackAudit.detail.contains("CC Switch provider key"),
            "fallback audit detail should name the CC Switch provider-key source."
        )
        try expect(
            fallbackAudit.action != "quota.needs_key",
            "fallback audit must not be quota.needs_key when CC Switch quota is valid."
        )

        try expect(hasOnlyRollups == false, "CC Switch token rollups without percent quota should not hide a missing MiniMax key.")
        try expect(hasMissingKey == false, "plain liveUnavailable MiniMax provider should not be treated as a fallback quota source.")
        let missingKeyAudit = MiniMaxQuotaAuditSemantics.unavailableAudit(hasCCSwitchQuotaFallback: hasMissingKey)
        try expect(missingKeyAudit.action == "quota.needs_key", "missing direct and fallback keys should still be quota.needs_key.")

        print("Verified MiniMax CC Switch quota fallback audit semantics.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if condition() == false {
            throw VerificationFailure.message(message)
        }
    }
}

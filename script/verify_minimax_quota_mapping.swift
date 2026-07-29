import Foundation

struct MiniMaxUsageSnapshot {
    static let tokenPlanURL = "https://api.minimaxi.com/v1/token_plan/remains"
}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private enum VerifyMiniMaxQuotaMapping {
    static func main() throws {
        let payload = Data(
            """
            {
              "start_time": 1722124800000,
              "end_time": 1722132000000,
              "current_interval_total_count": 200,
              "current_interval_usage_count": 50,
              "model_name": "general",
              "current_weekly_total_count": 0,
              "current_weekly_usage_count": 0,
              "weekly_start_time": 1722124800000,
              "weekly_end_time": 1722729600000,
              "current_interval_remaining_percent": 75,
              "current_weekly_remaining_percent": 40
            }
            """.utf8
        )
        let item = try JSONDecoder().decode(MiniMaxQuotaItem.self, from: payload)
        let direct = item.quotaWindow()
        let ccSwitch = item.quotaWindow(
            providerID: "minimax",
            providerDisplayName: "MiniMax via CC Switch"
        )

        try expect(direct.intervalUsedPercent == 25, "count-based interval usage must be 25%")
        try expect(direct.weeklyUsedPercent == 60, "remaining-percent fallback must produce 60% used")
        try expect(
            direct.intervalStartAt == Date(timeIntervalSince1970: 1_722_124_800),
            "millisecond timestamps must map to seconds exactly once"
        )
        try expect(direct.providerID == "minimax", "direct mapping must use the canonical provider id")
        try expect(
            ccSwitch.providerDisplayName == "MiniMax via CC Switch",
            "CC Switch mapping may override only provider presentation metadata"
        )
        try expect(
            commonFields(of: direct) == commonFields(of: ccSwitch),
            "direct and CC Switch paths must share identical quota-window semantics"
        )

        print("Verified shared MiniMax quota-window mapping for direct and CC Switch paths.")
    }

    private static func commonFields(of window: MiniMaxQuotaWindow) -> [String] {
        [
            window.modelName,
            String(window.intervalUsedCount),
            String(window.intervalTotalCount),
            String(window.intervalUsedPercent),
            String(describing: window.intervalRemainingPercent),
            String(window.intervalStartAt.timeIntervalSince1970),
            String(window.intervalResetAt.timeIntervalSince1970),
            String(window.weeklyUsedCount),
            String(window.weeklyTotalCount),
            String(window.weeklyUsedPercent),
            String(describing: window.weeklyRemainingPercent),
            String(window.weeklyStartAt.timeIntervalSince1970),
            String(window.weeklyResetAt.timeIntervalSince1970)
        ]
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw VerificationFailure(description: message)
        }
    }
}

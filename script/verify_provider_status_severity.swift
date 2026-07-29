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
private enum VerifyProviderStatusSeverity {
    static func main() throws {
        let quotaCriticalWithWarningAlert = provider(
            current: 95,
            limit: 100,
            healthAlerts: [
                ProviderHealthAlert(
                    status: .warning,
                    title: "Provider latency elevated",
                    detail: "Health probe is slow, but quota is already critical."
                )
            ]
        )
        try expect(
            quotaCriticalWithWarningAlert.status == .critical,
            "warning health alert must not downgrade critical quota status."
        )

        let quotaHealthyWithCriticalAlert = provider(
            current: 10,
            limit: 100,
            healthAlerts: [
                ProviderHealthAlert(
                    status: .critical,
                    title: "Provider unavailable",
                    detail: "Health probe cannot reach the provider."
                )
            ]
        )
        try expect(
            quotaHealthyWithCriticalAlert.status == .critical,
            "critical health alert should upgrade healthy quota status."
        )

        print("Verified ProviderUsage.status severity aggregation.")
    }

    private static func provider(
        current: Double,
        limit: Double,
        healthAlerts: [ProviderHealthAlert]
    ) -> ProviderUsage {
        ProviderUsage(
            id: "regression-provider",
            name: "Regression Provider",
            category: "Test",
            symbolName: "checkmark.circle",
            current: current,
            limit: limit,
            unit: "percent",
            spendToday: 0,
            spendMonth: 0,
            resetAt: Date().addingTimeInterval(3600),
            lastUpdated: Date(),
            history: [],
            dataSource: .ccSwitch,
            sourceDetail: "regression fixture",
            sourceUpdatedAt: Date(),
            tokensToday: nil,
            requestCountToday: nil,
            requestCountMonth: nil,
            currencyCode: nil,
            quotaLimitKnown: true,
            requestCountKnown: false,
            spendTodayKnown: false,
            spendMonthKnown: false,
            healthAlerts: healthAlerts
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if condition() == false {
            throw VerificationFailure.message(message)
        }
    }
}

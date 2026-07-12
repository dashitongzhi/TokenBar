import Foundation

@main
private enum VerifySmartRoutingCostMetrics {
    static func main() throws {
        let average = SmartRoutingCostMetrics.averageCostDelta(observations: [
            SmartRoutingCostObservation(estimated: 10, actual: nil),
            SmartRoutingCostObservation(estimated: 20, actual: 30)
        ])
        guard average == 10 else {
            throw VerificationFailure("average cost delta must use only records with both costs")
        }
        let tokenAverage = SmartRoutingCostMetrics.averageTokenDelta(observations: [
            SmartRoutingTokenObservation(estimated: 1_000, actual: nil),
            SmartRoutingTokenObservation(estimated: 2_000, actual: 3_000)
        ])
        guard tokenAverage == 1_000 else {
            throw VerificationFailure("average token delta must use only records with both token values")
        }
        print("Verified Smart Routing cost deltas exclude records with unknown actual costs.")
    }
}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

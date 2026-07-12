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
        print("Verified Smart Routing cost deltas exclude records with unknown actual costs.")
    }
}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

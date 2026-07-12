import Foundation

struct SmartRoutingCostObservation: Equatable {
    var estimated: Double?
    var actual: Double?
}

enum SmartRoutingCostMetrics {
    static func averageCostDelta(observations: [SmartRoutingCostObservation]) -> Double {
        let knownCostPairs = observations.compactMap { observation -> Double? in
            guard let estimated = observation.estimated, let actual = observation.actual else { return nil }
            return actual - estimated
        }
        guard knownCostPairs.isEmpty == false else { return 0 }
        return knownCostPairs.reduce(0, +) / Double(knownCostPairs.count)
    }
}

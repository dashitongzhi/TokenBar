import Foundation

struct SmartRoutingCostObservation: Equatable {
    var estimated: Double?
    var actual: Double?
}

struct SmartRoutingTokenObservation: Equatable {
    var estimated: Int?
    var actual: Int?
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

extension SmartRoutingCostMetrics {
    static func averageTokenDelta(observations: [SmartRoutingTokenObservation]) -> Double {
        let knownTokenPairs = observations.compactMap { observation -> Int? in
            guard let estimated = observation.estimated, let actual = observation.actual else { return nil }
            return actual - estimated
        }
        guard knownTokenPairs.isEmpty == false else { return 0 }
        return Double(knownTokenPairs.reduce(0, +)) / Double(knownTokenPairs.count)
    }
}

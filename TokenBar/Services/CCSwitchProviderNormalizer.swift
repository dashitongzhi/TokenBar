import Foundation

enum CCSwitchProviderNormalizer {
    static func normalize(
        rollup: CCSwitchDailyRollup,
        recordsByCompositeID: [String: CCSwitchProviderRecord],
        recordsByID: [String: [CCSwitchProviderRecord]]
    ) -> CCSwitchKnownProvider? {
        if let record = recordsByCompositeID["\(rollup.appType):\(rollup.providerID)"],
           let provider = normalize(record: record) {
            return provider
        }
        if let record = recordsByID[rollup.providerID]?.first,
           let provider = normalize(record: record) {
            return provider
        }

        return normalize(
            haystack: "\(rollup.providerID) \(rollup.appType) \(rollup.model)",
            includesMiniMaxI: false
        )
    }

    static func normalize(record: CCSwitchProviderRecord) -> CCSwitchKnownProvider? {
        normalize(
            haystack: [
                record.id,
                record.name,
                record.appType,
                record.baseURL ?? "",
                record.modelNames.joined(separator: " ")
            ].joined(separator: " "),
            includesMiniMaxI: true
        )
    }

    private static func normalize(haystack: String, includesMiniMaxI: Bool) -> CCSwitchKnownProvider? {
        let haystack = haystack.lowercased()
        if haystack.contains("deepseek") { return .deepSeek }
        if haystack.contains("minimax") || haystack.contains("mini-max") || (includesMiniMaxI && haystack.contains("minimaxi")) { return .miniMax }
        if haystack.contains("mimo") || haystack.contains("xiaomi") { return .xiaomiMiMo }
        if haystack.contains("glm") { return .glm }
        if haystack.contains("openai") || haystack.contains("gpt") || haystack.contains("o1") || haystack.contains("o3") || haystack.contains("o4") { return .openAI }
        if haystack.contains("anthropic") || haystack.contains("claude") { return .anthropic }
        return nil
    }
}

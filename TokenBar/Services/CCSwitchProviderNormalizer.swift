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

        return normalize(haystack: rollup.providerID, includesMiniMaxI: true)
            ?? normalize(haystack: rollup.model, includesMiniMaxI: false)
    }

    static func normalize(record: CCSwitchProviderRecord) -> CCSwitchKnownProvider? {
        if let host = record.baseURL.flatMap({ URLComponents(string: $0)?.host?.lowercased() }) {
            if ["api.deepseek.com"].contains(host) { return .deepSeek }
            if ["api.minimaxi.com", "api.minimax.io"].contains(host) { return .miniMax }
            if ["api.openai.com"].contains(host) { return .openAI }
            if ["api.anthropic.com"].contains(host) { return .anthropic }
        }

        // appType identifies the consuming client (for example Claude or
        // Codex), not the upstream provider, so it must not influence vendor
        // classification.
        let identity = [record.id, record.name].joined(separator: " ")
        let identityProviders = providers(in: identity, includesMiniMaxI: true)
        if identityProviders.count == 1 {
            return identityProviders.first
        }
        if identityProviders.count > 1 {
            return nil
        }

        let modelProviders = record.modelNames.reduce(into: Set<CCSwitchKnownProvider>()) {
            $0.formUnion(providers(in: $1, includesMiniMaxI: false))
        }
        // A proxy or aggregator may advertise models from several vendors.
        // Treating the entire record as the first matching vendor misattributes
        // all rollups and may select the wrong live-quota credential. When the
        // record is heterogeneous, normalize each rollup from its model instead.
        return modelProviders.count == 1 ? modelProviders.first : nil
    }

    private static func normalize(haystack: String, includesMiniMaxI: Bool) -> CCSwitchKnownProvider? {
        let candidates = providers(in: haystack, includesMiniMaxI: includesMiniMaxI)
        return [
            .deepSeek,
            .miniMax,
            .xiaomiMiMo,
            .glm,
            .openAI,
            .anthropic
        ].first(where: candidates.contains)
    }

    private static func providers(
        in haystack: String,
        includesMiniMaxI: Bool
    ) -> Set<CCSwitchKnownProvider> {
        let normalized = haystack.lowercased()
        let tokens = Set(normalized.split(whereSeparator: { $0.isLetter == false && $0.isNumber == false }).map(String.init))
        var providers = Set<CCSwitchKnownProvider>()
        if tokens.contains("deepseek") { providers.insert(.deepSeek) }
        if tokens.contains("minimax") || (tokens.contains("mini") && tokens.contains("max")) || (includesMiniMaxI && tokens.contains("minimaxi")) {
            providers.insert(.miniMax)
        }
        if tokens.contains("mimo") || tokens.contains("xiaomi") { providers.insert(.xiaomiMiMo) }
        if tokens.contains("glm") { providers.insert(.glm) }
        if tokens.contains("openai") || tokens.contains("gpt") || ["o1", "o3", "o4"].contains(where: tokens.contains) {
            providers.insert(.openAI)
        }
        if tokens.contains("anthropic") || tokens.contains("claude") { providers.insert(.anthropic) }
        return providers
    }
}

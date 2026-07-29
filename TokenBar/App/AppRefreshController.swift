import Foundation

@MainActor
final class AppRefreshController {
    private let providerModule: ProviderRefreshModule

    init(providerModule: ProviderRefreshModule? = nil) {
        self.providerModule = providerModule ?? ProviderRefreshModule()
    }

    func refresh(
        providers: [ProviderUsage],
        includeCCSwitchOfficialQuotaProbes: Bool
    ) async -> ProviderRefreshOutcome {
        await providerModule.refresh(
            providers: providers,
            includeCCSwitchOfficialQuotaProbes: includeCCSwitchOfficialQuotaProbes
        )
    }
}

import Foundation

@MainActor
extension AppState {
    func refreshModelCatalog(providerID: String? = nil, baseURL: String? = nil) {
        guard isRefreshingModelCatalog == false else { return }
        let targetProviderID = providerID ?? selectedProviderID
        isRefreshingModelCatalog = true
        modelCatalogMessage = localized("modelCatalogRefreshing")

        Task {
            let remote = await providerModelCatalogService.fetch(providerID: targetProviderID, baseURL: baseURL)
            await MainActor.run { self.applyModelCatalogResult(remote, providerID: targetProviderID) }
        }
    }

    func modelCatalog(for providerID: String) -> [ModelCatalogItem] {
        modelCatalogItems
            .filter { $0.providerID == providerID || providerAliases(providerID).contains($0.providerID) }
            .sorted { lhs, rhs in
                if lhs.source != rhs.source { return sourceRank(lhs.source) < sourceRank(rhs.source) }
                return lhs.modelID.localizedStandardCompare(rhs.modelID) == .orderedAscending
            }
    }

    func addProvider(template: ProbeTemplate) {
        guard providers.contains(where: { $0.id == template.platform }) == false else { return }
        providers.append(AppSeedData.provider(
            id: template.platform,
            name: template.displayName,
            category: template.category,
            symbol: template.symbolName,
            current: 0,
            limit: 10_000,
            unit: template.unit,
            spendToday: 0,
            spendMonth: 0,
            resetHours: 24 * 14
        ))
        selectedProviderID = template.platform
        addAudit(provider: template.displayName, action: "provider.add", detail: "Provider metadata added; API key belongs in Keychain")
        persistProviders()
    }

    func reloadModelUsageRollups() {
        mergeModelUsageRollups(localUsageIngestionModule.loadModelUsageRollups())
    }

    func reloadModelCatalogFromLocalSources() {
        let localItems = agentModelConfigurationService.readConfiguredModelCatalogItems()
            + ccSwitchUsageService.configuredModelCatalogItems()
        mergeModelCatalogItems(localItems, replacingProviderID: nil)
    }

    func mergeModelUsageRollups(_ localRows: [ModelUsageRollup]) {
        let configuredRows = agentModelConfigurationService.readConfiguredModels()
        let localKeys = Set(localRows.map { modelUsageMergeKey($0) })
        let visibleConfiguredRows = configuredRows.filter { localKeys.contains(modelUsageMergeKey($0)) == false }
        modelUsageRollups = localRows + visibleConfiguredRows
    }

    func ensureProviderExists(providerID: String) {
        guard providers.contains(where: { $0.id == providerID }) == false else { return }
        if let seed = AppSeedData.providers().first(where: { $0.id == providerID }) {
            let seedOrder = AppSeedData.providers().firstIndex(where: { $0.id == providerID }) ?? providers.count
            providers.insert(seed, at: min(seedOrder, providers.count))
            return
        }
        providers.append(AppSeedData.provider(
            id: providerID,
            name: titleFromWorkspaceID(providerID),
            category: "AI & API",
            symbol: "network",
            current: 0,
            limit: 0,
            unit: "tokens",
            spendToday: 0,
            spendMonth: 0,
            resetHours: 24 * 30,
            dataSource: .localAgent,
            sourceDetail: "Local agent usage was ingested through TokenBar's local API."
        ))
    }

    private func applyModelCatalogResult(_ result: ProviderModelCatalogResult, providerID: String) {
        isRefreshingModelCatalog = false
        switch result {
        case .success(let items):
            mergeModelCatalogItems(items, replacingProviderID: providerID)
            modelCatalogMessage = items.isEmpty ? localized("modelCatalogEmpty") : String(format: localized("modelCatalogLoadedFormat"), items.count)
            addAudit(provider: providerID, action: "models.refresh", detail: "Fetched \(items.count) models")
        case .unavailable(let detail):
            modelCatalogMessage = detail
            addAudit(provider: providerID, action: "models.unavailable", detail: detail)
        case .failure(let detail):
            modelCatalogMessage = detail
            addAudit(provider: providerID, action: "models.error", detail: detail)
        }
        notifyStatusBarUpdate()
    }

    func mergeModelCatalogItems(_ items: [ModelCatalogItem], replacingProviderID: String?) {
        var merged = modelCatalogItems
        if let replacingProviderID {
            let aliases = providerAliases(replacingProviderID).union([replacingProviderID])
            merged.removeAll { aliases.contains($0.providerID) && $0.source == .providerAPI }
        }
        merged.append(contentsOf: items)

        var bestByKey: [String: ModelCatalogItem] = [:]
        for item in merged where item.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let key = [item.providerID, item.modelID.lowercased()].joined(separator: "|")
            if let existing = bestByKey[key] {
                if sourceRank(item.source) < sourceRank(existing.source) { bestByKey[key] = item }
            } else {
                bestByKey[key] = item
            }
        }
        modelCatalogItems = bestByKey.values.sorted {
            if $0.providerID != $1.providerID { return $0.providerID < $1.providerID }
            if $0.source != $1.source { return sourceRank($0.source) < sourceRank($1.source) }
            return $0.modelID.localizedStandardCompare($1.modelID) == .orderedAscending
        }
    }

    private func modelUsageMergeKey(_ rollup: ModelUsageRollup) -> String {
        [rollup.agent.rawValue, rollup.providerID, rollup.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()].joined(separator: "|")
    }

    private func sourceRank(_ source: ModelCatalogSource) -> Int {
        switch source {
        case .providerAPI: 0
        case .ccSwitchConfig: 1
        case .localAgentConfig: 2
        }
    }

    private func providerAliases(_ providerID: String) -> Set<String> {
        switch providerID {
        case "google", "gemini": ["google", "gemini"]
        case "ccswitch-codex", "codex": ["ccswitch-codex", "codex", "openai"]
        default: [providerID]
        }
    }
}

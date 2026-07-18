import Foundation

struct WorkspacePolicyStore {
    private let document: JSONDocumentStore<[WorkspacePolicy]>

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        document = JSONDocumentStore(
            fileName: "workspace-policies.json",
            fileManager: fileManager,
            directoryURL: directoryURL
        )
    }

    func load(defaults: [WorkspacePolicy]) -> [WorkspacePolicy] {
        let saved: [WorkspacePolicy]
        switch document.load() {
        case .missing:
            var normalizedDefaults = defaults
            if normalizeExpiredSpendBuckets(in: &normalizedDefaults) {
                save(normalizedDefaults)
            }
            return normalizedDefaults
        case .unreadable:
            var normalizedDefaults = defaults
            _ = normalizeExpiredSpendBuckets(in: &normalizedDefaults)
            return normalizedDefaults
        case .loaded(let policies):
            saved = policies
        }

        var changed = false
        var merged = saved.filter { policy in
            let keep = Self.demoSeedIDs.contains(policy.id) == false
            if keep == false { changed = true }
            return keep
        }
        for defaultPolicy in defaults {
            if let index = merged.firstIndex(where: { $0.id == defaultPolicy.id }) {
                let updated = Self.mergeInferredDefaults(into: merged[index], defaultPolicy: defaultPolicy)
                if updated != merged[index] {
                    merged[index] = updated
                    changed = true
                }
            } else {
                merged.append(defaultPolicy)
                changed = true
            }
        }
        if normalizeExpiredSpendBuckets(in: &merged) {
            changed = true
        }
        if changed {
            save(merged)
        }
        return merged
    }

    func save(_ policies: [WorkspacePolicy]) {
        try? document.save(policies)
    }

    private static let demoSeedIDs: Set<String> = ["client-app", "personal-lab", "production-fix"]

    private func normalizeExpiredSpendBuckets(in policies: inout [WorkspacePolicy]) -> Bool {
        var changed = false
        for index in policies.indices {
            let didReset = policies[index].resetExpiredSpendBuckets()
            changed = didReset || changed
        }
        return changed
    }

    private static func mergeInferredDefaults(into saved: WorkspacePolicy, defaultPolicy: WorkspacePolicy) -> WorkspacePolicy {
        var merged = saved
        if merged.preferredProviderID?.isEmpty != false {
            merged.preferredProviderID = defaultPolicy.preferredProviderID
        }
        if merged.preferredModel?.isEmpty != false {
            merged.preferredModel = defaultPolicy.preferredModel
        }
        if merged.setupSourceDetail?.isEmpty != false {
            merged.setupSourceDetail = defaultPolicy.setupSourceDetail
        }
        if merged.configuredModelCount == nil {
            merged.configuredModelCount = defaultPolicy.configuredModelCount
        }
        if merged.inferredFromPaths?.isEmpty != false {
            merged.inferredFromPaths = defaultPolicy.inferredFromPaths
        }
        if merged.maxEstimatedRunCost <= 0, defaultPolicy.maxEstimatedRunCost > 0 {
            merged.maxEstimatedRunCost = defaultPolicy.maxEstimatedRunCost
        }
        if merged.allowedProviderIDs.isEmpty {
            merged.allowedProviderIDs = defaultPolicy.allowedProviderIDs
        }
        return merged
    }
}

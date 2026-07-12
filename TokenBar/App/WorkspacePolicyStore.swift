import Foundation

struct WorkspacePolicyStore {
    private let storeURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("TokenBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("workspace-policies.json")
    }

    func load(defaults: [WorkspacePolicy]) -> [WorkspacePolicy] {
        guard let data = try? Data(contentsOf: storeURL) else {
            var normalizedDefaults = defaults
            if normalizeExpiredSpendBuckets(in: &normalizedDefaults) {
                save(normalizedDefaults)
            }
            return normalizedDefaults
        }
        guard let saved = try? JSONDecoder.tokenBar.decode([WorkspacePolicy].self, from: data) else {
            save(defaults)
            return defaults
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
        guard let data = try? JSONEncoder.tokenBar.encode(policies) else { return }
        try? data.write(to: storeURL, options: [.atomic])
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

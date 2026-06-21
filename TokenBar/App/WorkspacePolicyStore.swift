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
        guard let data = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder.tokenBar.decode([WorkspacePolicy].self, from: data) else {
            return defaults
        }

        var merged = saved
        for defaultPolicy in defaults where merged.contains(where: { $0.id == defaultPolicy.id }) == false {
            merged.append(defaultPolicy)
        }
        return merged
    }

    func save(_ policies: [WorkspacePolicy]) {
        guard let data = try? JSONEncoder.tokenBar.encode(policies) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }
}

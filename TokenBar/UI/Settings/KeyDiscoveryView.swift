import SwiftUI

struct KeyDiscoveryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var discovered: [DiscoveredKey] = []
    @State private var isScanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appState.localized("localFirst"))
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                scan()
            } label: {
                Label(appState.localized("scan"), systemImage: "magnifyingglass")
            }
            .disabled(isScanning)

            if discovered.isEmpty {
                ContentUnavailableView(
                    appState.localized("noKeysFound"),
                    systemImage: "key.slash",
                    description: Text("~/.zshrc, ~/.bashrc, ~/.env, ~/project/*/.env")
                )
            } else {
                List(discovered) { key in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(key.provider)
                                .font(.headline)
                            Spacer()
                            Text(key.variableName)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text("\(key.file):\(key.line)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }

    private func scan() {
        isScanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls = [
            home.appendingPathComponent(".zshrc"),
            home.appendingPathComponent(".bashrc"),
            home.appendingPathComponent(".bash_profile"),
            home.appendingPathComponent(".zprofile"),
            home.appendingPathComponent(".env")
        ]
        let project = home.appendingPathComponent("project")
        if let envFiles = try? FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: nil) {
            urls.append(contentsOf: envFiles.map { $0.appendingPathComponent(".env") })
        }

        Task {
            let results = await WorkspaceDiscovery().scan(paths: urls)
            await MainActor.run {
                discovered = results
                isScanning = false
            }
        }
    }
}

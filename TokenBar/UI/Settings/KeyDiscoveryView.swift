import AppKit
import SwiftUI

struct KeyDiscoveryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var discovered: [DiscoveredKey] = []
    @State private var isScanning = false
    @State private var includeShellProfiles = false
    @State private var includeHomeEnv = false
    @State private var selectedTargets: [DiscoveryTarget] = []
    @State private var hasScanned = false
    @State private var importingKeyIDs: Set<String> = []
    @State private var importMessages: [String: String] = [:]

    private var scanTargets: [DiscoveryTarget] {
        let home = UserHomeDirectory.url
        var targets: [DiscoveryTarget] = []

        if includeShellProfiles {
            targets.append(contentsOf: [
                DiscoveryTarget(url: home.appendingPathComponent(".zshrc"), sourceLabel: "~/.zshrc"),
                DiscoveryTarget(url: home.appendingPathComponent(".zprofile"), sourceLabel: "~/.zprofile"),
                DiscoveryTarget(url: home.appendingPathComponent(".bashrc"), sourceLabel: "~/.bashrc"),
                DiscoveryTarget(url: home.appendingPathComponent(".bash_profile"), sourceLabel: "~/.bash_profile")
            ])
        }

        if includeHomeEnv {
            targets.append(DiscoveryTarget(url: home.appendingPathComponent(".env"), sourceLabel: "~/.env"))
        }

        targets.append(contentsOf: selectedTargets)
        return Array(Set(targets)).sorted { $0.sourceLabel < $1.sourceLabel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(appState.localized("keyDiscoveryTitle"))
                    .font(.headline)
                Text(appState.localized("keyDiscoveryCaption"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(appState.localized("scanShellProfiles"), isOn: $includeShellProfiles)
                    Toggle(appState.localized("scanHomeEnv"), isOn: $includeHomeEnv)

                    Divider()

                    HStack {
                        Button {
                            addFiles()
                        } label: {
                            Label(appState.localized("addFiles"), systemImage: "doc.badge.plus")
                        }

                        Button {
                            addFolderEnv()
                        } label: {
                            Label(appState.localized("addFolderEnv"), systemImage: "folder.badge.plus")
                        }
                    }

                    if selectedTargets.isEmpty == false {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(appState.localized("selectedLocations"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(selectedTargets) { target in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(target.sourceLabel)
                                        .font(.caption)
                                    Spacer()
                                    Button {
                                        selectedTargets.removeAll { $0.id == target.id }
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(appState.localized("removeLocation"))
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            } label: {
                Label(appState.localized("scanTargets"), systemImage: "scope")
            }

            HStack(spacing: 10) {
                Button {
                    scan()
                } label: {
                    Label(appState.localized("scanSelected"), systemImage: "magnifyingglass")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isScanning || scanTargets.isEmpty)

                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(appState.localized("keyDiscoveryPrivacyNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hasScanned == false {
                ContentUnavailableView(
                    appState.localized("chooseScanTargets"),
                    systemImage: "hand.raised",
                    description: Text(appState.localized("chooseScanTargetsDescription"))
                )
            } else if discovered.isEmpty {
                ContentUnavailableView(
                    appState.localized("noKeysFound"),
                    systemImage: "key.slash",
                    description: Text(appState.localized("noKeysFoundDescription"))
                )
            } else {
                List(discovered) { key in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(key.provider)
                                    .font(.headline)
                                Spacer()
                                Text(key.variableName)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(key.locationSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let message = importMessages[key.id] {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 8)

                        if canImport(key) {
                            if importingKeyIDs.contains(key.id) {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button {
                                    importKey(key)
                                } label: {
                                    Label(appState.localized("importKey"), systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.bordered)
                                .help(importHelp(for: key))
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func scan() {
        isScanning = true
        let targets = scanTargets

        Task {
            let results = await WorkspaceDiscovery().scan(targets: targets)
            await MainActor.run {
                discovered = results
                isScanning = false
                hasScanned = true
            }
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.message = appState.localized("addFilesPanelMessage")

        guard panel.runModal() == .OK else { return }
        appendTargets(
            panel.urls.map { url in
                DiscoveryTarget(url: url, sourceLabel: url.lastPathComponent)
            }
        )
    }

    private func addFolderEnv() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = appState.localized("addFolderPanelMessage")

        guard panel.runModal() == .OK else { return }
        appendTargets(
            panel.urls.map { url in
                DiscoveryTarget(
                    url: url.appendingPathComponent(".env"),
                    sourceLabel: "\(url.lastPathComponent)/.env"
                )
            }
        )
    }

    private func appendTargets(_ targets: [DiscoveryTarget]) {
        var merged = selectedTargets
        for target in targets where merged.contains(target) == false {
            merged.append(target)
        }
        selectedTargets = merged.sorted { $0.sourceLabel < $1.sourceLabel }
    }

    private func canImport(_ key: DiscoveredKey) -> Bool {
        importActionName(for: key) != nil
    }

    private func importHelp(for key: DiscoveredKey) -> String {
        guard let actionName = importActionName(for: key) else {
            return appState.localized("keyDiscoveryImportUnsupported")
        }
        return String(format: appState.localized("keyDiscoveryImportHelpFormat"), key.variableName, actionName)
    }

    private func importActionName(for key: DiscoveredKey) -> String? {
        switch key.provider {
        case "OpenAI":
            return "OPENAI_ADMIN_KEY"
        case "Anthropic":
            return "ANTHROPIC_ADMIN_KEY"
        case "OpenRouter":
            return "OPENROUTER_API_KEY"
        default:
            return nil
        }
    }

    private func importKey(_ key: DiscoveredKey) {
        guard importingKeyIDs.contains(key.id) == false else { return }
        importingKeyIDs.insert(key.id)
        importMessages[key.id] = appState.localized("keyDiscoveryImporting")

        Task {
            do {
                try await store(key)
                await MainActor.run {
                    importingKeyIDs.remove(key.id)
                    importMessages[key.id] = String(
                        format: appState.localized("keyDiscoveryImportedFormat"),
                        key.provider,
                        key.variableName
                    )
                }
            } catch {
                await MainActor.run {
                    importingKeyIDs.remove(key.id)
                    importMessages[key.id] = String(
                        format: appState.localized("keyDiscoveryImportFailedFormat"),
                        error.localizedDescription
                    )
                }
            }
        }
    }

    private func store(_ key: DiscoveredKey) async throws {
        switch key.provider {
        case "OpenAI":
            try await appState.storeOpenAIAdminKey(key.secretValue)
        case "Anthropic":
            try await appState.storeAnthropicAdminKey(key.secretValue)
        case "OpenRouter":
            try await appState.storeOpenRouterAPIKey(key.secretValue)
        default:
            throw KeyDiscoveryImportError.unsupportedProvider
        }
    }
}

private enum KeyDiscoveryImportError: LocalizedError {
    case unsupportedProvider

    var errorDescription: String? {
        "This provider cannot be imported into live settings yet."
    }
}

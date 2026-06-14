import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(appState.localized("statusBar"), systemImage: "menubar.rectangle") }

            PlatformSettingsView()
                .tabItem { Label(appState.localized("platforms"), systemImage: "square.grid.2x2") }

            VStack(spacing: 14) {
                FocusBudgetView()
                AuditPanel(limit: nil)
            }
            .padding()
            .tabItem { Label(appState.localized("privacyAudit"), systemImage: "lock.shield") }

            KeyDiscoveryView()
                .tabItem { Label(appState.localized("keyDiscovery"), systemImage: "key.viewfinder") }
        }
        .padding(12)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker(appState.localized("language"), selection: $appState.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Picker(appState.localized("content"), selection: $appState.statusBarContent) {
                    ForEach(StatusBarContent.allCases) { content in
                        Text(content.title(language: appState.language)).tag(content)
                    }
                }

                Picker(appState.localized("provider"), selection: $appState.selectedProviderID) {
                    ForEach(appState.providers) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }

                TextField(appState.localized("customText"), text: $appState.customStatusText)
            } header: {
                Text(appState.localized("statusBar"))
            }

            Section {
                AppIconPickerView()
            } header: {
                Text(appState.localized("appIcon"))
            }

            Section {
                Toggle(appState.localized("focusMode"), isOn: $appState.focusModeEnabled)
                HStack {
                    Text(appState.localized("sessionBudget"))
                    Slider(value: $appState.sessionBudget, in: 1...50, step: 1)
                    Text("$\(Int(appState.sessionBudget))")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }

            Section {
                Toggle(appState.localized("mcp"), isOn: $appState.localAPIEnabled)
                LocalAPIStatusRow()
                Text(appState.localized("mcpCaption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.localized("localFirst"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LocalAPIStatusRow: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: appState.localAPIStatus.symbolName)
                .foregroundStyle(appState.localAPIStatus.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.localAPIStatusTitle)
                    .font(.caption.weight(.semibold))
                Text(appState.localAPIStatusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text(appState.localAPISummaryValue)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(appState.localAPIStatus.color)
        }
        .padding(.vertical, 2)
    }
}

private struct AppIconPickerView: View {
    @EnvironmentObject private var appState: AppState

    private let columns = [
        GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(AppIconChoice.allCases) { icon in
                Button {
                    appState.selectedAppIcon = icon
                } label: {
                    VStack(spacing: 8) {
                        Image(icon.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text(icon.title(language: appState.language))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                appState.selectedAppIcon == icon ? Color.accentColor : Color.secondary.opacity(0.24),
                                lineWidth: appState.selectedAppIcon == icon ? 2 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon.title(language: appState.language))
            }
        }
    }
}

private struct PlatformSettingsView: View {
    @EnvironmentObject private var appState: AppState

    private let templates: [ProbeTemplate] = ProbeTemplateLoader.builtInTemplates()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appState.localized("liveUsageCaption"))
                .font(.callout)
                .foregroundStyle(.secondary)

            OpenAIAdminKeyPanel()

            List {
                Section(appState.localized("platforms")) {
                    ForEach(appState.providers) { provider in
                        HStack {
                            Image(systemName: provider.symbolName)
                                .foregroundStyle(provider.status.color)
                                .frame(width: 22)
                            VStack(alignment: .leading) {
                                Text(provider.name)
                                Text(provider.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                SourcePill(source: provider.sourceKind)
                                Text("$\(appState.formatMoney(provider.spendMonth))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section(appState.localized("addProvider")) {
                    ForEach(templates) { template in
                        Button {
                            appState.addProvider(template: template)
                        } label: {
                            Label(template.displayName, systemImage: template.symbolName)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

private struct OpenAIAdminKeyPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var adminKey = ""
    @State private var message = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized("openAILiveUsage"), systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                if let openAI = appState.providers.first(where: { $0.id == "openai" }) {
                    SourcePill(source: openAI.sourceKind)
                }
            }

            HStack(spacing: 8) {
                SecureField(appState.localized("openAIAdminKey"), text: $adminKey)
                    .textFieldStyle(.roundedBorder)

                Button {
                    save()
                } label: {
                    Label(appState.localized("save"), systemImage: "key.fill")
                }
                .disabled(isSaving || adminKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    clear()
                } label: {
                    Label(appState.localized("clear"), systemImage: "trash")
                }
                .disabled(isSaving)

                Button {
                    appState.refreshAll()
                } label: {
                    Label(appState.localized("refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshingUsage)
            }

            if message.isEmpty == false {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let openAI = appState.providers.first(where: { $0.id == "openai" }) {
                Text(openAI.sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func save() {
        let trimmed = adminKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        isSaving = true
        Task {
            do {
                try await appState.storeOpenAIAdminKey(trimmed)
                await MainActor.run {
                    adminKey = ""
                    message = appState.localized("openAIKeySaved")
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func clear() {
        isSaving = true
        Task {
            do {
                try await appState.clearOpenAIAdminKey()
                await MainActor.run {
                    message = appState.localized("openAIKeyCleared")
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

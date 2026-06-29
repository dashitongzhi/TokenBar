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

                Picker(appState.localized("routingMode"), selection: $appState.routingMode) {
                    ForEach(RoutingMode.allCases) { mode in
                        Label(mode.title(language: appState.language), systemImage: mode.symbolName).tag(mode)
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
                    Slider(value: $appState.sessionBudget, in: 0...50, step: 1)
                    Text(appState.sessionBudget > 0 ? "$\(Int(appState.sessionBudget))" : appState.localized("off"))
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

            LiveProviderCredentialPanels()

            ModelCatalogSettingsPreview()

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
                                Text(provider.hasKnownSpendMonth ? "$\(appState.formatMoney(provider.spendMonth))" : "-")
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

private struct ModelCatalogSettingsPreview: View {
    @EnvironmentObject private var appState: AppState

    private var rows: [ModelCatalogItem] {
        Array(appState.modelCatalogItems.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized("modelCatalog"), systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Button {
                    appState.refreshModelCatalog()
                } label: {
                    Label(appState.localized("pullModels"), systemImage: "arrow.down.circle")
                }
                .disabled(appState.isRefreshingModelCatalog)
            }

            Text(appState.modelCatalogMessage.isEmpty ? appState.localized("modelCatalogHelp") : appState.modelCatalogMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if rows.isEmpty == false {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Text(row.modelID)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(row.providerID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text(row.source.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

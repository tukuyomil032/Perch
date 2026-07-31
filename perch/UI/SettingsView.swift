import Defaults
import SwiftUI

struct SettingsView: View {
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.autoCollapseDelay) var autoCollapseDelay
    @Default(.showInAllSpaces) var showInAllSpaces
    @Default(.languageCode) var languageCode

    var body: some View {
        TabView {
            GeneralTab(launchAtLogin: $launchAtLogin, showInAllSpaces: $showInAllSpaces)
                .tabItem { Label(L10n.string("settings.general"), systemImage: "gearshape") }
            IslandTab(autoCollapseDelay: $autoCollapseDelay)
                .tabItem { Label(L10n.string("settings.island"), systemImage: "rectangle.topthird.inset.filled") }
            NowPlayingTab()
                .tabItem { Label(L10n.string("settings.nowplaying"), systemImage: "music.note") }
            LanguageTab(languageCode: $languageCode)
                .tabItem { Label(L10n.string("settings.language"), systemImage: "globe") }
            AIUsageTab()
                .tabItem { Label(L10n.string("settings.ai_usage"), systemImage: "cpu") }
            PermissionsTab()
                .tabItem { Label(L10n.string("settings.permissions"), systemImage: "checkmark.shield") }
            SettingsUpdateTab()
                .tabItem { Label(L10n.string("settings.updates"), systemImage: "arrow.down.circle") }
        }
        .frame(width: 600, height: 360)
        .id(languageCode)
    }
}

private struct GeneralTab: View {
    @Binding var launchAtLogin: Bool
    @Binding var showInAllSpaces: Bool

    var body: some View {
        Form {
            Toggle(L10n.string("settings.launch_at_login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItemManager.setEnabled(newValue)
                }
            Toggle(L10n.string("settings.show_all_spaces"), isOn: $showInAllSpaces)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct IslandTab: View {
    @Binding var autoCollapseDelay: Double
    @Default(.islandChromeStyle) private var islandChromeStyle
    @Default(.uiMode) private var uiMode

    var body: some View {
        Form {
            Section(L10n.string("settings.island_position")) {
                Picker(L10n.string("settings.island_position"), selection: $islandChromeStyle) {
                    ForEach(IslandChromeStyle.allCases, id: \.self) { style in
                        Text(L10n.string(style.displayNameKey)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(L10n.string("settings.ui_mode")) {
                Picker(L10n.string("settings.ui_mode"), selection: $uiMode) {
                    ForEach(UIMode.allCases, id: \.self) { mode in
                        Text(L10n.string(mode.displayNameKey)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Slider(value: $autoCollapseDelay, in: 1.0...10.0, step: 0.5) {
                Text(L10n.string("settings.auto_collapse"))
            } minimumValueLabel: {
                Text("1s")
            } maximumValueLabel: {
                Text("10s")
            }
            Text("\(autoCollapseDelay, specifier: "%.1f") seconds")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct NowPlayingTab: View {
    @Default(.preferredNowPlayingSource) private var preferredNowPlayingSource

    var body: some View {
        Form {
            Section(L10n.string("settings.sources")) {
                Picker(L10n.string("settings.nowplaying_source"), selection: $preferredNowPlayingSource) {
                    ForEach(NowPlayingSourcePreference.allCases) { source in
                        Text(L10n.string(source.displayNameKey)).tag(source)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PermissionsTab: View {
    @State private var store = PermissionsStore()

    var body: some View {
        Form {
            Section(L10n.string("settings.permissions.section")) {
                ForEach(PermissionsStore.Kind.allCases) { kind in
                    row(for: kind)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { store.refreshAll() }
    }

    @ViewBuilder
    private func row(for kind: PermissionsStore.Kind) -> some View {
        let status = store.statuses[kind] ?? .notDetermined
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                Text(statusLabel(status))
                    .font(.caption)
                    .foregroundStyle(statusColor(status))
            }
            Spacer()
            if status != .authorized {
                Button(actionLabel(status)) {
                    Task { await store.request(kind) }
                }
            }
        }
    }

    private func statusLabel(_ status: PermissionsStore.PermissionStatus) -> String {
        switch status {
        case .authorized: L10n.string("settings.permissions.status.authorized")
        case .notDetermined: L10n.string("settings.permissions.status.not_determined")
        case .denied: L10n.string("settings.permissions.status.denied")
        case .unknown: L10n.string("settings.permissions.status.unknown")
        }
    }

    private func statusColor(_ status: PermissionsStore.PermissionStatus) -> Color {
        switch status {
        case .authorized: .green
        case .notDetermined: .yellow
        case .denied: .red
        case .unknown: .secondary
        }
    }

    private func actionLabel(_ status: PermissionsStore.PermissionStatus) -> String {
        status == .denied
            ? L10n.string("settings.permissions.open_system_settings")
            : L10n.string("settings.permissions.request")
    }
}

private struct LanguageTab: View {
    @Binding var languageCode: String

    var body: some View {
        Form {
            Picker(L10n.string("settings.language_picker"), selection: $languageCode) {
                Text("English").tag("en")
                Text("日本語").tag("ja")
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AIUsageTab: View {
    @Environment(AppState.self) private var appState
    @State private var openAIKey = ""
    @State private var openRouterKey = ""
    @State private var openRouterMgmtKey = ""

    @Default(.aiUsageShowRemaining) private var showRemaining
    @Default(.aiUsageAbsoluteResetTime) private var absoluteResetTime
    @Default(.aiUsageShowPace) private var showPace
    @Default(.aiUsagePaceAbsoluteTime) private var paceAbsoluteTime

    var body: some View {
        Form {
            Section(L10n.string("settings.ai_usage.display_options")) {
                Toggle(isOn: $showRemaining) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("settings.ai_usage.show_remaining"))
                        Text(L10n.string("settings.ai_usage.show_remaining_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $absoluteResetTime) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("settings.ai_usage.absolute_reset_time"))
                        Text(L10n.string("settings.ai_usage.absolute_reset_time_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $showPace) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("settings.ai_usage.show_pace"))
                        Text(L10n.string("settings.ai_usage.show_pace_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if showPace {
                    Toggle(isOn: $paceAbsoluteTime) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.string("settings.ai_usage.pace_absolute_time"))
                            Text(L10n.string("settings.ai_usage.pace_absolute_time_hint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("OpenAI") {
                SecureField(L10n.string("settings.ai_usage.openai_key_placeholder"), text: $openAIKey)
                    .onSubmit { saveOpenAIKey() }
                if OpenAIProvider().isConfigured {
                    Button(L10n.string("settings.ai_usage.openai_delete_key"), role: .destructive) {
                        OpenAIProvider.deleteAPIKey()
                        openAIKey = ""
                    }
                }
                Text(L10n.string("settings.ai_usage.openai_key_note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("OpenRouter") {
                SecureField(L10n.string("settings.ai_usage.openrouter_key_placeholder"), text: $openRouterKey)
                    .onSubmit { saveOpenRouterKey() }
                SecureField(L10n.string("settings.ai_usage.openrouter_mgmt_placeholder"), text: $openRouterMgmtKey)
                    .onSubmit { saveOpenRouterMgmtKey() }
                if OpenRouterProvider().isConfigured {
                    Button(L10n.string("settings.ai_usage.openrouter_delete_keys"), role: .destructive) {
                        OpenRouterProvider.deleteRegularKey()
                        OpenRouterProvider.deleteManagementKey()
                        openRouterKey = ""
                        openRouterMgmtKey = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveOpenAIKey() {
        guard !openAIKey.isEmpty else { return }
        let wasConfigured = OpenAIProvider().isConfigured
        do {
            try OpenAIProvider.saveAPIKey(openAIKey)
            refreshAIUsageIfNeeded(wasConfigured: wasConfigured)
        } catch {}
    }

    private func saveOpenRouterKey() {
        guard !openRouterKey.isEmpty else { return }
        let wasConfigured = OpenRouterProvider().isConfigured
        do {
            try OpenRouterProvider.saveRegularKey(openRouterKey)
            refreshAIUsageIfNeeded(wasConfigured: wasConfigured)
        } catch {}
    }

    private func saveOpenRouterMgmtKey() {
        guard !openRouterMgmtKey.isEmpty else { return }
        let wasConfigured = OpenRouterProvider().isConfigured
        do {
            try OpenRouterProvider.saveManagementKey(openRouterMgmtKey)
            refreshAIUsageIfNeeded(wasConfigured: wasConfigured)
        } catch {}
    }

    private func refreshAIUsageIfNeeded(wasConfigured: Bool) {
        guard !wasConfigured else { return }
        Task {
            await appState.aiUsageStore.refresh()
        }
    }
}

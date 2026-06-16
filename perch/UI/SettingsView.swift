import Defaults
import SwiftUI

struct SettingsView: View {
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.animationSpeed) var animationSpeed
    @Default(.autoCollapseDelay) var autoCollapseDelay
    @Default(.showInAllSpaces) var showInAllSpaces
    @Default(.languageCode) var languageCode

    var body: some View {
        TabView {
            GeneralTab(launchAtLogin: $launchAtLogin, showInAllSpaces: $showInAllSpaces)
                .tabItem { Label(L10n.string("settings.general"), systemImage: "gearshape") }
            IslandTab(animationSpeed: $animationSpeed, autoCollapseDelay: $autoCollapseDelay)
                .tabItem { Label(L10n.string("settings.island"), systemImage: "rectangle.topthird.inset.filled") }
            NowPlayingTab()
                .tabItem { Label(L10n.string("settings.nowplaying"), systemImage: "music.note") }
            LanguageTab(languageCode: $languageCode)
                .tabItem { Label(L10n.string("settings.language"), systemImage: "globe") }
            AIUsageTab()
                .tabItem { Label(L10n.string("settings.ai_usage"), systemImage: "cpu") }
            #if DEBUG
            DebugTab()
                .tabItem { Label(L10n.string("settings.debug"), systemImage: "ladybug") }
            #endif
        }
        .frame(width: 420, height: 360)
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
    @Binding var animationSpeed: Double
    @Binding var autoCollapseDelay: Double
    @Default(.pillSize) private var pillSize
    @Default(.pillBackgroundStyle) private var pillBgStyle

    var body: some View {
        Form {
            Picker(L10n.string("settings.pill_size"), selection: $pillSize) {
                ForEach(PillSizePreset.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.segmented)

            Picker("Pill Background", selection: $pillBgStyle) {
                ForEach(PillBackgroundStyle.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.segmented)

            Slider(value: $animationSpeed, in: 0.5...2.0, step: 0.1) {
                Text(L10n.string("settings.animation_speed"))
            } minimumValueLabel: {
                Text(L10n.string("settings.animation_slow"))
            } maximumValueLabel: {
                Text(L10n.string("settings.animation_fast"))
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
    @Default(.enableSpotify) private var enableSpotify
    @Default(.enableAppleMusic) private var enableAppleMusic
    @Default(.enableYouTubeMusic) private var enableYouTubeMusic

    var body: some View {
        Form {
            Section(L10n.string("settings.sources")) {
                Toggle(L10n.string("settings.spotify"), isOn: $enableSpotify)
                Toggle(L10n.string("settings.apple_music"), isOn: $enableAppleMusic)
                Toggle(L10n.string("settings.youtube_music"), isOn: $enableYouTubeMusic)
            }
        }
        .formStyle(.grouped)
        .padding()
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
            Section("使用量 表示オプション") {
                Toggle(isOn: $showRemaining) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("残り%で表示")
                        Text("オフ: \"20% 使用\" / オン: \"80% 残り\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $absoluteResetTime) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("リセット時刻を絶対表示")
                        Text("オフ: \"リセット 2時間後\" / オン: \"10:50 にリセット\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $showPace) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("消費ペースを表示")
                        Text("余裕% / リセットまで持続 / 枯渇予測を表示")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if showPace {
                    Toggle(isOn: $paceAbsoluteTime) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("枯渇予測を絶対時刻で表示")
                            Text("オフ: \"あと 3h で枯渇\" / オン: \"13:00 に枯渇\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("OpenAI") {
                SecureField("Admin API Key (required for usage data)", text: $openAIKey)
                    .onSubmit { saveOpenAIKey() }
                if OpenAIProvider().isConfigured {
                    Button("Delete Key", role: .destructive) {
                        OpenAIProvider.deleteAPIKey()
                        openAIKey = ""
                    }
                }
                Text("Requires Organization Admin Key — not a regular project key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("OpenRouter") {
                SecureField("API Key (sk-or-v1-...)", text: $openRouterKey)
                    .onSubmit { saveOpenRouterKey() }
                SecureField("Management Key (optional, enables chart data)", text: $openRouterMgmtKey)
                    .onSubmit { saveOpenRouterMgmtKey() }
                if OpenRouterProvider().isConfigured {
                    Button("Delete Keys", role: .destructive) {
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

#if DEBUG
private struct DebugTab: View {
    @Default(.notchSimulationMode) private var notchSimulationMode

    var body: some View {
        Form {
            Section(L10n.string("settings.debug")) {
                Picker("Notch Simulation", selection: $notchSimulationMode) {
                    ForEach(NotchSimulationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
#endif

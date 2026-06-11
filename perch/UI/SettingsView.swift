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
                .tabItem { Label("General", systemImage: "gearshape") }
            IslandTab(animationSpeed: $animationSpeed, autoCollapseDelay: $autoCollapseDelay)
                .tabItem { Label("Island", systemImage: "rectangle.topthird.inset.filled") }
            NowPlayingTab()
                .tabItem { Label("Now Playing", systemImage: "music.note") }
            LanguageTab(languageCode: $languageCode)
                .tabItem { Label("Language", systemImage: "globe") }
            #if DEBUG
            DebugTab()
                .tabItem { Label("Debug", systemImage: "ladybug") }
            #endif
        }
        .frame(width: 420, height: 320)
    }
}

private struct GeneralTab: View {
    @Binding var launchAtLogin: Bool
    @Binding var showInAllSpaces: Bool

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItemManager.setEnabled(newValue)
                }
            Toggle("Show on all Spaces", isOn: $showInAllSpaces)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct IslandTab: View {
    @Binding var animationSpeed: Double
    @Binding var autoCollapseDelay: Double

    var body: some View {
        Form {
            Slider(value: $animationSpeed, in: 0.5...2.0, step: 0.1) {
                Text("Animation speed")
            } minimumValueLabel: {
                Text("Slow")
            } maximumValueLabel: {
                Text("Fast")
            }

            Slider(value: $autoCollapseDelay, in: 1.0...10.0, step: 0.5) {
                Text("Auto-collapse delay")
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
            Section("Sources") {
                Toggle("Spotify", isOn: $enableSpotify)
                Toggle("Apple Music", isOn: $enableAppleMusic)
                Toggle("YouTube Music", isOn: $enableYouTubeMusic)
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
            Picker("Language", selection: $languageCode) {
                Text("English").tag("en")
                Text("日本語").tag("ja")
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .padding()
    }
}

#if DEBUG
private struct DebugTab: View {
    @Default(.notchSimulationMode) private var notchSimulationMode

    var body: some View {
        Form {
            Section("Debug") {
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

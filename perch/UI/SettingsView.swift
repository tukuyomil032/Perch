import Defaults
import SwiftUI

struct SettingsView: View {
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.animationSpeed) var animationSpeed
    @Default(.autoCollapseDelay) var autoCollapseDelay
    @Default(.showInAllSpaces) var showInAllSpaces
    @Default(.showNowPlayingSource) var showNowPlayingSource
    @Default(.languageCode) var languageCode

    var body: some View {
        TabView {
            GeneralTab(launchAtLogin: $launchAtLogin, showInAllSpaces: $showInAllSpaces)
                .tabItem { Label("General", systemImage: "gearshape") }
            IslandTab(animationSpeed: $animationSpeed, autoCollapseDelay: $autoCollapseDelay)
                .tabItem { Label("Island", systemImage: "rectangle.topthird.inset.filled") }
            NowPlayingTab(showNowPlayingSource: $showNowPlayingSource)
                .tabItem { Label("Now Playing", systemImage: "music.note") }
            LanguageTab(languageCode: $languageCode)
                .tabItem { Label("Language", systemImage: "globe") }
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
    @Binding var showNowPlayingSource: Bool

    var body: some View {
        Form {
            Toggle("Show music source in pill", isOn: $showNowPlayingSource)
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

import SwiftUI

struct SettingsUpdateTab: View {
    @Environment(SparkleUpdateController.self) private var updateController

    var body: some View {
        @Bindable var updateController = updateController

        Form {
            Section(L10n.string("settings.updates.automatic")) {
                Toggle(L10n.string("settings.updates.automatic"), isOn: $updateController.automaticallyChecksForUpdates)
                    .disabled(!updateController.isUpdateConfigurationReady)
                Text(L10n.string("settings.updates.automatic_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.updates.channel")) {
                Picker(L10n.string("settings.updates.channel"), selection: $updateController.updateChannel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(L10n.string(channel.displayNameKey)).tag(channel)
                    }
                }
                .disabled(!updateController.isUpdateConfigurationReady)
                Text(L10n.string("settings.updates.channel_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.updates.version")) {
                LabeledContent(L10n.string("settings.updates.version"), value: AppVersion.displayString)
                if !updateController.isUpdateConfigurationReady {
                    Text(L10n.string("settings.updates.configuration_required"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(L10n.string("settings.updates.check")) {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
                .accessibilityHint(L10n.string("settings.updates.check_hint"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

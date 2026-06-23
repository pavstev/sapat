import KeyboardShortcuts
import SwiftUI

/// Standard preferences window. The same global shortcut recorder also lives in the
/// popover footer, but a Settings scene gives us the conventional ⌘, surface.
struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Record toggle:", name: .toggleRecording)
            } header: {
                Text("Global Shortcut")
            } footer: {
                Text("Press this shortcut from any app to start or stop recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
    }
}

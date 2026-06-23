import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that starts/stops recording from any app. Default: ⌥⌘G.
    static let toggleRecording = Self(
        "toggleRecording",
        default: .init(.g, modifiers: [.command, .option])
    )
}

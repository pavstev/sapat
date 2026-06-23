import AppKit
import KeyboardShortcuts
import SwiftUI

/// Owns the menu bar status item, the popover, the global hotkey, and the shared
/// `RecorderViewModel`. Using AppKit here (rather than SwiftUI `MenuBarExtra`) gives
/// us full, reliable control over showing the popover — required so the global
/// hotkey can pop it open from any app on macOS 14.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = RecorderViewModel()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        registerHotkey()

        viewModel.onStateChange = { [weak self] state in
            self?.updateStatusIcon(for: state)
        }

        Task { await viewModel.prepare() }
    }

    // MARK: Setup

    private func configurePopover() {
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: PopoverView().environment(viewModel))
        hosting.sizingOptions = [.preferredContentSize] // let the SwiftUI content size the popover
        popover.contentViewController = hosting
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = micImage(filled: false)
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func registerHotkey() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in self?.handleHotkey() }
        }
    }

    // MARK: Actions

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hotkey fired: make sure there's visible feedback, then toggle recording.
    private func handleHotkey() {
        if !popover.isShown { showPopover() }
        viewModel.toggleRecording()
    }

    // MARK: Status icon

    private func updateStatusIcon(for state: AppState) {
        guard let button = statusItem.button else { return }
        if case .recording = state {
            button.image = micImage(filled: true)
            button.contentTintColor = .systemRed
        } else {
            button.image = micImage(filled: false)
            button.contentTintColor = nil
        }
    }

    private func micImage(filled: Bool) -> NSImage? {
        let image = NSImage(
            systemSymbolName: filled ? "mic.fill" : "mic",
            accessibilityDescription: "Glasnik"
        )
        image?.isTemplate = true
        return image
    }
}

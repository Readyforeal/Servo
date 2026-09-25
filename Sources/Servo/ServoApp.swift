import AppKit
import SwiftUI

@MainActor
final class ServoAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(suppressFocusRings(_:)), name: NSWindow.didUpdateNotification, object: nil)
    }
    @objc private func suppressFocusRings(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        func suppress(_ view: NSView) {
            if view.focusRingType != .none { view.focusRingType = .none }
            view.subviews.forEach(suppress)
        }
        if let content = window.contentView { suppress(content) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }
}

@main
struct ServoApp: App {
    @NSApplicationDelegateAdaptor(ServoAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateChecker()

    var body: some Scene {
        Window("Servo", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 660)
                .preferredColorScheme(.dark).tint(ServoPalette.accent).focusEffectDisabled()
                .servoClearWindow().background(ServoWindowChrome())
                .ignoresSafeArea(.container, edges: .top)
                .onAppear { appDelegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(updates.checking ? "Checking for Updates…" : "Check for Updates…") { Task { await updates.check() } }
                    .disabled(updates.checking)
                Divider()
            }
            CommandGroup(after: .newItem) {
                Button("Enable .test Addresses…") { model.enableLocalDomains() }
                    .disabled(model.isWorking)
                Button("Refresh Sites") { model.refreshSites() }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra("Servo", systemImage: "server.rack") {
            ServoMenuBarView()
                .environmentObject(model).environmentObject(updates)
        }
        .menuBarExtraStyle(.menu)
    }
}

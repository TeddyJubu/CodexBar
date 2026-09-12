#if DEBUG
import AppKit
import CodexBarCore
import SwiftUI

/// Offline UI proof entered before settings, account discovery, or provider startup.
@MainActor
enum NotchUsageNativeProof {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--notch-proof") else { return false }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = Delegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        return true
    }

    private final class Delegate: NSObject, NSApplicationDelegate {
        private var window: NSWindow?
        private var controller: NotchUsageController?

        func applicationDidFinishLaunching(_ notification: Notification) {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 560, height: 490),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            window.title = "CodexBar notch preview — synthetic data"
            window.contentView = NSHostingView(rootView: ProofView())
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.window = window
            self.controller = NotchUsageController(
                providers: { NotchUsageNativeProof.sampleProviders },
                openSettings: { [weak self] in
                    self?.window?.makeKeyAndOrderFront(nil)
                })
            self.controller?.start()
            NSApp.activate(ignoringOtherApps: true)
        }

        func applicationWillTerminate(_ notification: Notification) {
            self.controller?.stop()
        }

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }
    }

    private struct ProofView: View {
        @State private var expanded = true
        /// Provider-specific by design: this offline fixture initially selects its synthetic Codex row.
        @State private var selectedID = "codex"

        var body: some View {
            VStack(spacing: 20) {
                Text("NOTCH USAGE · OFFLINE PREVIEW")
                    .font(.caption).tracking(2).foregroundStyle(.secondary)
                if let geometry = NotchGeometry(
                    screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                    safeAreaTop: 32,
                    leftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
                    rightArea: CGRect(x: 856, y: 950, width: 656, height: 32))
                {
                    NotchUsageView(
                        presentation: self.presentation,
                        geometry: geometry,
                        expanded: self.expanded,
                        selectProvider: { self.selectedID = $0 },
                        toggleExpanded: { self.expanded.toggle() },
                        hoverChanged: { _ in },
                        openSettings: {})
                }
                Text("Sample values only. Click the notch to collapse or expand.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 560, height: 490)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        private var presentation: NotchUsagePresentation {
            NotchUsagePresentation(providers: NotchUsageNativeProof.sampleProviders, selectedID: self.selectedID)
        }
    }

    private static var sampleProviders: [NotchUsageProvider] {
        [
            // Provider-specific by design: fixed synthetic Codex and Claude rows exercise provider switching offline.
            self.provider(id: "codex", name: "Codex", session: 38, weekly: 62),
            self.provider(id: "claude", name: "Claude", session: 91, weekly: 47),
            NotchUsageProvider(id: "empty", name: "No data example", windows: [], updatedAt: nil, error: nil),
        ]
    }

    private static func provider(id: String, name: String, session: Double, weekly: Double) -> NotchUsageProvider {
        let now = Date()
        let windows = [("Session", session, 3600.0), ("Weekly", weekly, 172_800.0)]
            .compactMap { label, used, reset in
                NotchUsageWindow(RateWindow(
                    usedPercent: used,
                    windowMinutes: nil,
                    resetsAt: now.addingTimeInterval(reset),
                    resetDescription: nil), label: label)
            }
        return NotchUsageProvider(id: id, name: name, windows: windows, updatedAt: now, error: nil)
    }
}
#endif

import AppKit
import CodexBarCore
import Observation
import SwiftUI

@MainActor
final class NotchUsageController {
    private let providers: @MainActor () -> [NotchUsageProvider]
    private let openSettings: @MainActor () -> Void
    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchUsageView>?
    private var menuTracking = false
    private var observers: [NSObjectProtocol] = []
    private var hoverTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var observationGeneration = UUID()
    private var enabled = true
    private var running = false
    private var expanded = false
    private var selectedID: String?

    convenience init(store: UsageStore, settings _: SettingsStore, openSettings: @escaping @MainActor () -> Void) {
        self.init(providers: {
            _ = store.menuObservationToken
            return Self.providers(from: store)
        }, openSettings: openSettings)
    }

    init(
        providers: @escaping @MainActor () -> [NotchUsageProvider],
        openSettings: @escaping @MainActor () -> Void)
    {
        self.providers = providers
        self.openSettings = openSettings
    }

    func start() {
        guard !self.running else { return }
        self.running = true
        self.observationGeneration = UUID()
        self.enabled = UserDefaults.standard.object(forKey: "notchUsageEnabled") as? Bool ?? true
        self.selectedID = UserDefaults.standard.string(forKey: "notchUsageSelectedProvider")
        for name in [NSApplication.didChangeScreenParametersNotification, UserDefaults.didChangeNotification] {
            self.observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main)
            { [weak self] notification in
                let defaultsChanged = notification.name == UserDefaults.didChangeNotification
                MainActor.assumeIsolated {
                    guard let self, self.running else { return }
                    if defaultsChanged {
                        let enabled = UserDefaults.standard.object(forKey: "notchUsageEnabled") as? Bool ?? true
                        guard enabled != self.enabled else { return }
                        self.enabled = enabled
                    }
                    self.requestRender()
                }
            })
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            self.observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main)
            { [weak self] notification in
                let tracking = notification.name == NSMenu.didBeginTrackingNotification
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuTracking = tracking
                    self.hoverTask?.cancel()
                    if !self.menuTracking, let panel = self.panel {
                        self.hoverChanged(panel.frame.contains(NSEvent.mouseLocation))
                    }
                }
            })
        }
        self.observeStore()
        self.requestRender()
    }

    func stop() {
        self.running = false
        self.observationGeneration = UUID()
        self.renderTask?.cancel()
        self.renderTask = nil
        self.hoverTask?.cancel()
        self.hoverTask = nil
        self.observers.forEach(NotificationCenter.default.removeObserver)
        self.observers.removeAll()
        self.panel?.orderOut(nil)
        self.panel = nil
        self.hostingView = nil
    }

    private func observeStore() {
        guard self.running else { return }
        let generation = self.observationGeneration
        withObservationTracking {
            _ = self.presentation()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.observationGeneration == generation else { return }
                self.observeStore()
                self.requestRender()
            }
        }
    }

    private func presentation() -> NotchUsagePresentation {
        NotchUsagePresentation(providers: self.providers(), selectedID: self.selectedID)
    }

    private static func providers(from store: UsageStore) -> [NotchUsageProvider] {
        store.enabledProvidersForDisplay().map { id in
            let snapshot = store.menuBarSnapshot(for: id)
            let metadata = id.firstPartyProvider.map { store.metadata(for: $0) }
            var name = metadata?.displayName ?? id.rawValue
            #if canImport(JavaScriptCore)
            if let plugin = UserProviderPluginRegistry.plugin(for: id) { name = plugin.manifest.name }
            #endif
            let windows = NotchUsageProvider.usageWindows(snapshot: snapshot, provider: id.firstPartyProvider)
            return NotchUsageProvider(
                id: id.rawValue,
                name: name,
                windows: windows,
                updatedAt: snapshot?.updatedAt,
                error: store.errors[id])
        }
    }

    /// Defer AppKit/SwiftUI layout out of notification and view callbacks. In particular,
    /// SwiftUI can itself write defaults while measuring text; synchronously rebuilding
    /// the hosting view from that notification recursively enters its layout locks.
    private func requestRender() {
        guard self.running, self.renderTask == nil else { return }
        self.renderTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.running else { return }
            self.renderTask = nil
            self.render()
        }
    }

    private func render() {
        guard self.running else { return }
        let geometry = NSScreen.screens.compactMap { screen in
            NotchGeometry(
                screenFrame: screen.frame,
                safeAreaTop: screen.safeAreaInsets.top,
                leftArea: screen.auxiliaryTopLeftArea,
                rightArea: screen.auxiliaryTopRightArea)
        }.first
        guard self.enabled, let geometry else {
            self.hoverTask?.cancel()
            self.expanded = false
            self.panel?.orderOut(nil)
            return
        }
        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NotchUsagePanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            (panel as? NotchUsagePanel)?.dismiss = { [weak self] in
                guard let self else { return }
                self.hoverTask?.cancel()
                self.expanded = false
                self.requestRender()
            }
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.acceptsMouseMovedEvents = true
            panel.setAccessibilityLabel("CodexBar notch usage")
            self.panel = panel
        }
        let view = NotchUsageView(
            presentation: self.presentation(),
            geometry: geometry,
            expanded: self.expanded,
            selectProvider: { [weak self] id in
                self?.selectedID = id
                UserDefaults.standard.set(id, forKey: "notchUsageSelectedProvider")
                self?.requestRender()
            },
            toggleExpanded: { [weak self] in
                guard let self else { return }
                self.hoverTask?.cancel()
                self.expanded.toggle()
                self.requestRender()
            },
            hoverChanged: { [weak self] inside in
                self?.hoverChanged(inside)
            },
            openSettings: { [weak self] in
                guard let self else { return }
                self.hoverTask?.cancel()
                self.expanded = false
                self.requestRender()
                self.openSettings()
            })
        panel.setFrame(geometry.frame(expanded: self.expanded), display: false)
        // No animation: respects Reduce Motion and keeps the hit region equal to visible bounds.
        if let hostingView = self.hostingView {
            hostingView.rootView = view
        } else {
            let hostingView = NotchHostingView(rootView: view)
            panel.contentView = hostingView
            self.hostingView = hostingView
        }
        panel.orderFrontRegardless()
    }

    private func hoverChanged(_ inside: Bool) {
        self.hoverTask?.cancel()
        guard !self.menuTracking, inside != self.expanded else { return }
        self.hoverTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(inside ? 220 : 400)) } catch { return }
            guard let self, self.running else { return }
            self.expanded = inside
            self.requestRender()
        }
    }
}

@MainActor
private final class NotchUsagePanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        self.dismiss?()
        self.resignKey()
    }
}

@MainActor
private final class NotchHostingView: NSHostingView<NotchUsageView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

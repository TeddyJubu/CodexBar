import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

struct NotchUsageTests {
    @Test(arguments: [CGPoint.zero, CGPoint(x: -1512, y: 200), CGPoint(x: 350, y: 982)])
    func `panel stays below the screen top and follows the notch on offset displays`(origin: CGPoint) throws {
        let screen = CGRect(origin: origin, size: CGSize(width: 1512, height: 982))
        let geometry = try #require(NotchGeometry(
            screenFrame: screen,
            safeAreaTop: 32,
            leftArea: CGRect(x: screen.minX, y: screen.maxY - 32, width: 656, height: 32),
            rightArea: CGRect(x: screen.minX + 856, y: screen.maxY - 32, width: 656, height: 32)))

        #expect(geometry.notchWidth == 200)
        for expanded in [false, true] {
            let frame = geometry.frame(expanded: expanded)
            #expect(frame.midX == screen.midX)
            #expect(frame.maxY == screen.maxY)
            #expect(screen.contains(frame))
        }
        #expect(geometry.expandedSize.height > geometry.compactSize.height)
    }

    @Test
    func `panel aligns with the reported camera gap rather than assuming a centered notch`() throws {
        let geometry = try #require(NotchGeometry(
            screenFrame: CGRect(x: -1512, y: 200, width: 1512, height: 982),
            safeAreaTop: 32,
            leftArea: CGRect(x: -1512, y: 1150, width: 600, height: 32),
            rightArea: CGRect(x: -712, y: 1150, width: 712, height: 32)))
        #expect(geometry.frame(expanded: false).midX == -812)
        #expect(geometry.frame(expanded: true).midX == -812)
    }

    @Test
    func `missing notch geometry never creates an overlay`() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 950, width: 656, height: 32)
        let right = CGRect(x: 856, y: 950, width: 656, height: 32)
        #expect(NotchGeometry(screenFrame: screen, safeAreaTop: 0, leftArea: left, rightArea: right) == nil)
        #expect(NotchGeometry(screenFrame: screen, safeAreaTop: 32, leftArea: nil, rightArea: right) == nil)
        #expect(NotchGeometry(screenFrame: screen, safeAreaTop: 32, leftArea: left, rightArea: nil) == nil)
        #expect(NotchGeometry(screenFrame: screen, safeAreaTop: 32, leftArea: right, rightArea: left) == nil)
    }

    @Test
    func `provider selection falls back when the selected provider is disabled`() {
        let codex = NotchUsageProvider(id: "codex", name: "Codex", windows: [], updatedAt: nil, error: nil)
        let claude = NotchUsageProvider(id: "claude", name: "Claude", windows: [], updatedAt: nil, error: nil)
        var presentation = NotchUsagePresentation(providers: [codex, claude], selectedID: "claude")
        #expect(presentation.selected?.id == "claude")
        presentation.providers = [codex]
        #expect(presentation.selected?.id == "codex")
        presentation.providers = []
        #expect(presentation.selected == nil)
    }

    @Test(arguments: [-20.0, 0, 42.5, 100, 150])
    func `usage is clamped only for display without changing source data`(used: Double) throws {
        let source = RateWindow(usedPercent: used, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let window = try #require(NotchUsageWindow(source, label: "Session"))
        #expect(window.usedPercent == min(100, max(0, used)))
        #expect(source.usedPercent == used)
    }

    @Test
    func `missing synthetic and nonfinite usage never masquerades as available quota`() {
        #expect(NotchUsageWindow(nil, label: "Session") == nil)
        let placeholder = RateWindow(
            usedPercent: 0,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil,
            isSyntheticPlaceholder: true)
        #expect(NotchUsageWindow(placeholder, label: "Session") == nil)
        for used in [Double.nan, .infinity, -.infinity] {
            let source = RateWindow(usedPercent: used, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
            #expect(NotchUsageWindow(source, label: "Session") == nil)
        }
        let genuineReset = RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        #expect(NotchUsageWindow(genuineReset, label: "Session")?.usedPercent == 0)
    }

    @Test
    @MainActor
    func `factory labels follow the reported quota shape while codex hides unsupported tertiary usage`() {
        let window = RateWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let modern = UsageSnapshot(primary: window, secondary: window, tertiary: window, updatedAt: .distantPast)
        let legacy = UsageSnapshot(primary: window, secondary: window, updatedAt: .distantPast)
        #expect(NotchUsageProvider.usageWindows(snapshot: modern, provider: .factory).map(\.label)
            == ["5-hour", "Weekly", "Monthly"])
        #expect(NotchUsageProvider.usageWindows(snapshot: legacy, provider: .factory).map(\.label)
            == ["Standard", "Premium"])
        #expect(NotchUsageProvider.usageWindows(snapshot: modern, provider: .codex).map(\.label)
            == ["Session", "Weekly"])
    }

    @Test
    @MainActor
    func `claude cost only account shows spend quota without inventing a session`() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 5,
                limit: 20,
                currencyCode: "USD",
                period: " Monthly cap ",
                updatedAt: .distantPast),
            updatedAt: .distantPast)
        let windows = NotchUsageProvider.usageWindows(snapshot: snapshot, provider: .claude)
        #expect(windows.map(\.label) == ["Monthly cap"])
        #expect(windows.map(\.usedPercent) == [25])
    }

    @Test
    @MainActor
    func `unknown extra quota is omitted while known extra quota retains its title`() {
        let window = RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(id: "unknown", title: "Unreported", window: window, usageKnown: false),
                NamedRateWindow(id: "known", title: "Shared requests", window: window),
            ],
            updatedAt: .distantPast)
        let windows = NotchUsageProvider.usageWindows(snapshot: snapshot, provider: .codex)
        #expect(windows.map(\.label) == ["Shared requests"])
        #expect(windows.map(\.usedPercent) == [100])
    }
}

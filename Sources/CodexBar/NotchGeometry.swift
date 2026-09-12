import AppKit
import CodexBarCore

/// Adapted from Notchly's IslandWidthResolver and IslandHeightResolver (MIT).
/// See docs/Notchly-LICENSE.txt. Use the real camera gap, never a guessed notch.
struct NotchGeometry {
    let screenFrame: CGRect
    let notchWidth: CGFloat
    let closedHeight: CGFloat
    let centerX: CGFloat

    init?(screenFrame: CGRect, safeAreaTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) {
        guard screenFrame.width.isFinite, screenFrame.height.isFinite,
              safeAreaTop.isFinite, safeAreaTop > 0, safeAreaTop < screenFrame.height,
              let leftArea, let rightArea
        else { return nil }
        let gap = rightArea.minX - leftArea.maxX
        guard gap.isFinite, gap > 0, gap + 152 <= screenFrame.width else { return nil }
        self.screenFrame = screenFrame
        self.notchWidth = gap
        self.closedHeight = safeAreaTop
        self.centerX = (leftArea.maxX + rightArea.minX) / 2
    }

    var compactSize: CGSize {
        CGSize(width: self.notchWidth + 152, height: self.closedHeight)
    }

    var expandedSize: CGSize {
        CGSize(
            width: min(self.screenFrame.width, max(420, self.compactSize.width)),
            height: min(self.screenFrame.height, self.closedHeight + 310))
    }

    func frame(expanded: Bool) -> CGRect {
        let size = expanded ? self.expandedSize : self.compactSize
        return CGRect(
            x: min(
                max(self.centerX - size.width / 2, self.screenFrame.minX),
                self.screenFrame.maxX - size.width),
            y: self.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height)
    }
}

struct NotchUsageWindow {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
    let resetDescription: String?

    init?(_ window: RateWindow?, label: String) {
        guard let window, !window.isSyntheticPlaceholder, window.usedPercent.isFinite else { return nil }
        self.label = label
        self.usedPercent = UsagePercent(raw: window.usedPercent).displayClamped
        self.resetsAt = window.resetsAt
        self.resetDescription = window.resetDescription
    }
}

struct NotchUsageProvider: Identifiable {
    let id: String
    let name: String
    let windows: [NotchUsageWindow]
    let updatedAt: Date?
    let error: String?

    @MainActor
    static func usageWindows(snapshot: UsageSnapshot?, provider: UsageProvider?) -> [NotchUsageWindow] {
        guard let snapshot else { return [] }
        // Provider-specific by design: Claude spend-only accounts use the existing menu bar quota resolver.
        if provider == .claude,
           let spendLimit = MenuBarMetricWindowResolver.claudeSpendLimitWindow(snapshot: snapshot)
        {
            let period = snapshot.providerCost?.period?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = period.flatMap { $0.isEmpty ? nil : $0 } ?? "Extra usage"
            return [NotchUsageWindow(spendLimit, label: label)].compactMap(\.self)
        }
        let labels = provider.map { provider in
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            return descriptor.presentation.rateWindowLabels(metadata: descriptor.metadata, snapshot: snapshot)
        } ?? ProviderRateWindowLabels(
            primary: "Primary",
            secondary: "Secondary",
            tertiary: "Additional",
            showsTertiary: true)
        var windows = [
            NotchUsageWindow(snapshot.primary, label: labels.primary),
            NotchUsageWindow(snapshot.secondary, label: labels.secondary),
            labels.showsTertiary ? NotchUsageWindow(snapshot.tertiary, label: labels.tertiary) : nil,
        ].compactMap(\.self)
        windows += (snapshot.extraRateWindows ?? []).filter(\.usageKnown).compactMap {
            NotchUsageWindow($0.window, label: $0.title)
        }
        return windows
    }
}

struct NotchUsagePresentation {
    var providers: [NotchUsageProvider]
    var selectedID: String?
    var selected: NotchUsageProvider? {
        self.providers.first { $0.id == self.selectedID } ?? self.providers.first
    }
}

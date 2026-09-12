import SwiftUI

struct NotchUsageView: View {
    let presentation: NotchUsagePresentation
    let geometry: NotchGeometry
    let expanded: Bool
    let selectProvider: (String) -> Void
    let toggleExpanded: () -> Void
    let hoverChanged: (Bool) -> Void
    let openSettings: () -> Void

    private var size: CGSize {
        self.expanded ? self.geometry.expandedSize : self.geometry.compactSize
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: self.toggleExpanded) {
                HStack(spacing: 0) {
                    self.wing(index: 0)
                    Color.clear.frame(width: self.geometry.notchWidth)
                    self.wing(index: 1)
                }
                .frame(height: self.geometry.closedHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(self.presentation.selected?.name ?? "CodexBar") notch usage")
            .accessibilityHint(self.expanded ? "Collapse usage details" : "Expand usage details")
            if self.expanded {
                self.details
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: self.size.width, height: self.size.height)
        .background {
            // Adapted from Notchly's IslandMaskView (MIT), without out-of-window cutouts.
            // Keeping the mask inside the panel avoids an invisible oversized hit region.
            Rectangle().fill(.black)
                .clipShape(.rect(
                    bottomLeadingRadius: self.expanded ? 24 : 10,
                    bottomTrailingRadius: self.expanded ? 24 : 10))
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onHover(perform: self.hoverChanged)
    }

    private func wing(index: Int) -> some View {
        let windows = self.presentation.selected?.windows ?? []
        let window = windows.indices.contains(index) ? windows[index] : nil
        return HStack(spacing: 5) {
            if self.presentation.selected?.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundStyle(.orange)
            } else {
                Circle().fill(self.color(window)).frame(width: 5, height: 5)
            }
            Text(window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.map { "\($0.label), \(Int($0.usedPercent.rounded())) percent used" }
            ?? "Usage unavailable")
        .accessibilityHint(self.presentation.selected?.error != nil ? "Refresh failed; data may be outdated" : "")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("USAGE").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.gray)
                Spacer()
                Button(action: self.openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Open CodexBar settings").accessibilityLabel("Open settings")
                Button(action: self.toggleExpanded) { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain).help("Collapse notch").accessibilityLabel("Collapse notch")
            }
            if let provider = self.presentation.selected {
                Menu {
                    ForEach(self.presentation.providers) { item in
                        Button(item.name) { self.selectProvider(item.id) }
                    }
                } label: {
                    HStack {
                        Text(provider.name).font(.system(size: 21, weight: .semibold))
                        Image(systemName: "chevron.down").font(.caption)
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Select usage provider")
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(Array(provider.windows.enumerated()), id: \.offset) { _, window in
                            self.usageRow(window)
                        }
                        if provider.windows.isEmpty {
                            Text("No usage limits available yet. Configure this provider in Settings.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if provider.error != nil {
                            Label(
                                provider.windows
                                    .isEmpty ? "Refresh failed" : "Refresh failed · showing last available data",
                                systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                if let updatedAt = provider.updatedAt {
                    Text("Updated \(updatedAt.formatted(date: .omitted, time: .shortened)) · percentages used")
                        .font(.caption2).foregroundStyle(.gray)
                }
            } else {
                Text("Your AI usage, at a glance").font(.headline)
                Text("Enable a provider in CodexBar Settings to see usage here.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Settings", action: self.openSettings).buttonStyle(.bordered)
            }
        }
    }

    private func usageRow(_ window: NotchUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.label).font(.callout)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))% used").font(.callout.weight(.semibold)).monospacedDigit()
            }
            ProgressView(value: window.usedPercent, total: 100).tint(self.color(window))
                .accessibilityLabel(window.label)
                .accessibilityValue("\(Int(window.usedPercent.rounded())) percent used")
            if let reset = window.resetsAt {
                Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if let description = window.resetDescription, !description.isEmpty {
                Text(description).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func color(_ window: NotchUsageWindow?) -> Color {
        guard let window else { return .gray }
        return window.usedPercent >= 90 ? .orange : .mint
    }
}

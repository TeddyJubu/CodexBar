---
summary: "MacBook notch usage display, controls, and building this fork."
read_when:
  - Enabling or using the notch display
  - Building the notch edition locally
---

# Usage in the MacBook notch

This fork adds a native AppKit and SwiftUI usage panel around the MacBook camera notch. It reuses CodexBar's enabled providers and existing usage snapshots. The notch does not create another account connection or fetch loop.

## Controls

- Enable or disable **Settings → Menu Bar → MacBook notch → Show usage in the notch**. It is enabled by default.
- Hover or click beside the camera to expand the panel.
- Choose a provider in the expanded panel to see its usage windows and reset times.
- Use the chevron to collapse the panel, or the gear to open settings.

The compact display shows the first two available quota windows for the selected provider. Percentages mean **used**, and the expanded view identifies each window. A dash means no reported usage for that position. Missing data and synthetic placeholder windows are not shown as zero usage. The expanded panel labels refresh failures and the last update time when available.

The panel uses the screen's reported safe area and camera gap. It appears only on a display with a detected notch; a display without a notch keeps the usual CodexBar menu bar interface. Display changes reposition the panel. CodexBar's existing menu bar controls remain available.

## Build this fork

Use the Xcode/Swift toolchain required by this checkout's `Package.swift`, then run from the repository root:

```bash
swift build
./Scripts/package_app.sh debug
open CodexBar.app
```

The package script creates the local app bundle. The upstream Homebrew package and upstream release downloads do not contain this fork's notch feature.

For an offline check of the new display model and geometry:

```bash
CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 swift test --filter NotchUsageTests
```

These tests do not connect accounts or read Keychain credentials. They cover screen positioning, unavailable usage, display clamping, and provider selection. Actual camera cutout alignment and mouse interaction should also be checked on a notched MacBook using the freshly built app.

For an interactive preview with synthetic data, build the debug bundle and run:

```bash
open -n CodexBar.app --args --notch-proof
```

This opens a labeled preview window and the real notch panel when a notched display is connected. It starts before account discovery or provider refreshes. Close the preview window to quit. Launch the app normally to use your configured providers.

## Credits

Notch geometry and mask design are adapted from [Notchly](https://github.com/Notchly/Notchly), under its MIT license. See [Notchly-LICENSE.txt](Notchly-LICENSE.txt). The feature uses native frameworks and adds no package dependency.

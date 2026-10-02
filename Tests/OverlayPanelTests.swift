// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 Hussaini Holding

import AppKit

/// AppKit describes a non-activating panel as a system dialog, which tiling
/// window managers track and list on whichever space is current. The shared
/// panel class is compiled here and created deferred, so no window is shown;
/// each floating surface's own file is read for the class it builds.
enum OverlayPanelTests {
    static func run(_ suite: TestSuite) {
        // The Clipboard History window keeps a title bar strip to drag it by.
        for style: NSWindow.StyleMask in [[.borderless, .nonactivatingPanel],
                                          [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]] {
            let overlay = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                                       styleMask: style, backing: .buffered, defer: true)
            suite.expect(overlay.accessibilitySubrole() == .unknown,
                         "a floating overlay describes itself as an undescribed window, so window managers skip it")
            suite.expect(overlay.accessibilityRole() == .window && overlay.isAccessibilityElement(),
                         "a floating overlay stays an accessible window for assistive technology")
        }

        // HUDs, previews, pickers and the menu's positioning helper: none is a
        // document window, and each floats over other apps' windows.
        let surfaces = [
            "Sources/Rukn/App/AppDelegate.swift",
            "Sources/Rukn/UI/PermissionGuideOverlay.swift",
            "Sources/Rukn/UI/QuitProtection/QuitProtectionHUD.swift",
            "Sources/Rukn/Services/QuickTools/QuickToolHUD.swift",
            "Sources/Rukn/Services/QuickTools/QuickLauncherService.swift",
            "Sources/Rukn/Services/QuickTools/CameraPreviewService.swift",
            "Sources/Rukn/Services/QuickTools/RecentCaptureService.swift",
            "Sources/Rukn/Services/QuickTools/ScreenshotSelectionController.swift",
            "Sources/Rukn/Services/QuickTools/ScreenshotQuickPreviewController.swift",
            "Sources/Rukn/Services/QuickTools/ScreenshotPinController.swift",
            "Sources/Rukn/Services/QuickTools/QRResultController.swift",
            "Sources/Rukn/Services/QuickTools/ScratchpadService.swift",
            "Sources/Rukn/Services/Snippets/SnippetLibraryService.swift",
            "Sources/Rukn/Services/Clipboard/ClipboardHistoryService.swift",
            "Sources/Rukn/Services/CommandBar/CommandBarService.swift",
            "Sources/Rukn/Services/Switcher/AppSwitcher.swift",
            "Sources/Rukn/Services/RadialMenu/RadialMenuService.swift",
            "Sources/Rukn/Services/RadialMenu/RadialNowPlayingService.swift",
            "Sources/Rukn/Services/DockPreview/DockPreviewService.swift",
            "Sources/Rukn/Services/WindowLayout/WindowLayoutService.swift",
            "Sources/Rukn/Services/DiskImageInstaller/DiskImageInstallerService.swift",
            "Sources/Rukn/Services/Finder/FinderCutPaste.swift",
            "Sources/Rukn/Services/Display/BrightnessOSD.swift",
            "Sources/Rukn/Services/CleaningMode/CleaningModeManager.swift",
            "Sources/Rukn/Services/Recorder/RecorderIndicator.swift",
        ]
        for path in surfaces {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(source.range(of: #"\bOverlayPanel\(contentRect|:\s*OverlayPanel\b"#,
                                      options: .regularExpression) != nil
                         && !source.contains("NSPanel(contentRect")
                         && source.range(of: #"class \w+:\s*NSPanel\b"#, options: .regularExpression) == nil,
                         "\(path) builds its floating panels as overlays, which window managers do not list")
        }
    }
}

//
//  PlatformHelpers.swift
//  GitAgent
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform clipboard copy.
func copyToClipboard(_ string: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = string
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #endif
}

/// Cross-platform clipboard paste.
func pasteFromClipboard() -> String? {
    #if canImport(UIKit)
    return UIPasteboard.general.string
    #elseif canImport(AppKit)
    return NSPasteboard.general.string(forType: .string)
    #else
    return nil
    #endif
}

extension View {
    /// Hides the navigation back button on iOS — navigation is swipe-back only.
    @ViewBuilder
    func iOSHidesBackButton() -> some View {
        #if os(iOS)
        self.navigationBarBackButtonHidden()
        #else
        self
        #endif
    }

    /// ⌘- / ⌘= adjust a font-size setting (iOS: hardware keyboard only).
    /// Two invisible buttons carry the shortcuts — `opacity(0)` keeps them in
    /// the view hierarchy so the shortcuts still fire (`.hidden()` would not).
    func fontSizeShortcuts(_ range: ClosedRange<Int> = 12...24,
                           get: @escaping () -> Int,
                           set: @escaping (Int) -> Void) -> some View {
        background {
            Group {
                Button("") { set(max(range.lowerBound, get() - 1)) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("") { set(min(range.upperBound, get() + 1)) }
                    .keyboardShortcut("=", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

#if os(iOS)
/// Lets RepoDetailView suspend the nav-level swipe while inline link content
/// is open (the swipe would otherwise skip a level, e.g. file → repo list
/// instead of file → README).
enum SwipeBackControl {
    /// Non-nil while a view shows inline navigation levels.
    static var overridePop: (() -> Void)?
}

/// Permanent delegate for navigation controllers' interactive pop gesture.
/// Hiding the back button makes UIKit disable the gesture; a permanent
/// delegate answering `viewControllers.count > 1` keeps the SYSTEM edge swipe
/// working — one level per swipe, driven entirely by UIKit/SwiftUI. (An
/// earlier custom pan gesture fought the split view's built-in gesture and
/// popped two levels per swipe; it was removed.)
final class SystemSwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SystemSwipeBackDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        var responder = gestureRecognizer.view?.next
        while let current = responder {
            if let navigationController = current as? UINavigationController {
                return navigationController.viewControllers.count > 1
                    && SwipeBackControl.overridePop == nil
            }
            responder = current.next
        }
        return false
    }
}

extension UINavigationController {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = SystemSwipeBackDelegate.shared
    }
}
#endif

#if canImport(AppKit)
/// Sets the hosting window's background to a GitHub-style near-black
/// (#0d1117) — softer than pure black against the system-gray chrome.
private struct BlackWindowAccessor: NSViewRepresentable {
    final class AccessorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.backgroundColor = NSColor(red: 0x0d / 255, green: 0x11 / 255,
                                              blue: 0x17 / 255, alpha: 1)
        }
    }

    func makeNSView(context: Context) -> NSView { AccessorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

extension View {
    /// Pure-black window background on macOS, matching the terminal; no-op elsewhere.
    @ViewBuilder
    func macBlackWindow() -> some View {
        #if canImport(AppKit)
        background(BlackWindowAccessor())
        #else
        self
        #endif
    }

    /// Lists sit directly on the black window on macOS instead of the default
    /// control background; no-op elsewhere.
    @ViewBuilder
    func macTransparentScrollBackground() -> some View {
        #if canImport(AppKit)
        scrollContentBackground(.hidden)
        #else
        self
        #endif
    }
}

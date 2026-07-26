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

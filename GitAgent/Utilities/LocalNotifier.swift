//
//  LocalNotifier.swift
//  GitAgent
//
//  Thin wrapper over UNUserNotificationCenter for local notifications
//  (same API on iOS and macOS, no platform branching needed).
//

import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
final class GitAgentNotificationAppDelegate: NSObject, NSApplicationDelegate {
  func applicationWillFinishLaunching(_ notification: Notification) {
    LocalNotifier.configure()
  }
}
#else
final class GitAgentNotificationAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    LocalNotifier.configure()
    return true
  }
}
#endif

enum LocalNotifier {
  private static let delegate = NotificationDelegate()
  private static let coderCategoryIdentifier = "gitagent.coder.turn-finished"
  private static let openCoderActionIdentifier = "gitagent.coder.open-session"
  private static let coderSessionIDKey = "coderSessionID"
  private static var coderSessionHandler: ((UUID) -> Void)?
  private static var pendingCoderSessionID: UUID?

  /// Installs the foreground presentation delegate during app startup.
  static func configure() {
    let center = UNUserNotificationCenter.current()
    center.delegate = delegate
    let openSession = UNNotificationAction(
      identifier: openCoderActionIdentifier,
      title: L10n.resolveCurrent(.openCoderSession),
      options: [.foreground]
    )
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: coderCategoryIdentifier,
        actions: [openSession],
        intentIdentifiers: []
      )
    ])
  }

  /// Routes Coder notification responses into the app. A response received
  /// during cold launch is retained until the SwiftUI environment is ready.
  static func installCoderSessionHandler(_ handler: @escaping (UUID) -> Void) {
    DispatchQueue.main.async {
      coderSessionHandler = handler
      guard let pendingCoderSessionID else { return }
      self.pendingCoderSessionID = nil
      handler(pendingCoderSessionID)
    }
  }

  /// Requests alert/sound authorization. The system returns immediately when
  /// the user has already made a choice.
  static func requestAuthorizationIfNeeded() {
    let center = UNUserNotificationCenter.current()
    configure()
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  #if os(macOS)
  /// Reads the user's actual macOS notification presentation choice. Apps
  /// cannot change this setting; they can only direct the user to Settings.
  static func notificationAlertStyle(_ completion: @escaping (UNAlertStyle) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        completion(settings.alertStyle)
      }
    }
  }
  #endif

  /// Posts a local notification immediately.
  static func post(title: String, body: String, coderSessionID: UUID? = nil) {
    let center = UNUserNotificationCenter.current()
    configure()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .notDetermined:
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
          guard granted else { return }
          addNotification(
            title: title,
            body: body,
            coderSessionID: coderSessionID,
            to: center
          )
        }
      case .authorized, .provisional, .ephemeral:
        addNotification(
          title: title,
          body: body,
          coderSessionID: coderSessionID,
          to: center
        )
      case .denied:
        break
      @unknown default:
        break
      }
    }
  }

  private static func addNotification(
    title: String,
    body: String,
    coderSessionID: UUID?,
    to center: UNUserNotificationCenter
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let coderSessionID {
      content.categoryIdentifier = coderCategoryIdentifier
      content.userInfo[coderSessionIDKey] = coderSessionID.uuidString
    }
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    center.add(request) { error in
      if let error {
        NSLog("GitAgent: failed to post notification \(error)")
      }
    }
  }

  /// Explicitly present notifications while the app is active; the system
  /// handles background notification presentation automatically.
  private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
      completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      didReceive response: UNNotificationResponse,
      withCompletionHandler completionHandler: @escaping () -> Void
    ) {
      defer { completionHandler() }
      guard response.actionIdentifier == UNNotificationDefaultActionIdentifier ||
        response.actionIdentifier == openCoderActionIdentifier,
        let rawID = response.notification.request.content.userInfo[coderSessionIDKey] as? String,
        let recordID = UUID(uuidString: rawID)
      else { return }

      DispatchQueue.main.async {
        #if os(macOS)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first(where: \.canBecomeKey)?.makeKeyAndOrderFront(nil)
        #endif
        if let coderSessionHandler {
          coderSessionHandler(recordID)
        } else {
          pendingCoderSessionID = recordID
        }
      }
    }
  }
}

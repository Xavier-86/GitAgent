//
//  LocalNotifier.swift
//  GitAgent
//
//  Thin wrapper over UNUserNotificationCenter for local notifications
//  (same API on iOS and macOS, no platform branching needed).
//

import Foundation
import UserNotifications

enum LocalNotifier {
  private static var didRequestAuthorization = false

  /// Requests alert/sound authorization once, on first use.
  static func requestAuthorizationIfNeeded() {
    guard !didRequestAuthorization else { return }
    didRequestAuthorization = true
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  /// Posts a local notification immediately.
  static func post(title: String, body: String) {
    requestAuthorizationIfNeeded()
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        NSLog("GitAgent: failed to post notification \(error)")
      }
    }
  }
}

//
//  RelativeTime.swift
//  GitAgent
//
//  Static relative-time labels computed once at render — no timers,
//  no live refresh anywhere in the app.
//

import Foundation

enum RelativeTime {
    /// Single-unit relative time ("3m ago", "2d ago") — only the largest unit.
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .hour, .day, .weekOfMonth, .month, .year]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func short(_ date: Date) -> String {
        let interval = max(0, -date.timeIntervalSinceNow)
        guard interval >= 60 else { return "just now" }
        let unit = formatter.string(from: interval) ?? ""
        return "\(unit) ago"
    }
}

//
//  SettingsView.swift
//  GitAgent
//

import SwiftUI

/// App settings window (macOS: ⌘,). Reading font size.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Stepper(value: fontSizeBinding, in: 12...24) {
                HStack {
                    Text(settings.tr(.fontSize))
                    Spacer()
                    Text("\(settings.fontSize)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
    }

    private var fontSizeBinding: Binding<Int> {
        Binding(
            get: { settings.fontSize },
            set: { settings.fontSize = $0 }
        )
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}

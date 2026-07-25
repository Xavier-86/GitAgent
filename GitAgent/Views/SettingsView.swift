//
//  SettingsView.swift
//  GitAgent
//

import SwiftUI

/// App settings (macOS: ⌘, window; iOS: gear button in the sidebar). Reading font size.
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
        #if os(macOS)
        .frame(width: 360)
        .padding()
        #endif
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

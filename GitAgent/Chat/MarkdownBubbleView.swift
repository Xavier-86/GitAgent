//
//  MarkdownBubbleView.swift
//  GitAgent
//

import SwiftUI

/// Renders Markdown (assistant chat answers) through the app's web-renderer
/// pipeline, sized to fit its content via height reports from the page.
struct MarkdownBubbleView: View {
    let markdown: String
    var fontSize: Int = 16

    @State private var height: CGFloat = 24

    var body: some View {
        WebMarkdownView(markdown: markdown,
                        onContentHeight: { height = max(24, $0) },
                        scrollPassthrough: true,
                        fontSize: fontSize)
            .frame(height: height)
    }
}

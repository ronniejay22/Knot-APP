//
//  KnotProgressIndicator.swift
//  Knot
//
//  Inline spinner + full-screen overlay loading indicator. Replaces the
//  `Theme.overlayDim + ultraThinMaterial card` pattern that was duplicated
//  across the deletion / export / login loading flows.
//

import SwiftUI

/// Namespace for progress indicators.
enum KnotProgressIndicator {

    /// Tinted spinner for inline use within other views.
    struct Inline: View {
        var tint: Color = Theme.accent

        var body: some View {
            ProgressView().tint(tint)
        }
    }

    /// Full-screen dimmed overlay with a centered card containing a spinner
    /// and an optional message.
    struct Overlay: View {
        let message: String?

        init(message: String? = nil) {
            self.message = message
        }

        var body: some View {
            ZStack {
                Theme.overlayDim.ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Overlay") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        Text("Background content").foregroundStyle(Theme.textPrimary)
        KnotProgressIndicator.Overlay(message: "Deleting account...")
    }
}

#Preview("Inline") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        KnotProgressIndicator.Inline()
    }
}
#endif

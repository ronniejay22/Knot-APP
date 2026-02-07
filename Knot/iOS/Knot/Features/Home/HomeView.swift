//
//  HomeView.swift
//  Knot
//
//  Created on February 6, 2026.
//  Step 2.3: Placeholder Home screen for session persistence verification.
//  Full implementation in Phase 4 (Step 4.1).
//

import SwiftUI
import LucideIcons

/// Placeholder Home screen displayed after successful authentication.
///
/// This is a minimal view to verify session persistence (Step 2.3).
/// The full Home screen with hint capture, milestone cards, and network
/// monitoring will be built in Step 4.1.
struct HomeView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // MARK: - Welcome Branding
                VStack(spacing: 16) {
                    Image(uiImage: Lucide.heart)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .foregroundStyle(.pink)

                    Text("Welcome to Knot")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .tracking(-0.5)

                    Text("Your session is active.\nYou're authenticated.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()

                // MARK: - Session Info
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(uiImage: Lucide.circleCheck)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.green)

                        Text("Session restored from Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    HomeView()
        .environment(AuthViewModel())
}

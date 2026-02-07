//
//  SignInView.swift
//  Knot
//
//  Created on February 6, 2026.
//  Step 2.1: Apple Sign-In Button
//  Step 2.2: Connected to Supabase Auth via AuthViewModel
//  Step 2.3: Uses shared AuthViewModel from environment
//

import SwiftUI
import AuthenticationServices
import LucideIcons

/// The sign-in screen displayed when no authenticated session exists.
/// Presents the Knot branding, value proposition, and Apple Sign-In button.
/// On successful Apple Sign-In, forwards the identity token to Supabase Auth
/// via `AuthViewModel`, which stores the session in the iOS Keychain.
///
/// Uses the shared `AuthViewModel` from the SwiftUI environment (injected by
/// `ContentView`). This ensures sign-in state drives the root navigation —
/// when `isAuthenticated` becomes `true`, `ContentView` automatically switches
/// to the Home screen.
struct SignInView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        @Bindable var viewModel = authViewModel

        ZStack {
            // MARK: - Background
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: - Hero Branding
                VStack(spacing: 16) {
                    Image(uiImage: Lucide.heart)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .foregroundStyle(Theme.accent)

                    Text("Knot")
                        .font(.system(size: 44, weight: .bold, design: .default))
                        .tracking(-1)
                        .foregroundStyle(.white)

                    Text("Relational Excellence\non Autopilot")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()

                // MARK: - Value Propositions
                VStack(spacing: 14) {
                    SignInFeatureRow(
                        icon: Lucide.gift,
                        text: "Personalized gift & date ideas"
                    )
                    SignInFeatureRow(
                        icon: Lucide.calendar,
                        text: "Never miss an important milestone"
                    )
                    SignInFeatureRow(
                        icon: Lucide.sparkles,
                        text: "AI-powered recommendations"
                    )
                }
                .padding(.horizontal, 32)

                Spacer()

                // MARK: - Apple Sign-In
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        authViewModel.configureRequest(request)
                    } onCompletion: { result in
                        authViewModel.handleResult(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(authViewModel.isLoading)

                    Text("By continuing, you agree to our Terms & Privacy Policy")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }

            // MARK: - Loading Overlay
            if authViewModel.isLoading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                ProgressView("Signing in...")
                    .tint(.white)
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Sign In Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authViewModel.signInError ?? "An unknown error occurred.")
        }
    }
}

// MARK: - Feature Row Component

/// A single row in the value proposition list on the sign-in screen.
private struct SignInFeatureRow: View {
    let icon: UIImage
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.accent.opacity(0.85))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    SignInView()
}

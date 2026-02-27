//
//  LoginView.swift
//  Knot
//
//  Created on February 26, 2026.
//  Multi-provider login screen with Apple, Google, and Email magic link.
//

import SwiftUI
import LucideIcons

/// Login screen presenting Apple, Google, and Email sign-in options.
/// Reached via "Get Started" from SignInView.
struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        @Bindable var viewModel = authViewModel

        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: - Title & Subtitle
                Text("Create Account")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.bottom, 8)

                Text("Sign up to start building your partner vault")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)

                // MARK: - Provider Buttons
                VStack(spacing: 14) {
                    // 1. Continue with Apple
                    Button {
                        Task { await authViewModel.signInWithApple() }
                    } label: {
                        ProviderButtonLabel(
                            icon: AnyView(
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.black)
                            ),
                            title: "Continue with Apple"
                        )
                    }
                    .disabled(authViewModel.isLoading)

                    // 2. Continue with Google
                    Button {
                        Task { await authViewModel.signInWithGoogle() }
                    } label: {
                        ProviderButtonLabel(
                            icon: AnyView(GoogleLogoIcon()),
                            title: "Continue with Google"
                        )
                    }
                    .disabled(authViewModel.isLoading)

                    // 3. Continue with Email
                    NavigationLink(value: "magicLink") {
                        ProviderButtonLabel(
                            icon: AnyView(
                                Image(uiImage: Lucide.mail)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(.black.opacity(0.7))
                            ),
                            title: "Continue with Email"
                        )
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
                Spacer()
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
        .navigationBarBackButtonHidden(false)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Sign In Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authViewModel.signInError ?? "An unknown error occurred.")
        }
    }
}

// MARK: - Provider Button Label

/// Shared label layout for all provider buttons: icon + title on a white pill background.
private struct ProviderButtonLabel: View {
    let icon: AnyView
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            icon
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 27))
    }
}

// MARK: - Google Logo Icon

/// Renders the Google "G" multicolor logo as a SwiftUI view.
private struct GoogleLogoIcon: View {
    var body: some View {
        Text("G")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.26, green: 0.52, blue: 0.96),  // Google blue
                        Color(red: 0.86, green: 0.20, blue: 0.18),  // Google red
                        Color(red: 0.96, green: 0.71, blue: 0.10),  // Google yellow
                        Color(red: 0.21, green: 0.65, blue: 0.33),  // Google green
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 20, height: 20)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LoginView()
            .environment(AuthViewModel())
    }
}

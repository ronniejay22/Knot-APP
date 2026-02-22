//
//  SignInView.swift
//  Knot
//
//  Created on February 6, 2026.
//  Redesigned with photo grid + branding split layout.
//

import SwiftUI
import AuthenticationServices
import LucideIcons

/// The sign-in screen displayed when no authenticated session exists.
/// Features a two-section layout: a cream-colored photo grid on top (~55%)
/// and a dark-gradient branding section with CTAs on the bottom (~45%).
///
/// "Get Started" navigates to a pre-auth walkthrough (GetStartedView).
/// "I already have an account" triggers Apple Sign-In directly.
struct SignInView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        @Bindable var viewModel = authViewModel

        NavigationStack {
            ZStack {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // MARK: - Top: Photo Grid
                        PhotoGridSection()
                            .frame(height: geometry.size.height * 0.55)

                        // MARK: - Bottom: Branding + Actions
                        BrandingSection(authViewModel: authViewModel)
                            .frame(maxHeight: .infinity)
                    }
                }
                .ignoresSafeArea()

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
            .navigationDestination(for: String.self) { destination in
                if destination == "getStarted" {
                    GetStartedView()
                }
            }
        }
        .alert("Sign In Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authViewModel.signInError ?? "An unknown error occurred.")
        }
    }
}

// MARK: - Photo Grid Section

/// Displays a decorative grid of placeholder photo tiles on a cream background.
/// Tiles are arranged in staggered rows that bleed off-screen for visual interest.
private struct PhotoGridSection: View {
    private let placeholderColors: [[Color]] = [
        [.pink.opacity(0.25), .orange.opacity(0.30), .purple.opacity(0.25), .teal.opacity(0.30), .pink.opacity(0.20)],
        [.indigo.opacity(0.25), .pink.opacity(0.30), .cyan.opacity(0.25), .orange.opacity(0.25), .purple.opacity(0.20)],
        [.orange.opacity(0.20), .teal.opacity(0.25), .pink.opacity(0.30), .indigo.opacity(0.25), .orange.opacity(0.30)],
        [.purple.opacity(0.25), .cyan.opacity(0.20), .orange.opacity(0.25), .pink.opacity(0.30), .teal.opacity(0.25)],
    ]

    private let tileSpacing: CGFloat = 10
    private let tileCornerRadius: CGFloat = 18
    private let rowOffset: CGFloat = -35

    var body: some View {
        GeometryReader { geometry in
            let tileWidth = (geometry.size.width - tileSpacing * 3) / 3.5
            let tileHeight = tileWidth * 1.2

            ZStack {
                Theme.signInCream

                VStack(spacing: tileSpacing) {
                    ForEach(0..<4, id: \.self) { row in
                        HStack(spacing: tileSpacing) {
                            ForEach(0..<5, id: \.self) { col in
                                RoundedRectangle(cornerRadius: tileCornerRadius)
                                    .fill(placeholderColors[row][col])
                                    .frame(width: tileWidth, height: tileHeight)
                            }
                        }
                        .offset(x: row.isMultiple(of: 2) ? 0 : rowOffset)
                    }
                }
            }
            .clipped()
        }
    }
}

// MARK: - Branding Section

/// Bottom section with the Knot branding, tagline, and sign-in/get-started buttons.
private struct BrandingSection: View {
    let authViewModel: AuthViewModel

    var body: some View {
        ZStack {
            Theme.backgroundGradient

            VStack(spacing: 0) {
                Spacer()

                // MARK: - Heart Icon
                Image(uiImage: Lucide.heart)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Theme.accent)
                    .padding(.bottom, 12)

                // MARK: - Two-tone App Name
                (Text("Kn").foregroundStyle(.white) + Text("ot").foregroundStyle(Theme.accent))
                    .font(.system(size: 42, weight: .bold))
                    .tracking(-1)
                    .padding(.bottom, 6)

                // MARK: - Tagline
                Text("Connect Deeply")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 28)

                // MARK: - Get Started Button
                NavigationLink(value: "getStarted") {
                    Text("Get Started")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.signInButtonPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.bottom, 12)

                // MARK: - I Already Have an Account (Apple Sign-In)
                ZStack {
                    Text("I already have an account")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.signInButtonSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Theme.signInButtonSecondaryBorder, lineWidth: 1)
                        )

                    SignInWithAppleButton(.signIn) { request in
                        authViewModel.configureRequest(request)
                    } onCompletion: { result in
                        authViewModel.handleResult(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .blendMode(.overlay)
                    .opacity(0.011)
                    .disabled(authViewModel.isLoading)
                }
                .padding(.bottom, 20)

                // MARK: - Terms & Privacy
                HStack(spacing: 4) {
                    Text("Terms & Conditions")
                    Text("•")
                    Text("Privacy Policy")
                }
                .font(.caption)
                .foregroundStyle(Theme.accent)

                Spacer()
                    .frame(height: 16)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Preview

#Preview {
    SignInView()
        .environment(AuthViewModel())
}

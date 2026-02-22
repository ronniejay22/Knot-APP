//
//  GetStartedView.swift
//  Knot
//
//  Created on February 16, 2026.
//  Pre-auth walkthrough showing app value propositions before sign-in.
//

import SwiftUI
import AuthenticationServices
import LucideIcons

/// A pre-auth walkthrough screen reached via "Get Started" on the sign-in screen.
/// Displays the app's value propositions and presents Apple Sign-In at the bottom.
struct GetStartedView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // MARK: - Hero
                VStack(spacing: 16) {
                    Image(uiImage: Lucide.heart)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .foregroundStyle(Theme.accent)

                    Text("Relational Excellence\non Autopilot")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // MARK: - Value Propositions
                VStack(alignment: .leading, spacing: 20) {
                    FeatureCard(
                        icon: Lucide.gift,
                        title: "Personalized Ideas",
                        description: "AI-powered gift & date recommendations tailored to your partner"
                    )
                    FeatureCard(
                        icon: Lucide.calendar,
                        title: "Milestone Tracking",
                        description: "Never miss a birthday, anniversary, or special occasion"
                    )
                    FeatureCard(
                        icon: Lucide.sparkles,
                        title: "Smart Hints",
                        description: "Capture little things they mention and we'll remember for you"
                    )
                }
                .padding(.horizontal, 8)

                Spacer()

                // MARK: - Apple Sign-In
                VStack(spacing: 12) {
                    SignInWithAppleButton(.signUp) { request in
                        authViewModel.configureRequest(request)
                    } onCompletion: { result in
                        authViewModel.handleResult(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(authViewModel.isLoading)

                    Text("By continuing, you agree to our Terms & Privacy Policy")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)

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
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: UIImage
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(Theme.accent)
                .padding(10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GetStartedView()
            .environment(AuthViewModel())
    }
}

//
//  SignInView.swift
//  Knot
//
//  Created on February 6, 2026.
//  Step 2.1: Apple Sign-In Button
//

import SwiftUI
import AuthenticationServices
import LucideIcons

/// The sign-in screen displayed when no authenticated session exists.
/// Presents the Knot branding, value proposition, and Apple Sign-In button.
struct SignInView: View {
    @State private var signInError: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // MARK: - Hero Branding
            VStack(spacing: 16) {
                Image(uiImage: Lucide.heart)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .foregroundStyle(.pink)

                Text("Knot")
                    .font(.system(size: 44, weight: .bold, design: .default))
                    .tracking(-1)

                Text("Relational Excellence\non Autopilot")
                    .font(.title3)
                    .foregroundStyle(.secondary)
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
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    handleSignInResult(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("By continuing, you agree to our Terms & Privacy Policy")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(signInError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Sign-In Handler

    /// Processes the Apple Sign-In result.
    /// On success, extracts the credential (user ID, email, identity token).
    /// On failure, shows an error alert (unless the user cancelled).
    private func handleSignInResult(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInError = "Unexpected credential type received."
                showError = true
                return
            }

            // Successfully received Apple credential.
            // The identity token will be sent to Supabase Auth in Step 2.2.
            let userId = credential.user
            let email = credential.email
            let identityToken = credential.identityToken

            print("[Knot] Apple Sign-In succeeded")
            print("[Knot] User ID: \(userId)")
            if let email {
                print("[Knot] Email: \(email)")
            }
            if let tokenData = identityToken,
               let tokenString = String(data: tokenData, encoding: .utf8) {
                print("[Knot] Identity token received (\(tokenString.prefix(20))...)")
            }

        case .failure(let error):
            let nsError = error as NSError
            // ASAuthorizationError.canceled — user dismissed the sheet
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                print("[Knot] Apple Sign-In cancelled by user")
                return
            }
            // All other errors — show alert
            signInError = error.localizedDescription
            showError = true
            print("[Knot] Apple Sign-In error: \(error.localizedDescription)")
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
                .foregroundStyle(.pink.opacity(0.85))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    SignInView()
}

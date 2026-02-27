//
//  MagicLinkView.swift
//  Knot
//
//  Created on February 26, 2026.
//  Email magic link sign-in: email input → send link → check your email.
//

import SwiftUI
import LucideIcons

/// Two-state view for email magic link authentication.
/// First shows an email input form; after sending, shows a "check your email" confirmation.
struct MagicLinkView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var email = ""
    @State private var isSent = false
    @FocusState private var isEmailFocused: Bool

    var body: some View {
        @Bindable var viewModel = authViewModel

        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                if isSent {
                    checkEmailView
                } else {
                    emailInputView
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)

            // MARK: - Loading Overlay
            if authViewModel.isLoading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                ProgressView("Sending magic link...")
                    .tint(.white)
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationBarBackButtonHidden(false)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authViewModel.signInError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Email Input State

    private var emailInputView: some View {
        VStack(spacing: 24) {
            Image(uiImage: Lucide.mail)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(Theme.accent)

            Text("Enter your email")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("We'll send you a magic link to create your account.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            TextField("email@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isEmailFocused)
                .font(.body)
                .foregroundStyle(.white)
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isEmailFocused ? Theme.accent : Theme.surfaceBorder, lineWidth: 1)
                )
                .onAppear { isEmailFocused = true }

            Button {
                Task {
                    await authViewModel.sendMagicLink(email: email)
                    if !authViewModel.showError {
                        withAnimation { isSent = true }
                    }
                }
            } label: {
                Text("Send Magic Link")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(email.isEmpty ? Theme.surface : Theme.signInButtonPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(email.isEmpty || authViewModel.isLoading)
        }
    }

    // MARK: - Confirmation State

    private var checkEmailView: some View {
        VStack(spacing: 20) {
            Image(uiImage: Lucide.mailCheck)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .foregroundStyle(Theme.accent)

            Text("Check your email")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            (Text("We sent a sign-in link to\n")
                .foregroundStyle(Theme.textSecondary) +
             Text(email)
                .foregroundStyle(.white)
                .bold())
                .font(.subheadline)
                .multilineTextAlignment(.center)

            Text("Tap the link in your email to sign in.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            Button {
                Task { await authViewModel.sendMagicLink(email: email) }
            } label: {
                Text("Resend Email")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            .disabled(authViewModel.isLoading)
            .padding(.top, 8)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MagicLinkView()
            .environment(AuthViewModel())
    }
}

//
//  ReauthenticationSheet.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.2: Re-authentication via Apple Sign-In before account deletion.
//

import SwiftUI
import AuthenticationServices
import LucideIcons

/// Sheet presented during account deletion to re-authenticate the user
/// via Apple Sign-In before proceeding with the destructive action.
///
/// This view does NOT create a new Supabase session. It only verifies
/// that the user can successfully complete Apple Sign-In, proving they
/// are the account owner (biometric/passcode confirmation). The existing
/// Supabase session (with a valid JWT) is used for the actual deletion
/// API call.
struct ReauthenticationSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Called when Apple Sign-In completes successfully.
    let onSuccess: () -> Void

    /// Called when the user cancels or the sign-in fails.
    let onCancel: () -> Void

    /// Error to display if re-authentication fails.
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    Image(uiImage: Lucide.shieldAlert)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.red)

                    Text("Verify Your Identity")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("To delete your account, please sign in with Apple to confirm your identity.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email]
                    } onCompletion: { result in
                        handleResult(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer().frame(height: 40)
                }
            }
            .navigationTitle("Re-authenticate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Image(uiImage: Lucide.x)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(.white)
                }
            }
        }
    }

    /// Processes the Apple Sign-In result for re-authentication.
    ///
    /// On success, calls `onSuccess` and dismisses. We do NOT send the
    /// token to Supabase — only verifying the user completed Apple Sign-In.
    private func handleResult(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success:
            onSuccess()
            dismiss()

        case .failure(let error):
            let nsError = error as NSError
            // User dismissed the Apple Sign-In sheet — not an error
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = "Authentication failed. Please try again."
            print("[Knot] Re-authentication failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Previews

#Preview("Re-authenticate") {
    ReauthenticationSheet(
        onSuccess: { print("Success") },
        onCancel: { print("Cancel") }
    )
}

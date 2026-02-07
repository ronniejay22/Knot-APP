//
//  AuthViewModel.swift
//  Knot
//
//  Created on February 6, 2026.
//  Step 2.2: Connects Apple Sign-In credential to Supabase Auth.
//

import AuthenticationServices
import CryptoKit
import Supabase

/// Manages the Apple Sign-In → Supabase Auth flow.
///
/// Generates a secure nonce for the OIDC exchange, sends the Apple identity
/// token to Supabase via `signInWithIdToken`, and stores the resulting session
/// in the iOS Keychain (handled automatically by the Supabase Swift SDK).
@Observable
@MainActor
final class AuthViewModel {

    // MARK: - Published State

    /// True while the Supabase sign-in network request is in flight.
    var isLoading = false

    /// True after a successful Supabase sign-in. Will drive navigation in Step 2.3.
    var isAuthenticated = false

    /// Human-readable error message shown in an alert on failure.
    var signInError: String?

    /// Controls the visibility of the error alert.
    var showError = false

    // MARK: - Private State

    /// Raw nonce generated before the Apple Sign-In request.
    /// Persists between `configureRequest` and `handleResult` so it can be
    /// forwarded to Supabase for OIDC nonce verification.
    private var currentNonce: String?

    // MARK: - Apple Sign-In Request Configuration

    /// Configures the `ASAuthorizationAppleIDRequest` with scopes and a hashed nonce.
    ///
    /// Called from the `SignInWithAppleButton` request closure. Generates a
    /// cryptographically secure random nonce, stores the raw value for later
    /// Supabase submission, and sets the SHA-256 hash on the Apple request.
    nonisolated func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        MainActor.assumeIsolated {
            currentNonce = nonce
        }
        request.requestedScopes = [.email]
        request.nonce = Self.sha256(nonce)
    }

    // MARK: - Apple Sign-In Result Handler

    /// Processes the Apple Sign-In result and forwards the identity token to Supabase.
    ///
    /// On success, extracts the identity token from the Apple credential and
    /// calls `signInWithSupabase`. On failure, shows an error alert (unless the
    /// user cancelled, which is silently ignored per standard iOS behavior).
    func handleResult(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInError = "Unexpected credential type received."
                showError = true
                return
            }

            guard let identityTokenData = credential.identityToken,
                  let idToken = String(data: identityTokenData, encoding: .utf8) else {
                signInError = "Unable to retrieve identity token."
                showError = true
                return
            }

            // Log credential info (email only available on first sign-in)
            print("[Knot] Apple Sign-In succeeded — forwarding to Supabase")
            if let email = credential.email {
                print("[Knot] Email: \(email)")
            }

            Task {
                await signInWithSupabase(idToken: idToken)
            }

        case .failure(let error):
            let nsError = error as NSError
            // User dismissed the Apple Sign-In sheet — not an error
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                print("[Knot] Apple Sign-In cancelled by user")
                return
            }
            signInError = error.localizedDescription
            showError = true
            print("[Knot] Apple Sign-In error: \(error.localizedDescription)")
        }
    }

    // MARK: - Supabase Auth

    /// Sends the Apple identity token to Supabase Auth via `signInWithIdToken`.
    ///
    /// On success, the Supabase SDK automatically stores the session (access token,
    /// refresh token) in the iOS Keychain. A new user record is created in
    /// `auth.users` if this is the first sign-in, and the `handle_new_user` trigger
    /// auto-creates the corresponding `public.users` row.
    private func signInWithSupabase(idToken: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await SupabaseManager.client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: currentNonce
                )
            )

            isAuthenticated = true
            currentNonce = nil

            print("[Knot] Supabase sign-in succeeded")
            print("[Knot] Supabase User ID: \(session.user.id)")
            print("[Knot] Email: \(session.user.email ?? "hidden (Apple Private Relay)")")
            print("[Knot] Access token: \(session.accessToken.prefix(20))...")

        } catch {
            currentNonce = nil
            signInError = "Sign-in failed. Please try again."
            showError = true
            print("[Knot] Supabase sign-in error: \(error)")
        }
    }

    // MARK: - Nonce Utilities

    /// Generates a cryptographically secure random string for use as an OIDC nonce.
    ///
    /// The raw nonce is sent to Supabase, while its SHA-256 hash is embedded in
    /// the Apple Sign-In request. Supabase hashes the raw nonce and verifies it
    /// matches the hash inside Apple's identity token, proving the token was
    /// issued for this specific sign-in attempt.
    private nonisolated static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard errorCode == errSecSuccess else {
            fatalError("Unable to generate secure random bytes: OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    /// Returns the SHA-256 hash of the input string as a lowercase hex string.
    private nonisolated static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

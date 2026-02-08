//
//  AuthViewModel.swift
//  Knot
//
//  Created on February 6, 2026.
//  Step 2.2: Connects Apple Sign-In credential to Supabase Auth.
//  Step 2.3: Session persistence — restores session from Keychain on app launch.
//  Step 2.4: Sign-out — clears Supabase session and Keychain, returns to Sign-In.
//  Step 3.11: Vault existence check on session restore/sign-in to skip onboarding.
//

import AuthenticationServices
import CryptoKit
import Supabase

/// Manages authentication state for the entire app.
///
/// On launch, listens to `authStateChanges` from the Supabase SDK to restore
/// any existing session from the iOS Keychain. If a valid session is found,
/// `isAuthenticated` becomes `true` and the app navigates to the Home screen.
/// If no session exists (or the session is expired and cannot be refreshed),
/// the Sign-In screen is shown.
///
/// Also handles the Apple Sign-In → Supabase Auth flow: generates a secure
/// nonce for the OIDC exchange, sends the Apple identity token to Supabase
/// via `signInWithIdToken`, and stores the resulting session in the Keychain
/// (handled automatically by the Supabase Swift SDK).
@Observable
@MainActor
final class AuthViewModel {

    // MARK: - Published State

    /// True while checking the Keychain for an existing session on app launch.
    /// The UI shows a loading indicator during this phase.
    var isCheckingSession = true

    /// True while the Supabase sign-in network request is in flight.
    var isLoading = false

    /// True when the user has a valid Supabase session. Drives root navigation:
    /// `true` → Home screen (or Onboarding if vault not created), `false` → Sign-In screen.
    var isAuthenticated = false

    /// True when the user has completed the onboarding flow (Partner Vault exists).
    /// When `isAuthenticated` is `true` but `hasCompletedOnboarding` is `false`,
    /// the app shows the onboarding flow instead of the Home screen.
    ///
    /// Set to `true` in two scenarios:
    /// 1. After the vault is submitted to the backend during onboarding (Step 3.11)
    /// 2. When an existing vault is detected on session restore or sign-in (Step 3.11)
    var hasCompletedOnboarding = false

    /// Human-readable error message shown in an alert on failure.
    var signInError: String?

    /// Controls the visibility of the error alert.
    var showError = false

    // MARK: - Private State

    /// Raw nonce generated before the Apple Sign-In request.
    /// Persists between `configureRequest` and `handleResult` so it can be
    /// forwarded to Supabase for OIDC nonce verification.
    private var currentNonce: String?

    /// Tracks whether the auth state listener task is already running
    /// to prevent duplicate listeners.
    private var isListening = false

    // MARK: - Session Persistence (Step 2.3)

    /// Starts listening for Supabase auth state changes.
    ///
    /// The Supabase Swift SDK emits an `initialSession` event on first listen,
    /// which contains the session restored from the iOS Keychain (or `nil` if
    /// no session exists). Subsequent events track sign-in, sign-out, and
    /// token refresh.
    ///
    /// Call this once from the root view's `.task` modifier. The async stream
    /// runs for the lifetime of the view.
    func listenForAuthChanges() async {
        guard !isListening else { return }
        isListening = true

        for await (event, session) in SupabaseManager.client.auth.authStateChanges {
            switch event {
            case .initialSession:
                // First event — session restored from Keychain (or nil)
                if let session {
                    isAuthenticated = true
                    print("[Knot] Session restored from Keychain")
                    print("[Knot] User ID: \(session.user.id)")
                    print("[Knot] Email: \(session.user.email ?? "hidden")")

                    // Check if user already has a vault → skip onboarding (Step 3.11)
                    let vaultService = VaultService()
                    let vaultFound = await vaultService.vaultExists()
                    // Re-check after await: onComplete() may have set this to true
                    // while vaultExists() was in flight (race across suspension points).
                    if !hasCompletedOnboarding {
                        hasCompletedOnboarding = vaultFound
                    }
                    print("[Knot] Vault exists: \(vaultFound) → \(hasCompletedOnboarding ? "Home" : "Onboarding")")
                } else {
                    isAuthenticated = false
                    hasCompletedOnboarding = false  // Defensive reset for nil session
                    print("[Knot] No existing session — showing Sign-In")
                }
                isCheckingSession = false

            case .signedIn:
                isAuthenticated = true
                print("[Knot] Auth state: signed in")

                // Check if returning user already has a vault → skip onboarding (Step 3.11)
                // Guard: don't overwrite if already true (e.g., user just finished onboarding
                // and the SDK re-emits signedIn, or vaultExists() fails transiently).
                if !hasCompletedOnboarding {
                    let vaultService = VaultService()
                    let vaultFound = await vaultService.vaultExists()
                    // Re-check after await: onComplete() may have set this to true
                    // while vaultExists() was in flight (race across suspension points).
                    if !hasCompletedOnboarding {
                        hasCompletedOnboarding = vaultFound
                    }
                    print("[Knot] Vault exists: \(vaultFound) → \(hasCompletedOnboarding ? "Home" : "Onboarding")")
                } else {
                    print("[Knot] Onboarding already completed — skipping vault check")
                }
                isCheckingSession = false  // After vault check — prevents onboarding flash

            case .signedOut:
                isAuthenticated = false
                hasCompletedOnboarding = false  // Reset for next sign-in (Step 3.11)
                print("[Knot] Auth state: signed out")

            case .tokenRefreshed:
                print("[Knot] Auth state: token refreshed")

            case .userUpdated:
                print("[Knot] Auth state: user updated")

            default:
                break
            }
        }
    }

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

            // isAuthenticated is set by the authStateChanges listener (signedIn event)
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

    // MARK: - Sign Out (Step 2.4)

    /// Signs the user out of Supabase and clears the Keychain session.
    ///
    /// Calls `supabase.auth.signOut()`, which:
    /// 1. Invalidates the current session on the Supabase server
    /// 2. Removes the session (access + refresh tokens) from the iOS Keychain
    /// 3. Emits a `signedOut` event via `authStateChanges`, which the listener
    ///    handles by setting `isAuthenticated = false`
    ///
    /// The `ContentView` auth router reacts to `isAuthenticated` changing to `false`
    /// and navigates back to the Sign-In screen automatically.
    func signOut() async {
        do {
            try await SupabaseManager.client.auth.signOut()
            // isAuthenticated is set to false by the authStateChanges listener (signedOut event)
            print("[Knot] Sign-out succeeded — session cleared from Keychain")
        } catch {
            signInError = "Sign-out failed. Please try again."
            showError = true
            print("[Knot] Sign-out error: \(error)")
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

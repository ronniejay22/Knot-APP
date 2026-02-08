//
//  HomeView.swift
//  Knot
//
//  Created on February 6, 2026.
//  Step 2.3: Placeholder Home screen for session persistence verification.
//  Step 2.4: Added Sign Out button in navigation toolbar.
//  Step 3.12: Added Edit Profile button (temporary until Settings in Step 11.1).
//  Full implementation in Phase 4 (Step 4.1).
//

import SwiftUI
import LucideIcons

/// Placeholder Home screen displayed after successful authentication.
///
/// This is a minimal view to verify session persistence (Step 2.3),
/// sign-out functionality (Step 2.4), and edit profile (Step 3.12).
/// The full Home screen with hint capture, milestone cards, and network
/// monitoring will be built in Step 4.1.
struct HomeView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    /// Controls the Edit Profile sheet presentation (Step 3.12).
    @State private var showEditProfile = false

    var body: some View {
        @Bindable var viewModel = authViewModel

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
                        .foregroundStyle(Theme.accent)

                    Text("Welcome to Knot")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .tracking(-0.5)
                        .foregroundStyle(.white)

                    Text("Your session is active.\nYou're authenticated.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
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
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                // MARK: - Edit Profile Button (Step 3.12)
                Button {
                    showEditProfile = true
                } label: {
                    HStack(spacing: 8) {
                        Image(uiImage: Lucide.userPen)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)

                        Text("Edit Partner Profile")
                            .font(.body.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)

                // MARK: - Sign Out Button (Step 2.4)
                Button(role: .destructive) {
                    Task {
                        await authViewModel.signOut()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(uiImage: Lucide.logOut)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)

                        Text("Sign Out")
                            .font(.body.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showEditProfile = true
                    } label: {
                        Image(uiImage: Lucide.userPen)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(.white)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await authViewModel.signOut()
                        }
                    } label: {
                        Image(uiImage: Lucide.logOut)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(.white)
                }
            }
            .alert("Sign Out Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(authViewModel.signInError ?? "An unknown error occurred.")
            }
            .fullScreenCover(isPresented: $showEditProfile) {
                EditVaultView()
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(AuthViewModel())
}

//
//  SettingsView.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.1: Settings screen with Account, Partner Profile, Notifications,
//  Privacy, and About sections. Replaces the temporary toolbar buttons in HomeView.
//

import SwiftUI
import LucideIcons

/// Settings screen presented as a sheet from the Home screen.
///
/// Organizes user-facing actions into five sections:
/// - **Account** — email display, sign out, delete account (Step 11.2 placeholder)
/// - **Partner Profile** — edit vault (reuses `EditVaultView`)
/// - **Notifications** — enable/disable toggle, quiet hours (Step 11.4 placeholder)
/// - **Privacy** — data export (Step 11.3 placeholder), clear all hints
/// - **About** — app version, terms of service, privacy policy
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var viewModel = SettingsViewModel()

    /// Controls the Edit Profile fullScreenCover (moved from HomeView).
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // MARK: - Account Section
                        accountSection

                        // MARK: - Partner Profile Section
                        partnerProfileSection

                        // MARK: - Notifications Section
                        notificationsSection

                        // MARK: - Privacy Section
                        privacySection

                        // MARK: - About Section
                        aboutSection

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
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
            // MARK: - Alerts
            .alert("Delete Account", isPresented: $viewModel.showDeleteAccountAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Account deletion will be available in a future update.")
            }
            .alert("Clear All Hints", isPresented: $viewModel.showClearHintsConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    Task { await viewModel.clearAllHints() }
                }
            } message: {
                Text("This will permanently delete all your captured hints. This action cannot be undone.")
            }
            .alert("Hints Cleared", isPresented: $viewModel.showClearHintsSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("All hints have been cleared successfully.")
            }
            .alert("Export My Data", isPresented: $viewModel.showExportDataAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Data export will be available in a future update.")
            }
            .alert("Quiet Hours", isPresented: $viewModel.showQuietHoursAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Quiet hours settings will be available in a future update.")
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.clearHintsError != nil },
                set: { if !$0 { viewModel.clearHintsError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.clearHintsError ?? "An unexpected error occurred.")
            }
            // MARK: - Sheets
            .fullScreenCover(isPresented: $showEditProfile) {
                EditVaultView()
            }
            .task {
                await viewModel.loadUserEmail()
                await viewModel.loadNotificationStatus()
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(spacing: 10) {
            sectionHeader(title: "Account")

            settingsInfoRow(
                icon: Lucide.mail,
                title: "Email",
                value: viewModel.userEmail
            )

            settingsRow(
                icon: Lucide.logOut,
                title: "Sign Out",
                showChevron: false
            ) {
                Task { await authViewModel.signOut() }
            }

            settingsRow(
                icon: Lucide.trash2,
                title: "Delete Account",
                subtitle: "Permanently remove your data",
                showChevron: false
            ) {
                viewModel.showDeleteAccountAlert = true
            }
        }
    }

    // MARK: - Partner Profile Section

    private var partnerProfileSection: some View {
        VStack(spacing: 10) {
            sectionHeader(title: "Partner Profile")

            settingsRow(
                icon: Lucide.userPen,
                title: "Edit Profile",
                subtitle: "Update partner details and preferences"
            ) {
                showEditProfile = true
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(spacing: 10) {
            sectionHeader(title: "Notifications")

            settingsToggleRow(
                icon: Lucide.bellRing,
                title: "Enable Notifications",
                isOn: Binding(
                    get: { viewModel.notificationsEnabled },
                    set: { _ in
                        Task { await viewModel.toggleNotifications() }
                    }
                )
            )

            settingsRow(
                icon: Lucide.moon,
                title: "Quiet Hours",
                subtitle: "Set do-not-disturb times"
            ) {
                viewModel.showQuietHoursAlert = true
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(spacing: 10) {
            sectionHeader(title: "Privacy")

            settingsRow(
                icon: Lucide.download,
                title: "Export My Data",
                subtitle: "Download your data as JSON"
            ) {
                viewModel.showExportDataAlert = true
            }

            settingsRow(
                icon: Lucide.trash,
                title: "Clear All Hints",
                subtitle: "Permanently delete all captured hints",
                showChevron: false
            ) {
                viewModel.showClearHintsConfirmation = true
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(spacing: 10) {
            sectionHeader(title: "About")

            settingsInfoRow(
                icon: Lucide.info,
                title: "Version",
                value: viewModel.appVersion
            )

            settingsRow(
                icon: Lucide.fileText,
                title: "Terms of Service"
            ) {
                if let url = URL(string: "https://knot-app.com/terms") {
                    UIApplication.shared.open(url)
                }
            }

            settingsRow(
                icon: Lucide.shield,
                title: "Privacy Policy"
            ) {
                if let url = URL(string: "https://knot-app.com/privacy") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - Reusable Row Components

    /// Uppercase section header label.
    private func sectionHeader(title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    /// Tappable row with icon, title, optional subtitle, and chevron.
    ///
    /// Follows the `editSectionButton` pattern from `EditVaultView`.
    private func settingsRow(
        icon: UIImage,
        title: String,
        subtitle: String? = nil,
        showChevron: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if showChevron {
                    Image(uiImage: Lucide.chevronRight)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    /// Non-tappable info display row with icon, title, and value.
    private func settingsInfoRow(
        icon: UIImage,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.accent)

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    /// Row with a toggle switch instead of a chevron.
    ///
    /// The caller should pass a custom `Binding` whose setter triggers the
    /// desired action. This avoids `.onChange` which fires on programmatic
    /// state changes (e.g., when `loadNotificationStatus()` sets the initial
    /// value), not just user taps.
    private func settingsToggleRow(
        icon: UIImage,
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.accent)

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: isOn)
                .tint(Theme.accent)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.surfaceBorder, lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView()
        .environment(AuthViewModel())
}

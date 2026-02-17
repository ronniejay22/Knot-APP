//
//  SettingsView.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.1: Settings screen with Account, Partner Profile, Notifications,
//  Privacy, and About sections. Replaces the temporary toolbar buttons in HomeView.
//  Step 11.2: Account deletion with three-stage confirmation flow
//  (warning, Apple Sign-In re-auth, final confirmation).
//

import SwiftUI
import SwiftData
import LucideIcons

/// Settings screen presented as a sheet from the Home screen.
///
/// Organizes user-facing actions into five sections:
/// - **Account** — email display, sign out, delete account (Step 11.2)
/// - **Partner Profile** — edit vault (reuses `EditVaultView`)
/// - **Notifications** — enable/disable toggle, quiet hours (Step 11.4 placeholder)
/// - **Privacy** — data export (Step 11.3), clear all hints
/// - **About** — app version, terms of service, privacy policy
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
                        accountSection
                        partnerProfileSection
                        notificationsSection
                        privacySection
                        aboutSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                // MARK: - Loading Overlays
                if viewModel.isDeletingAccount {
                    deletionLoadingOverlay
                }
                if viewModel.isExportingData {
                    exportLoadingOverlay
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { settingsToolbar }
            // Split alerts into two groups to help the Swift type checker.
            // Group 1: Account deletion alerts (Step 11.2)
            .modifier(AccountDeletionAlerts(
                viewModel: $viewModel,
                modelContext: modelContext,
                authViewModel: authViewModel,
                dismiss: dismiss
            ))
            // Group 2: Settings alerts (hints, export, quiet hours)
            .modifier(SettingsAlerts(viewModel: $viewModel))
            // MARK: - Sheets
            .fullScreenCover(isPresented: $showEditProfile) {
                EditVaultView()
            }
            .sheet(isPresented: $viewModel.showReauthentication) {
                ReauthenticationSheet(
                    onSuccess: { viewModel.onReauthenticationSuccess() },
                    onCancel: { viewModel.onReauthenticationFailure() }
                )
            }
            .sheet(isPresented: $viewModel.showExportShareSheet) {
                if let fileURL = viewModel.exportedFileURL {
                    ShareSheet(items: [fileURL])
                }
            }
            .task {
                await viewModel.loadUserEmail()
                await viewModel.loadNotificationStatus()
            }
        }
    }

    /// Loading overlay shown during account deletion.
    private var deletionLoadingOverlay: some View {
        Group {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Deleting account...")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Loading overlay shown during data export.
    private var exportLoadingOverlay: some View {
        Group {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Exporting your data...")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Toolbar content extracted to reduce body complexity.
    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
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
                viewModel.requestAccountDeletion()
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
                subtitle: "Download your data as a PDF"
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

// MARK: - Account Deletion Alerts (Step 11.2)

/// Groups the three account deletion alerts into a single `ViewModifier`
/// so the Swift type checker doesn't time out on a long `.alert` chain.
private struct AccountDeletionAlerts: ViewModifier {
    @Binding var viewModel: SettingsViewModel
    let modelContext: ModelContext
    let authViewModel: AuthViewModel
    let dismiss: DismissAction

    func body(content: Content) -> some View {
        content
            // Stage 1: Initial warning
            .alert("Delete Account?", isPresented: $viewModel.showDeleteAccountAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) {
                    viewModel.confirmDeleteAndReauthenticate()
                }
            } message: {
                Text("This will permanently delete your account and all associated data including your partner profile, hints, recommendations, and notification history. This action cannot be undone.")
            }
            // Stage 3: Final confirmation (after re-auth)
            .alert("Final Confirmation", isPresented: $viewModel.showFinalDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    viewModel.isReauthenticated = false
                }
                Button("Delete My Account", role: .destructive) {
                    Task {
                        let success = await viewModel.executeAccountDeletion(modelContext: modelContext)
                        if success {
                            await authViewModel.signOutAfterDeletion()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("You have been re-authenticated. Tap \"Delete My Account\" to permanently delete all your data. You will not be able to recover your account.")
            }
            // Deletion error
            .alert("Deletion Failed", isPresented: Binding(
                get: { viewModel.deleteAccountError != nil },
                set: { if !$0 { viewModel.deleteAccountError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.deleteAccountError ?? "An unexpected error occurred.")
            }
    }
}

// MARK: - Settings Alerts (Step 11.1)

/// Groups the general settings alerts (hints, export, quiet hours)
/// into a single `ViewModifier` to assist the Swift type checker.
private struct SettingsAlerts: ViewModifier {
    @Binding var viewModel: SettingsViewModel

    func body(content: Content) -> some View {
        content
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
                Button("Cancel", role: .cancel) { }
                Button("Export") {
                    Task { await viewModel.exportUserData() }
                }
            } message: {
                Text("This will export all your Knot data as a PDF. You can save it or share it.")
            }
            .alert("Export Failed", isPresented: Binding(
                get: { viewModel.exportDataError != nil },
                set: { if !$0 { viewModel.exportDataError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.exportDataError ?? "An unexpected error occurred.")
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
    }
}

// MARK: - Share Sheet (Step 11.3)

/// Wraps `UIActivityViewController` for use in SwiftUI sheets.
///
/// Used by the data export flow to present the system share sheet with
/// the exported JSON file, allowing the user to save to Files, AirDrop, etc.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView()
        .environment(AuthViewModel())
}

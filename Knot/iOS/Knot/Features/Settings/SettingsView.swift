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
/// - **Notifications** — enable/disable toggle, quiet hours with time pickers (Step 11.4)
/// - **Privacy** — data export (Step 11.3), clear all hints
/// - **About** — app version, terms of service, privacy policy
struct SettingsView: View {
    /// When `true`, the view is embedded in the tab bar and hides the dismiss button.
    var isTabEmbedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthViewModel.self) private var authViewModel

    @AppStorage("appThemeMode") private var themeMode: String = "light"
    @State private var viewModel = SettingsViewModel()

    /// Controls the Edit Profile fullScreenCover (moved from HomeView).
    @State private var showEditProfile = false

    /// Controls the Milestones management fullScreenCover.
    @State private var showMilestones = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        accountSection
                        partnerProfileSection
                        appearanceSection
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
            .navigationTitle(isTabEmbedded ? "Profile" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isTabEmbedded {
                    settingsToolbar
                }
            }
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
            .fullScreenCover(isPresented: $showMilestones) {
                MilestonesManagementView()
            }
            .sheet(isPresented: $viewModel.showDeleteConfirmationSheet) {
                ReauthenticationSheet(
                    onConfirm: {
                        let success = await viewModel.executeAccountDeletion(modelContext: modelContext)
                        if success {
                            await authViewModel.signOutAfterDeletion()
                            dismiss()
                        }
                        return success
                    },
                    onCancel: { }
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
                await viewModel.loadNotificationPreferences()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await viewModel.loadNotificationStatus() }
                }
            }
        }
    }

    /// Loading overlay shown during account deletion.
    private var deletionLoadingOverlay: some View {
        KnotProgressIndicator.Overlay(message: "Deleting account...")
    }

    /// Loading overlay shown during data export.
    private var exportLoadingOverlay: some View {
        KnotProgressIndicator.Overlay(message: "Exporting your data...")
    }

    /// Toolbar content extracted to reduce body complexity.
    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            KnotIconButton(icon: Lucide.x, variant: .ghost, size: .sm) {
                dismiss()
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(spacing: 10) {
            KnotSectionHeader<EmptyView>("Account", style: .caption)

            KnotListRow.info(
                icon: Lucide.mail,
                title: "Email",
                value: viewModel.userEmail
            )

            KnotListRow.action(
                icon: Lucide.logOut,
                title: "Sign Out",
                action: { Task { await authViewModel.signOut() } }
            )

            KnotListRow.action(
                icon: Lucide.trash2,
                title: "Delete Account",
                subtitle: "Permanently remove your data",
                action: { viewModel.requestAccountDeletion() }
            )
        }
    }

    // MARK: - Partner Profile Section

    private var partnerProfileSection: some View {
        VStack(spacing: 10) {
            KnotSectionHeader<EmptyView>("Partner Profile", style: .caption)

            KnotListRow.chevron(
                icon: Lucide.userPen,
                title: "Edit Profile",
                subtitle: "Update partner details and preferences",
                action: { showEditProfile = true }
            )

            KnotListRow.chevron(
                icon: Lucide.calendarHeart,
                title: "Milestones",
                subtitle: "Manage birthdays, anniversaries & key dates",
                action: { showMilestones = true }
            )
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(spacing: 10) {
            KnotSectionHeader<EmptyView>("Appearance", style: .caption)

            KnotListRow.toggle(
                icon: Lucide.moon,
                title: "Dark Mode",
                isOn: Binding(
                    get: { themeMode == "dark" },
                    set: { isDark in themeMode = isDark ? "dark" : "light" }
                )
            )
        }
    }

    // MARK: - Notifications Section (Step 11.4)

    private var notificationsSection: some View {
        VStack(spacing: 10) {
            KnotSectionHeader<EmptyView>("Notifications", style: .caption)

            KnotListRow.toggle(
                icon: Lucide.bellRing,
                title: "Enable Notifications",
                isOn: Binding(
                    get: { viewModel.notificationsEnabled },
                    set: { _ in
                        Task { await viewModel.toggleNotifications() }
                    }
                )
            )

            // Quiet hours row — taps to expand/collapse time pickers.
            // Uses the generic KnotListRow init so the trailing chevron can
            // animate between up/down with the expanded state.
            KnotListRow(
                icon: Lucide.moon,
                title: "Quiet Hours",
                subtitle: "\(viewModel.formatHour(viewModel.quietHoursStart)) – \(viewModel.formatHour(viewModel.quietHoursEnd))",
                action: {
                    withAnimation(Theme.Motion.standard) {
                        viewModel.showQuietHoursPicker.toggle()
                    }
                }
            ) {
                Image(uiImage: viewModel.showQuietHoursPicker ? Lucide.chevronUp : Lucide.chevronDown)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.textTertiary)
            }

            // Expandable quiet hours time pickers
            if viewModel.showQuietHoursPicker {
                KnotCard(padding: .none, radius: Theme.Radius.md) {
                    VStack(spacing: 0) {
                        quietHoursPickerRow(
                            label: "Start",
                            hour: Binding(
                                get: { viewModel.quietHoursStart },
                                set: { newValue in
                                    viewModel.quietHoursStart = newValue
                                    Task { await viewModel.saveQuietHours() }
                                }
                            )
                        )

                        Divider()
                            .background(Theme.surfaceBorder)

                        quietHoursPickerRow(
                            label: "End",
                            hour: Binding(
                                get: { viewModel.quietHoursEnd },
                                set: { newValue in
                                    viewModel.quietHoursEnd = newValue
                                    Task { await viewModel.saveQuietHours() }
                                }
                            )
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// A row with a label and an hour picker (0-23, displayed as 12-hour time).
    private func quietHoursPickerRow(
        label: String,
        hour: Binding<Int>
    ) -> some View {
        HStack {
            Text(label)
                .knotFont(Theme.Typography.cta)
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Picker(label, selection: hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(viewModel.formatHour(h))
                        .tag(h)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(spacing: 10) {
            KnotSectionHeader<EmptyView>("Privacy", style: .caption)

            KnotListRow.chevron(
                icon: Lucide.download,
                title: "Export My Data",
                subtitle: "Download your data as a PDF",
                action: { viewModel.showExportDataAlert = true }
            )

            KnotListRow.action(
                icon: Lucide.trash,
                title: "Clear All Hints",
                subtitle: "Permanently delete all captured hints",
                action: { viewModel.showClearHintsConfirmation = true }
            )
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(spacing: 10) {
            KnotSectionHeader<EmptyView>("About", style: .caption)

            KnotListRow.info(
                icon: Lucide.info,
                title: "Version",
                value: viewModel.appVersion
            )

            KnotListRow.chevron(
                icon: Lucide.fileText,
                title: "Terms of Service",
                action: {
                    if let url = URL(string: "https://knot-app.com/terms") {
                        UIApplication.shared.open(url)
                    }
                }
            )

            KnotListRow.chevron(
                icon: Lucide.shield,
                title: "Privacy Policy",
                action: {
                    if let url = URL(string: "https://knot-app.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                }
            )
        }
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
            // The typed-confirmation sheet (presented by SettingsView)
            // is now the only confirmation step. The previous warning +
            // final-confirmation alerts are gone; this modifier only owns
            // the error alert.
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

/// Groups the general settings alerts (hints, export)
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
/// the exported PDF file, allowing the user to save to Files, AirDrop, etc.
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

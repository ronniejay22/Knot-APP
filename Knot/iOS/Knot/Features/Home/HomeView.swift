//
//  HomeView.swift
//  Knot
//
//  Created on February 6, 2026.
//  Step 2.3: Placeholder Home screen for session persistence verification.
//  Step 2.4: Added Sign Out button in navigation toolbar.
//  Step 3.12: Added Edit Profile button (temporary until Settings in Step 11.1).
//  Step 11.1: Replaced toolbar buttons with single Settings gear icon.
//  Step 4.1: Full Home screen with header, milestones, network monitoring.
//  Step 6.6: Added Saved Recommendations section between Recommendations button and Recent Hints.
//  Step 7.7: Added Notifications bell icon in toolbar and sheet presentation.
//  Tab Navigation: Removed recommendations, saved, and settings sections (moved to Discover, Saved, Profile tabs).
//  Step 18.6: Removed standalone hint capture and recent hints surfaces; capture now lives inside the recommendation refresh flow.
//

import SwiftUI
import LucideIcons

/// Main Home screen displayed after authentication and onboarding.
///
/// Contains:
/// - **Offline banner** — persistent "No internet connection" banner when offline
/// - **Header** — partner name and days until next milestone
/// - **Upcoming Milestones** — next 1-2 milestones as countdown cards
///
/// Interactive elements are disabled when offline (network monitoring via `NWPathMonitor`).
struct HomeView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var viewModel = HomeViewModel()
    @Environment(NetworkMonitor.self) private var networkMonitor

    var body: some View {
        @Bindable var authVM = authViewModel

        NavigationStack {
            ZStack(alignment: .top) {
                // Background gradient
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // MARK: - Offline Banner
                        if !networkMonitor.isConnected {
                            offlineBanner
                        }

                        // MARK: - Header
                        headerSection

                        // MARK: - Upcoming Milestones
                        upcomingMilestonesSection
                            .disabled(!networkMonitor.isConnected)
                            .opacity(networkMonitor.isConnected ? 1.0 : 0.5)

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Image(uiImage: Lucide.heart)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Theme.accent)

                        Text("Knot")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

            }
            .alert("Error", isPresented: $authVM.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(authViewModel.signInError ?? "An unknown error occurred.")
            }
            .task {
                await viewModel.loadVault()
            }
        }
    }

    // MARK: - Offline Banner

    /// Persistent banner shown when the device has no network connection.
    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(uiImage: Lucide.wifiOff)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(.white)

            Text("No internet connection. Connect to use Knot.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.85))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
    }

    // MARK: - Header Section

    /// Shows partner name and countdown to next milestone.
    private var headerSection: some View {
        KnotCard(padding: .xl, radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                // Greeting
                Text(greetingText)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)

                // Partner name + countdown
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.partnerName)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        if let milestone = viewModel.nextMilestone {
                            HStack(spacing: 6) {
                                Image(systemName: milestone.iconName)
                                    .font(.caption)
                                    .foregroundStyle(milestoneCountdownColor(milestone))

                                Text("\(milestone.name) \(milestone.countdownText)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(milestoneCountdownColor(milestone))
                            }
                        }
                    }

                    Spacer()

                    // Milestone countdown badge
                    if let milestone = viewModel.nextMilestone {
                        countdownBadge(milestone)
                    }
                }

                // Vibe tags
                if !viewModel.vibes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.vibes, id: \.self) { vibe in
                                KnotBadge(vibeDisplayName(vibe), variant: .accent, size: .sm)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Upcoming Milestones Section

    /// Displays the next 1-2 milestones as countdown cards.
    private var upcomingMilestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            KnotSectionHeader("Upcoming", icon: Lucide.calendar, style: .subhead)

            if viewModel.isLoading {
                // Loading state
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Theme.accent)
                    Spacer()
                }
                .frame(height: 80)
            } else if viewModel.upcomingMilestones.isEmpty {
                // Empty state
                emptyMilestoneCard
            } else {
                // Milestone cards
                ForEach(viewModel.upcomingMilestones) { milestone in
                    milestoneCard(milestone)
                }
            }
        }
    }

    // MARK: - Component: Countdown Badge

    /// Large circular badge showing days until milestone.
    private func countdownBadge(_ milestone: UpcomingMilestone) -> some View {
        VStack(spacing: 2) {
            Text("\(milestone.daysUntil)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(milestoneCountdownColor(milestone))

            Text("days")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: 64, height: 64)
        .background(
            Circle()
                .fill(milestoneCountdownColor(milestone).opacity(0.12))
                .overlay(
                    Circle()
                        .stroke(milestoneCountdownColor(milestone).opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Component: Milestone Card

    /// A card showing milestone details and countdown.
    private func milestoneCard(_ milestone: UpcomingMilestone) -> some View {
        KnotCard(padding: .md) {
            HStack(spacing: 14) {
                // Type icon — color-coded by milestone type, stays inline
                Image(systemName: milestone.iconName)
                    .font(.title3)
                    .foregroundStyle(milestoneCountdownColor(milestone))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(milestoneCountdownColor(milestone).opacity(0.12))
                    )

                // Details
                VStack(alignment: .leading, spacing: 3) {
                    Text(milestone.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text(milestone.formattedDate)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                // Countdown — urgency-colored capsule, stays inline
                Text(milestone.countdownText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(milestoneCountdownColor(milestone))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(milestoneCountdownColor(milestone).opacity(0.12))
                    )
            }
        }
    }

    // MARK: - Component: Empty States

    /// Placeholder when no milestones are set up.
    private var emptyMilestoneCard: some View {
        KnotCard(variant: .outlinedDashed, padding: .md) {
            HStack(spacing: 12) {
                Image(uiImage: Lucide.calendarPlus)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.textTertiary)

                Text("No upcoming milestones. Edit your profile to add dates.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)

                Spacer()
            }
        }
    }

    // MARK: - Helpers

    /// Time-of-day greeting.
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    /// Returns the display name for a vibe tag (e.g., "quiet_luxury" → "Quiet Luxury").
    /// Uses an inline dictionary with hand-curated names to avoid coupling the Home
    /// feature to `OnboardingVibesView`. Keep in sync with `OnboardingVibesView.displayName(for:)`.
    /// If a third feature needs these names, extract to a shared utility in `/Core/`.
    private func vibeDisplayName(_ vibe: String) -> String {
        let names: [String: String] = [
            "quiet_luxury": "Quiet Luxury",
            "street_urban": "Street / Urban",
            "outdoorsy": "Outdoorsy",
            "vintage": "Vintage",
            "minimalist": "Minimalist",
            "bohemian": "Bohemian",
            "romantic": "Romantic",
            "adventurous": "Adventurous",
        ]
        return names[vibe] ?? vibe.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    /// Color based on milestone urgency.
    private func milestoneCountdownColor(_ milestone: UpcomingMilestone) -> Color {
        switch milestone.urgencyLevel {
        case .critical: return .red
        case .soon: return .orange
        case .upcoming: return .yellow
        case .distant: return Theme.accent
        }
    }
}

// MARK: - Previews

#Preview("Home — Loading") {
    HomeView()
        .environment(AuthViewModel())
        .environment(NetworkMonitor())
}

#Preview("Home — Empty") {
    HomeView()
        .environment(AuthViewModel())
        .environment(NetworkMonitor())
}

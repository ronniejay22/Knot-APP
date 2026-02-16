//
//  HomeView.swift
//  Knot
//
//  Created on February 6, 2026.
//  Step 2.3: Placeholder Home screen for session persistence verification.
//  Step 2.4: Added Sign Out button in navigation toolbar.
//  Step 3.12: Added Edit Profile button (temporary until Settings in Step 11.1).
//  Step 11.1: Replaced toolbar buttons with single Settings gear icon.
//  Step 4.1: Full Home screen with header, hint capture, milestones, hints preview, network monitoring.
//  Step 4.2: Wired up text hint submission via HintService API, success checkmark animation,
//            haptic feedback, recent hints loading from backend, error handling.
//  Step 6.6: Added Saved Recommendations section between Recommendations button and Recent Hints.
//  Step 7.7: Added Notifications bell icon in toolbar and sheet presentation.
//

import SwiftUI
import LucideIcons

/// Main Home screen displayed after authentication and onboarding.
///
/// Contains:
/// - **Offline banner** — persistent "No internet connection" banner when offline
/// - **Header** — partner name and days until next milestone
/// - **Hint Capture** — text input + microphone button for capturing hints
/// - **Upcoming Milestones** — next 1-2 milestones as countdown cards
/// - **Recent Hints** — preview of last 3 captured hints
///
/// Interactive elements are disabled when offline (network monitoring via `NWPathMonitor`).
struct HomeView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = HomeViewModel()
    @State private var networkMonitor = NetworkMonitor()

    /// Text for the hint capture input.
    @State private var hintText = ""

    /// Controls the Hints List sheet presentation.
    @State private var showHintsList = false

    /// Controls the Recommendations screen presentation.
    @State private var showRecommendations = false

    /// Controls the Settings sheet presentation (Step 11.1).
    @State private var showSettings = false

    /// Focus state for the hint text field.
    @FocusState private var isHintFieldFocused: Bool

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

                        // MARK: - Hint Capture
                        hintCaptureSection
                            .disabled(!networkMonitor.isConnected)
                            .opacity(networkMonitor.isConnected ? 1.0 : 0.5)

                        // MARK: - Upcoming Milestones
                        upcomingMilestonesSection
                            .disabled(!networkMonitor.isConnected)
                            .opacity(networkMonitor.isConnected ? 1.0 : 0.5)

                        // MARK: - Recommendations
                        recommendationsButton
                            .disabled(!networkMonitor.isConnected)
                            .opacity(networkMonitor.isConnected ? 1.0 : 0.5)

                        // MARK: - Saved Recommendations (Step 6.6)
                        if !viewModel.savedRecommendations.isEmpty {
                            savedRecommendationsSection
                        }

                        // MARK: - Recent Hints
                        recentHintsSection
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
                            .foregroundStyle(.white)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(uiImage: Lucide.settings)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(.white)
                }
            }
            .alert("Error", isPresented: $authVM.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(authViewModel.signInError ?? "An unknown error occurred.")
            }
            .fullScreenCover(isPresented: $showRecommendations) {
                RecommendationsView()
            }
            .onChange(of: showRecommendations) { _, isPresented in
                // Reload saved recommendations when returning from Recommendations screen
                if !isPresented {
                    viewModel.loadSavedRecommendations(modelContext: modelContext)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: showSettings) { _, isPresented in
                // Refresh data when returning from Settings (user may have edited profile or cleared hints)
                if !isPresented {
                    Task {
                        await viewModel.loadVault()
                        await viewModel.loadRecentHints()
                    }
                    viewModel.loadSavedRecommendations(modelContext: modelContext)
                }
            }
            .sheet(isPresented: $showHintsList) {
                HintsListView()
            }
            .onChange(of: showHintsList) { _, isPresented in
                // Refresh recent hints when returning from Hints List
                if !isPresented {
                    Task {
                        await viewModel.loadRecentHints()
                    }
                }
            }
            .task {
                await viewModel.loadVault()
                await viewModel.loadRecentHints()
                viewModel.loadSavedRecommendations(modelContext: modelContext)
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
                        .foregroundStyle(.white)
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
                            Text(vibeDisplayName(vibe))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Theme.accent.opacity(0.15))
                                )
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Hint Capture Section

    /// Text input + microphone button for capturing hints about the partner.
    private var hintCaptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section label
            HStack(spacing: 6) {
                Image(uiImage: Lucide.lightbulb)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Theme.accent)

                Text("Capture a Hint")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            // Input area
            HStack(alignment: .bottom, spacing: 10) {
                // Text field with success overlay
                ZStack {
                    ZStack(alignment: .topLeading) {
                        if hintText.isEmpty && !viewModel.showHintSuccess {
                            Text("What did they mention today?")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 10)
                        }

                        TextEditor(text: $hintText)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 40, maxHeight: 80)
                            .focused($isHintFieldFocused)
                            .opacity(viewModel.showHintSuccess ? 0 : 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        viewModel.showHintSuccess
                                            ? Color.green.opacity(0.5)
                                            : (isHintFieldFocused ? Theme.accent.opacity(0.5) : Theme.surfaceBorder),
                                        lineWidth: 1
                                    )
                            )
                    )

                    // Success checkmark overlay
                    if viewModel.showHintSuccess {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)

                            Text("Hint saved!")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.showHintSuccess)

                // Action buttons
                VStack(spacing: 8) {
                    // Microphone button (Step 4.3 — voice capture)
                    Button {
                        // Voice capture will be implemented in Step 4.3
                    } label: {
                        Image(uiImage: Lucide.mic)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Theme.surface)
                                    .overlay(
                                        Circle()
                                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                                    )
                            )
                    }

                    // Submit button (active when text is entered and not submitting)
                    Button {
                        submitHint()
                    } label: {
                        ZStack {
                            if viewModel.isSubmittingHint {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.7)
                            } else {
                                Image(uiImage: Lucide.arrowUp)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(canSubmitHint ? Theme.accent : Theme.surface)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            canSubmitHint ? Theme.accent : Theme.surfaceBorder,
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .disabled(!canSubmitHint || viewModel.isSubmittingHint)
                }
            }

            // Character counter + error message
            HStack {
                // Error message (left-aligned)
                if let error = viewModel.hintErrorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(hintText.count)/\(Constants.Validation.maxHintLength)")
                    .font(.caption2)
                    .foregroundStyle(hintCharacterCountColor)
            }
        }
    }

    // MARK: - Upcoming Milestones Section

    /// Displays the next 1-2 milestones as countdown cards.
    private var upcomingMilestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                HStack(spacing: 6) {
                    Image(uiImage: Lucide.calendar)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.accent)

                    Text("Upcoming")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer()
            }

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

    // MARK: - Recent Hints Section

    /// Shows the last 3 captured hints, or an empty state.
    private var recentHintsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                HStack(spacing: 6) {
                    Image(uiImage: Lucide.sparkles)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.accent)

                    Text("Recent Hints")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                // View all button (Step 4.5)
                if !viewModel.recentHints.isEmpty {
                    Button {
                        showHintsList = true
                    } label: {
                        Text("View All")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            if viewModel.recentHints.isEmpty {
                // Empty state
                emptyHintsCard
            } else {
                // Hint preview cards
                ForEach(viewModel.recentHints) { hint in
                    hintPreviewCard(hint)
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
        HStack(spacing: 14) {
            // Type icon
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
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(milestone.formattedDate)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            // Countdown
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Component: Empty States

    /// Placeholder when no milestones are set up.
    private var emptyMilestoneCard: some View {
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            Theme.surfaceBorder,
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                        )
                )
        )
    }

    /// Placeholder when no hints have been captured.
    private var emptyHintsCard: some View {
        VStack(spacing: 10) {
            Image(uiImage: Lucide.messageSquarePlus)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .foregroundStyle(Theme.textTertiary)

            Text("No hints yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            Text("Capture what your partner mentions — favorite things, wishes, places they want to visit.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            Theme.surfaceBorder,
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                        )
                )
        )
    }

    // MARK: - Component: Hint Preview Card

    /// Shows a single hint preview with text and source icon.
    private func hintPreviewCard(_ hint: HintPreview) -> some View {
        HStack(spacing: 12) {
            // Source icon
            Image(uiImage: hint.source == "voice_transcription" ? Lucide.mic : Lucide.penLine)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(hint.text)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(hint.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Recommendations Button

    /// Button that presents the Recommendations screen.
    private var recommendationsButton: some View {
        Button {
            showRecommendations = true
        } label: {
            HStack(spacing: 12) {
                Image(uiImage: Lucide.sparkles)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.accent.opacity(0.2))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Recommendations")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("AI-powered gift & experience ideas")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Image(uiImage: Lucide.chevronRight)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Saved Recommendations Section (Step 6.6)

    /// Shows saved recommendations as compact cards with swipe-to-delete.
    private var savedRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                HStack(spacing: 6) {
                    Image(uiImage: Lucide.bookmark)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.accent)

                    Text("Saved")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("\(viewModel.savedRecommendations.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            // Saved recommendation cards
            ForEach(viewModel.savedRecommendations) { saved in
                savedRecommendationCard(saved)
            }
        }
    }

    /// A compact card for a saved recommendation with type icon, title, merchant, price, and open link.
    private func savedRecommendationCard(_ saved: SavedRecommendation) -> some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: savedTypeIcon(saved.recommendationType))
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.accent.opacity(0.12))
                )

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let merchantName = saved.merchantName, !merchantName.isEmpty {
                        Text(merchantName)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    if let priceCents = saved.priceCents {
                        Text(savedFormattedPrice(cents: priceCents, currency: saved.currency))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Spacer()

            // Open link button
            Button {
                if let url = URL(string: saved.externalURL) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(uiImage: Lucide.externalLink)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                viewModel.deleteSavedRecommendation(saved, modelContext: modelContext)
            } label: {
                Image(uiImage: Lucide.x)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
        )
    }

    /// SF Symbol for saved recommendation type.
    private func savedTypeIcon(_ type: String) -> String {
        switch type {
        case "gift": return "gift.fill"
        case "experience": return "sparkles"
        case "date": return "heart.fill"
        default: return "star.fill"
        }
    }

    /// Formats price from cents for the saved card (delegates to RecommendationCard's shared helper).
    private func savedFormattedPrice(cents: Int, currency: String) -> String {
        RecommendationCard.formattedPrice(cents: cents, currency: currency)
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

    /// Whether the hint text can be submitted.
    /// Uses raw `hintText.count` for the length check (not trimmed) so it stays
    /// consistent with the character counter and color displayed to the user.
    /// Empty-after-trim is still rejected to prevent whitespace-only submissions.
    private var canSubmitHint: Bool {
        let trimmed = hintText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && hintText.count <= Constants.Validation.maxHintLength
    }

    /// Color for the hint character counter (red when approaching or exceeding limit).
    private var hintCharacterCountColor: Color {
        if hintText.count > Constants.Validation.maxHintLength {
            return .red
        } else if hintText.count >= 450 {
            return .red.opacity(0.8)
        } else {
            return Theme.textTertiary
        }
    }

    /// Submits the current hint text to the backend via `HintService`.
    ///
    /// Flow:
    /// 1. Validate the hint text is submittable
    /// 2. Provide light haptic feedback on tap
    /// 3. Call `viewModel.submitHint()` which sends to `POST /api/v1/hints`
    /// 4. On success: clear input, show checkmark animation, refresh Recent Hints
    /// 5. On failure: show error message below the input, provide error haptic
    private func submitHint() {
        guard canSubmitHint else { return }

        let textToSubmit = hintText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Haptic feedback on submit tap
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Clear the input immediately for responsiveness
        hintText = ""
        isHintFieldFocused = false

        // Submit to the backend
        Task {
            let success = await viewModel.submitHint(text: textToSubmit)

            if success {
                // Success haptic (notification-style)
                let successGenerator = UINotificationFeedbackGenerator()
                successGenerator.notificationOccurred(.success)
            } else {
                // Error haptic
                let errorGenerator = UINotificationFeedbackGenerator()
                errorGenerator.notificationOccurred(.error)
            }
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
}

#Preview("Home — Empty") {
    HomeView()
        .environment(AuthViewModel())
}

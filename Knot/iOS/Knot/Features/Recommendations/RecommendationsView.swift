//
//  RecommendationsView.swift
//  Knot
//
//  Created on February 10, 2026.
//  Step 6.2: Choice-of-Three horizontal scroll with paging, loading state, and Refresh button.
//  Step 6.3: Card selection flow with confirmation bottom sheet.
//  Step 6.4: Refresh flow with reason selection sheet and card animations.
//  Step 6.5: Manual vibe override — Adjust Vibe button and VibeOverrideSheet.
//

import SwiftUI
import LucideIcons

/// Displays exactly 3 recommendation cards in a horizontal paging scroll view.
///
/// Layout:
/// ```
/// ┌─────────────────────────────────────┐
/// │  ← Recommendations        ● ● ○    │
/// ├─────────────────────────────────────┤
/// │                                     │
/// │  ┌─────────────────────────────┐    │
/// │  │   RecommendationCard (1/3)  │    │
/// │  │   ← swipe to page →        │    │
/// │  └─────────────────────────────┘    │
/// │                                     │
/// │  ┌─────────────────────────────┐    │
/// │  │      🔄 Refresh             │    │
/// │  └─────────────────────────────┘    │
/// └─────────────────────────────────────┘
/// ```
struct RecommendationsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = RecommendationsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                Group {
                    if viewModel.isLoading {
                        loadingState
                    } else if let error = viewModel.errorMessage {
                        errorState(message: error)
                    } else if viewModel.recommendations.isEmpty {
                        emptyState
                    } else {
                        recommendationsContent
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(uiImage: Lucide.arrowLeft)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text("Recommendations")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .task {
                await viewModel.generateRecommendations()
            }
            .sheet(isPresented: $viewModel.showConfirmationSheet) {
                if let item = viewModel.selectedRecommendation {
                    SelectionConfirmationSheet(
                        item: item,
                        onConfirm: {
                            Task {
                                await viewModel.confirmSelection()
                            }
                        },
                        onCancel: {
                            viewModel.dismissSelection()
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $viewModel.showRefreshReasonSheet) {
                RefreshReasonSheet { reason in
                    Task {
                        await viewModel.handleRefreshReason(reason)
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.showVibeOverrideSheet) {
                VibeOverrideSheet(
                    selectedVibes: viewModel.vibeOverride ?? [],
                    onSave: { vibes in
                        Task {
                            await viewModel.saveVibeOverride(vibes)
                        }
                    },
                    onClear: {
                        viewModel.clearVibeOverride()
                        viewModel.showVibeOverrideSheet = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Recommendations Content

    private var recommendationsContent: some View {
        VStack(spacing: 20) {
            // Page indicator (hidden during refresh animation)
            pageIndicator
                .opacity(viewModel.cardsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: viewModel.cardsVisible)

            ZStack {
                // Horizontal paging scroll (animated out/in during refresh)
                TabView(selection: $viewModel.currentPage) {
                    ForEach(Array(viewModel.recommendations.enumerated()), id: \.element.id) { index, item in
                        ScrollView {
                            RecommendationCard(
                                title: item.title,
                                descriptionText: item.description,
                                recommendationType: item.recommendationType,
                                priceCents: item.priceCents,
                                currency: item.currency,
                                merchantName: item.merchantName,
                                imageURL: item.imageUrl,
                                onSelect: {
                                    viewModel.selectRecommendation(item)
                                }
                            )
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .opacity(viewModel.cardsVisible ? 1 : 0)
                .scaleEffect(viewModel.cardsVisible ? 1 : 0.85)
                .animation(.easeInOut(duration: 0.3), value: viewModel.cardsVisible)

                // Refresh loading overlay (Step 6.4)
                if viewModel.isRefreshing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(Theme.accent)
                            .scaleEffect(1.2)

                        Text("Finding better options...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.isRefreshing)

            // Action buttons (Step 6.5: Adjust Vibe + Refresh)
            HStack(spacing: 12) {
                adjustVibeButton
                refreshButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Adjust Vibe Button (Step 6.5)

    private var adjustVibeButton: some View {
        Button {
            viewModel.requestVibeOverride()
        } label: {
            HStack(spacing: 8) {
                Image(uiImage: Lucide.sparkles)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)

                Text("Adjust Vibe")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(viewModel.hasVibeOverride ? .white : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(viewModel.hasVibeOverride ? Theme.accent.opacity(0.3) : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                viewModel.hasVibeOverride ? Theme.accent : Theme.surfaceBorder,
                                lineWidth: viewModel.hasVibeOverride ? 1.5 : 1
                            )
                    )
            )
        }
        .disabled(viewModel.isRefreshing || !viewModel.cardsVisible)
        .opacity(viewModel.isRefreshing || !viewModel.cardsVisible ? 0.6 : 1.0)
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<viewModel.recommendations.count, id: \.self) { index in
                Circle()
                    .fill(index == viewModel.currentPage ? Theme.accent : Theme.textTertiary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == viewModel.currentPage ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.currentPage)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Refresh Button

    private var refreshButton: some View {
        Button {
            viewModel.requestRefresh()
        } label: {
            HStack(spacing: 8) {
                if viewModel.isRefreshing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(uiImage: Lucide.refreshCw)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }

                Text(viewModel.isRefreshing ? "Finding better options..." : "Refresh")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                    )
            )
        }
        .disabled(viewModel.isRefreshing || !viewModel.cardsVisible)
        .opacity(viewModel.isRefreshing || !viewModel.cardsVisible ? 0.6 : 1.0)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(1.2)

            Text("Generating recommendations...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: Lucide.circleAlert)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.textTertiary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task {
                    await viewModel.generateRecommendations()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(uiImage: Lucide.refreshCw)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)

                    Text("Try Again")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Theme.accent)
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(uiImage: Lucide.sparkles)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.textTertiary)

            Text("No recommendations yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Text("Complete your partner vault to get personalized recommendations.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Selection Confirmation Sheet (Step 6.3)

/// Bottom sheet shown when the user taps "Select" on a recommendation card.
/// Displays full details and provides "Open in [Merchant]" and "Cancel" buttons.
struct SelectionConfirmationSheet: View {
    let item: RecommendationItemResponse
    let onConfirm: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    Text("Confirm Selection")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Type badge
                    HStack(spacing: 5) {
                        Image(systemName: typeIconSystemName)
                            .font(.caption2.weight(.bold))

                        Text(typeLabel)
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Theme.accent)

                    // Title
                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    // Description
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    // Merchant + Price row
                    HStack {
                        if let merchantName = item.merchantName, !merchantName.isEmpty {
                            HStack(spacing: 5) {
                                Image(uiImage: Lucide.store)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)

                                Text(merchantName)
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        if let priceCents = item.priceCents {
                            Text(formattedPrice(cents: priceCents, currency: item.currency))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Theme.surfaceElevated)
                                )
                        }
                    }

                    // Location (for experiences/dates)
                    if let location = item.location {
                        let parts = [location.address, location.city, location.state]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                        if !parts.isEmpty {
                            HStack(spacing: 5) {
                                Image(uiImage: Lucide.mapPin)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)

                                Text(parts.joined(separator: ", "))
                                    .font(.caption)
                            }
                            .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    Divider()
                        .overlay(Theme.surfaceBorder)

                    // Action buttons
                    VStack(spacing: 12) {
                        // Confirm button
                        Button(action: onConfirm) {
                            HStack(spacing: 8) {
                                Image(uiImage: Lucide.externalLink)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)

                                Text(confirmButtonLabel)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Theme.accent)
                            )
                        }
                        .buttonStyle(.plain)

                        // Cancel button
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Theme.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(Theme.surfaceBorder, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Helpers

    private var confirmButtonLabel: String {
        if let merchantName = item.merchantName, !merchantName.isEmpty {
            return "Open in \(merchantName)"
        }
        return "Open Link"
    }

    private var typeIconSystemName: String {
        switch item.recommendationType {
        case "gift": return "gift.fill"
        case "experience": return "sparkles"
        case "date": return "heart.fill"
        default: return "star.fill"
        }
    }

    private var typeLabel: String {
        switch item.recommendationType {
        case "gift": return "Gift"
        case "experience": return "Experience"
        case "date": return "Date"
        default: return item.recommendationType.capitalized
        }
    }

    private func formattedPrice(cents: Int, currency: String) -> String {
        let amount = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = (cents % 100 == 0) ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

// MARK: - Refresh Reason Sheet (Step 6.4)

/// Bottom sheet shown when the user taps "Refresh" on the recommendations screen.
/// Presents 5 rejection reason options that control backend exclusion filtering.
struct RefreshReasonSheet: View {
    let onSelectReason: @MainActor (String) -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    Text("Why are you refreshing?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // Reason options
                    reasonButton(
                        id: "too_expensive",
                        label: "Too expensive",
                        icon: "arrow.up.circle"
                    )

                    reasonButton(
                        id: "too_cheap",
                        label: "Too cheap",
                        icon: "arrow.down.circle"
                    )

                    reasonButton(
                        id: "not_their_style",
                        label: "Not their style",
                        icon: "hand.thumbsdown"
                    )

                    reasonButton(
                        id: "already_have_similar",
                        label: "Already have something similar",
                        icon: "doc.on.doc"
                    )

                    reasonButton(
                        id: "show_different",
                        label: "Just show me different options",
                        icon: "arrow.triangle.2.circlepath"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Reason Button

    private func reasonButton(id: String, label: String, icon: String) -> some View {
        Button {
            onSelectReason(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vibe Override Sheet (Step 6.5)

/// Bottom sheet for temporarily overriding vibe preferences for this session only.
/// Displays the 8 vibe options in a 2-column grid matching the onboarding vibes aesthetic.
/// The override does not modify the partner vault — it only affects the current recommendation session.
struct VibeOverrideSheet: View {
    @State private var selectedVibes: Set<String>
    let onSave: @MainActor (Set<String>) -> Void
    let onClear: @MainActor () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    init(
        selectedVibes: Set<String>,
        onSave: @escaping @MainActor (Set<String>) -> Void,
        onClear: @escaping @MainActor () -> Void
    ) {
        self._selectedVibes = State(initialValue: selectedVibes)
        self.onSave = onSave
        self.onClear = onClear
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Adjust Vibe")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Temporarily change vibes for this session.\nYour vault preferences won't be modified.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.top, 16)
                .padding(.bottom, 16)

                // Vibe grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Constants.vibeOptions, id: \.self) { vibe in
                            VibeOverrideCard(
                                vibe: vibe,
                                displayName: OnboardingVibesView.displayName(for: vibe),
                                description: OnboardingVibesView.vibeDescription(for: vibe),
                                icon: OnboardingVibesView.vibeIcon(for: vibe),
                                gradient: OnboardingVibesView.vibeGradient(for: vibe),
                                isSelected: selectedVibes.contains(vibe)
                            ) {
                                toggleVibe(vibe)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                // Counter + buttons
                VStack(spacing: 12) {
                    // Selection counter
                    HStack(spacing: 4) {
                        Text("\(selectedVibes.count) selected")
                            .fontWeight(.semibold)

                        if selectedVibes.isEmpty {
                            Text("(pick at least 1)")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)

                    // Save button
                    Button {
                        onSave(selectedVibes)
                    } label: {
                        HStack(spacing: 8) {
                            Image(uiImage: Lucide.sparkles)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)

                            Text("Apply & Refresh")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedVibes.isEmpty)
                    .opacity(selectedVibes.isEmpty ? 0.5 : 1.0)

                    // Clear override button
                    Button {
                        onClear()
                    } label: {
                        Text("Reset to Vault Defaults")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Theme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func toggleVibe(_ vibe: String) {
        if selectedVibes.contains(vibe) {
            selectedVibes.remove(vibe)
        } else {
            selectedVibes.insert(vibe)
        }
    }
}

// MARK: - Vibe Override Card

/// A compact vibe card for the override sheet, matching the onboarding vibe card aesthetic.
private struct VibeOverrideCard: View {
    let vibe: String
    let displayName: String
    let description: String
    let icon: UIImage
    let gradient: LinearGradient
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                gradient

                LinearGradient(
                    colors: [.clear, .black.opacity(0.40)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Large icon watermark
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.white.opacity(0.18))
                    .offset(x: 28, y: -16)

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    Spacer()

                    Image(uiImage: icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.white.opacity(0.85))

                    Text(displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.70))
                        .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)

                // Checkmark badge
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.pink)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .aspectRatio(1.4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.pink : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 2.5 : 0.5
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isSelected)
    }
}

// MARK: - Previews

#Preview("Loading") {
    RecommendationsView()
        .preferredColorScheme(.dark)
}

// MARK: - Confirmation Sheet Previews (Step 6.3)

private let _previewGiftItem: RecommendationItemResponse = {
    let json = """
    {
        "id": "preview-1",
        "recommendation_type": "gift",
        "title": "Ceramic Pottery Class for Two",
        "description": "A hands-on pottery experience where you and your partner create custom pieces together. Includes all materials and firing.",
        "price_cents": 8500,
        "currency": "USD",
        "external_url": "https://example.com/pottery",
        "image_url": null,
        "merchant_name": "Clay Studio Brooklyn",
        "source": "yelp",
        "location": null,
        "interest_score": 0.85,
        "vibe_score": 0.72,
        "love_language_score": 0.9,
        "final_score": 0.82
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)
}()

private let _previewExperienceItem: RecommendationItemResponse = {
    let json = """
    {
        "id": "preview-2",
        "recommendation_type": "experience",
        "title": "Private Sunset Sailing on the Bay",
        "description": "Enjoy a 2-hour private sailing trip with champagne and charcuterie as the sun sets over the bay.",
        "price_cents": 24900,
        "currency": "USD",
        "external_url": "https://example.com/sailing",
        "image_url": null,
        "merchant_name": "Bay Sailing Co.",
        "source": "yelp",
        "location": {
            "city": "San Francisco",
            "state": "CA",
            "country": "US",
            "address": "Pier 39"
        },
        "interest_score": 0.9,
        "vibe_score": 0.8,
        "love_language_score": 0.7,
        "final_score": 0.8
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(RecommendationItemResponse.self, from: json)
}()

#Preview("Confirmation Sheet — Gift") {
    SelectionConfirmationSheet(
        item: _previewGiftItem,
        onConfirm: {},
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Confirmation Sheet — Experience with Location") {
    SelectionConfirmationSheet(
        item: _previewExperienceItem,
        onConfirm: {},
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Refresh Reason Sheet") {
    RefreshReasonSheet(onSelectReason: { _ in })
        .preferredColorScheme(.dark)
}

// MARK: - Vibe Override Sheet Previews (Step 6.5)

#Preview("Vibe Override — Empty") {
    VibeOverrideSheet(
        selectedVibes: [],
        onSave: { _ in },
        onClear: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Vibe Override — 2 Selected") {
    VibeOverrideSheet(
        selectedVibes: ["quiet_luxury", "romantic"],
        onSave: { _ in },
        onClear: {}
    )
    .preferredColorScheme(.dark)
}

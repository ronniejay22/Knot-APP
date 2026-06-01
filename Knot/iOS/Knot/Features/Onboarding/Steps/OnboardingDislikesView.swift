//
//  OnboardingDislikesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 4 — Dislikes.
//  Step 3.4: Full implementation — dark-themed 3-column image card grid.
//  Step 18.14 (2026-05-17): Liked interests excluded from the catalog (was: shown disabled).
//  Step 18.15 (2026-05-17): Removed the 5-item upper cap (now at-least-5).
//

import SwiftUI
import LucideIcons

/// Step 4: Select at least 5 things the partner dislikes ("Hard Avoids").
///
/// Dark-themed screen matching the Interests screen (Step 3.3) visual style.
/// Uses the same 3-column image card grid with themed gradients and SF Symbol icons.
///
/// Interests already selected as "likes" in Step 3.3 are excluded from the
/// catalog entirely (not rendered), so a category can never appear on both
/// screens.
///
/// Features:
/// - Personalized title using the partner's name from Step 3.2
/// - Search bar to filter the remaining interest categories
/// - Selection counter showing "X selected (Y more needed)" until the minimum is met
struct OnboardingDislikesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    @State private var searchText = ""
    @State private var addCustomError: String?

    /// Predefined + user-added custom dislikes, minus anything already chosen as a like.
    /// Custom items sort to the end so the predefined order is preserved.
    private var catalog: [String] {
        let combined = Constants.interestCategories + viewModel.customDislikes.sorted()
        return combined.filter { !viewModel.selectedInterests.contains($0) }
    }

    /// Catalog filtered by the search text (case-insensitive).
    private var filteredInterests: [String] {
        if searchText.isEmpty { return catalog }
        return catalog.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    /// The trimmed search term, when non-empty — used by the "add custom" affordance.
    private var trimmedSearchTerm: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            // MARK: - Search Bar
            searchBar
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // MARK: - Card Grid
            ScrollView {
                if filteredInterests.isEmpty {
                    noResultsView
                        .padding(.horizontal, 24)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(filteredInterests, id: \.self) { interest in
                            DislikeImageCard(
                                title: interest,
                                isSelected: viewModel.selectedDislikes.contains(interest),
                                iconName: OnboardingInterestsView.iconName(for: interest),
                                gradient: OnboardingInterestsView.cardGradient(for: interest),
                                imageName: OnboardingInterestsView.imageName(for: interest)
                            ) {
                                toggleDislike(interest)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            // MARK: - Selection Counter
            counterSection
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
        .onChange(of: viewModel.selectedDislikes) { _, _ in
            viewModel.validateCurrentStep()
        }
        .onChange(of: searchText) { _, _ in
            addCustomError = nil
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "them" : name

            Text("What doesn't \(displayName) like?")
                .knotFont(Theme.Typography.onboardingHeader)
                .foregroundStyle(Theme.textPrimary)

            Text("Choose at least 5 things your partner avoids.\nWe'll make sure to steer clear of these.")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 4)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textTertiary)

            TextField(
                "",
                text: $searchText,
                prompt: Text("Search interests...")
                    .foregroundStyle(Theme.textTertiary)
            )
            .knotFont(Theme.Typography.body)
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    // MARK: - Selection Counter

    private var counterSection: some View {
        let count = viewModel.selectedDislikes.count
        let remaining = Constants.Validation.minDislikes - count

        return HStack(spacing: 4) {
            Text("\(count) selected")
                .knotFont(Theme.Typography.cta)

            if remaining > 0 {
                Text("(\(remaining) more needed)")
                    .knotFont(Theme.Typography.body)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    // MARK: - Selection Logic

    private func toggleDislike(_ interest: String) {
        if viewModel.selectedDislikes.contains(interest) {
            viewModel.selectedDislikes.remove(interest)
        } else {
            viewModel.selectedDislikes.insert(interest)
        }
    }

    // MARK: - No-Results / Add Custom

    /// View shown inside the ScrollView when no catalog items match the search.
    /// Offers an "Add" button to create a custom dislike from the current search text.
    @ViewBuilder
    private var noResultsView: some View {
        let term = trimmedSearchTerm
        VStack(spacing: 16) {
            if term.isEmpty {
                Text("No dislikes to show.")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 6) {
                    Text("No matches for \"\(term)\"")
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)

                    Text("Don't see what you're looking for? Add it as a custom dislike.")
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                Button(action: addCustomFromSearch) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add \"\(term)\"")
                            .knotFont(Theme.Typography.cta)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if let addCustomError {
                    Text(addCustomError)
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(.pink)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Adds the current search text as a custom dislike and clears the field.
    private func addCustomFromSearch() {
        let result = viewModel.addCustomDislike(searchText)
        switch result {
        case .added:
            searchText = ""
            addCustomError = nil
        case .empty:
            addCustomError = "Type a name to add a custom dislike."
        case .tooLong:
            addCustomError = "Keep it under \(OnboardingViewModel.maxCustomInterestLength) characters."
        case .duplicate:
            addCustomError = "That dislike is already in the list."
        case .overlapsLikes:
            addCustomError = "You already picked that as a like."
        }
    }
}

// MARK: - Dislike Image Card

/// A visual card representing a single interest category for the dislikes screen.
///
/// Matches the `InterestImageCard` style from Step 3.3. When an image is available
/// in the asset catalog, the card displays it as a full-bleed photo; otherwise it
/// falls back to the themed gradient background with a centered SF Symbol icon.
///
/// Visual states:
/// - **Unselected:** Photo (or gradient) background, white text
/// - **Selected (disliked):** Pink border, checkmark badge in top-right corner
private struct DislikeImageCard: View {
    let title: String
    let isSelected: Bool
    let iconName: String
    let gradient: LinearGradient
    /// Asset catalog image name (e.g., "Interests/interest-travel"). Nil if no image added yet.
    let imageName: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background: prefer asset image, fall back to gradient + icon
                if let imageName {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    gradient

                    // SF Symbol icon (only when no image)
                    Image(systemName: iconName)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.white.opacity(0.20))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Bottom gradient overlay for text readability
                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Interest name — bottom-left
                VStack {
                    Spacer()
                    HStack {
                        Text(title)
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        Spacer()
                    }
                }
                .padding(10)

                // Selection checkmark badge — top-right (only when selected as dislike)
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
                    .padding(7)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .aspectRatio(0.82, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.pink : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 2.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isSelected)
    }
}

// MARK: - Preview

#Preview("Empty — No Likes") {
    OnboardingDislikesView()
        .environment(OnboardingViewModel())
}

#Preview("With Liked Interests") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Alex"
    vm.selectedInterests = ["Travel", "Cooking", "Music", "Hiking", "Photography"]
    return OnboardingDislikesView()
        .environment(vm)
}

#Preview("3 Dislikes Selected") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Jordan"
    vm.selectedInterests = ["Travel", "Cooking", "Music", "Hiking", "Photography"]
    vm.selectedDislikes = ["Gaming", "Cars", "Wine"]
    return OnboardingDislikesView()
        .environment(vm)
}

#Preview("5 Dislikes Selected — Complete") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Jordan"
    vm.selectedInterests = ["Travel", "Cooking", "Music", "Hiking", "Photography"]
    vm.selectedDislikes = ["Gaming", "Cars", "Wine", "Skiing", "Karaoke"]
    return OnboardingDislikesView()
        .environment(vm)
}

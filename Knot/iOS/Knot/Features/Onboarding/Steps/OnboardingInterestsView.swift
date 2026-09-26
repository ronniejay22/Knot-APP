//
//  OnboardingInterestsView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 3 — Interests.
//  Step 3.3: Full implementation — dark-themed 3-column image card grid
//            with search bar and selection counter.
//  Step 18.15 (2026-05-17): Removed the 5-item upper cap (now at-least-5).
//  Step (2026-06-07): Replaced the 3-column image-card grid with a flat
//            single-column list of selectable rows (`InterestListRow`).
//

import SwiftUI

/// Step 3: Select at least 5 interests the partner likes.
///
/// Dark-themed screen with a single-column vertical list of interest rows. Each
/// row (`InterestListRow`) shows a tinted icon chip, the interest name, and a
/// pink accent border + checkmark when selected. The user must select at least
/// 5 as "likes"; there is no upper bound.
///
/// Features:
/// - Personalized title using the partner's name from Step 3.2
/// - Search bar to filter the 40 interest categories
/// - Selection counter showing "X selected (Y more needed)" until the minimum is met
struct OnboardingInterestsView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    @State private var searchText = ""
    @State private var addCustomError: String?

    /// Full catalog (predefined + user-added customs). Custom items sort to the
    /// end so the predefined order is preserved.
    private var catalog: [String] {
        Constants.interestCategories + viewModel.customInterests.sorted()
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

            // MARK: - Interest List
            ScrollView {
                if filteredInterests.isEmpty {
                    noResultsView
                        .padding(.horizontal, 24)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredInterests, id: \.self) { interest in
                            InterestListRow(
                                title: interest,
                                icon: Self.icon(for: interest),
                                isSelected: viewModel.selectedInterests.contains(interest)
                            ) {
                                toggleInterest(interest)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
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
        .onChange(of: viewModel.selectedInterests) { _, _ in
            viewModel.validateCurrentStep()
        }
        .onChange(of: searchText) { _, _ in
            addCustomError = nil
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "Them" : name

        return OnboardingStepHeader(
            title: "What does \(displayName) love?",
            subtitle: "Choose at least 5 things your partner enjoys. This helps us personalize gift and date ideas."
        )
        .padding(.top, 4)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            KnotIconView(.searchOutlined, size: 20)
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
                    KnotIconView(.cancelOutlined, size: 20)
                        .foregroundStyle(Theme.textTertiary)
                }
                .accessibilityLabel("Clear search")
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
        let count = viewModel.selectedInterests.count
        let remaining = Constants.Validation.minInterests - count

        return HStack(spacing: 4) {
            Text("\(count) selected")
                .knotFont(Theme.Typography.cta)

            if remaining > 0 {
                Text("(\(remaining) more needed)")
                    .knotFont(Theme.Typography.body)
            } else {
                KnotIconView(.checkCircle, size: 18)
            }
        }
        .foregroundStyle(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    // MARK: - Selection Logic

    private func toggleInterest(_ interest: String) {
        if viewModel.selectedInterests.contains(interest) {
            viewModel.selectedInterests.remove(interest)
        } else {
            viewModel.selectedInterests.insert(interest)
        }
    }

    // MARK: - No-Results / Add Custom

    /// View shown inside the ScrollView when no catalog items match the search.
    /// If the user has typed something, offers an "Add" button to create a custom
    /// interest. With an empty search, this state is unreachable, so we fall back
    /// to a simple message.
    @ViewBuilder
    private var noResultsView: some View {
        let term = trimmedSearchTerm
        VStack(spacing: 16) {
            if term.isEmpty {
                Text("No interests to show.")
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 6) {
                    Text("No matches for \"\(term)\"")
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)

                    Text("Don't see what you're looking for? Add it as a custom interest.")
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                Button(action: addCustomFromSearch) {
                    Text("Add \"\(term)\"")
                        .knotFont(Theme.Typography.cta)
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

    /// Adds the current search text as a custom interest and clears the field.
    private func addCustomFromSearch() {
        let result = viewModel.addCustomInterest(searchText)
        switch result {
        case .added:
            searchText = ""
            addCustomError = nil
        case .empty:
            addCustomError = "Type a name to add a custom interest."
        case .tooLong:
            addCustomError = "Keep it under \(OnboardingViewModel.maxCustomInterestLength) characters."
        case .duplicate:
            addCustomError = "That interest is already in the list."
        case .overlapsLikes:
            // Not reachable from the interests screen.
            addCustomError = "That name is already in use."
        }
    }

    // MARK: - Interest Icons

    /// Maps each interest category to a themed MUI icon. Custom interests
    /// fall back to `.starBorder`.
    static func icon(for interest: String) -> KnotIcon {
        let icons: [String: KnotIcon] = [
            "Travel": .flightOutlined,
            "Cooking": .outdoorGrillOutlined,
            "Movies": .movieOutlined,
            "Music": .musicNoteOutlined,
            "Reading": .menuBookOutlined,
            "Sports": .sportsSoccerOutlined,
            "Gaming": .sportsEsportsOutlined,
            "Art": .brushOutlined,
            "Photography": .photoCameraOutlined,
            "Fitness": .fitnessCenterOutlined,
            "Fashion": .checkroomOutlined,
            "Technology": .laptopMacOutlined,
            "Nature": .natureOutlined,
            "Food": .restaurantOutlined,
            "Coffee": .localCafeOutlined,
            "Wine": .wineBarOutlined,
            "Dancing": .nightlifeOutlined,
            "Theater": .theaterComedyOutlined,
            "Concerts": .libraryMusicOutlined,
            "Museums": .museumOutlined,
            "Shopping": .shoppingBagOutlined,
            "Yoga": .selfImprovementOutlined,
            "Hiking": .hikingOutlined,
            "Beach": .beachAccessOutlined,
            "Pets": .petsOutlined,
            "Cars": .directionsCarOutlined,
            "DIY": .handymanOutlined,
            "Gardening": .yardOutlined,
            "Meditation": .spaOutlined,
            "Podcasts": .podcastsOutlined,
            "Baking": .bakeryDiningOutlined,
            "Camping": .cabinOutlined,
            "Cycling": .directionsBikeOutlined,
            "Running": .directionsRunOutlined,
            "Swimming": .poolOutlined,
            "Skiing": .downhillSkiingOutlined,
            "Surfing": .surfingOutlined,
            "Painting": .paletteOutlined,
            "Board Games": .casinoOutlined,
            "Karaoke": .micOutlined
        ]
        return icons[interest] ?? .starBorder
    }
}

// MARK: - Preview

#Preview("Empty") {
    OnboardingInterestsView()
        .environment(OnboardingViewModel())
}

#Preview("3 Selected") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Alex"
    vm.selectedInterests = ["Travel", "Cooking", "Music"]
    return OnboardingInterestsView()
        .environment(vm)
}

#Preview("5 Selected") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Jordan"
    vm.selectedInterests = ["Travel", "Cooking", "Music", "Hiking", "Photography"]
    return OnboardingInterestsView()
        .environment(vm)
}

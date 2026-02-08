//
//  OnboardingInterestsView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 3 — Interests (5 likes).
//  Step 3.3: Full implementation — dark-themed 3-column image card grid
//            with search bar, selection counter, and exactly-5 validation.
//

import SwiftUI
import LucideIcons

/// Step 3: Select exactly 5 interests the partner likes.
///
/// Dark-themed screen with a 3-column grid of visual interest cards. Each card
/// displays a themed gradient background, an SF Symbol icon, and the interest name.
/// The user must select exactly 5 as "likes."
///
/// Features:
/// - Personalized title using the partner's name from Step 3.2
/// - Search bar to filter the 40 interest categories
/// - Selection counter showing "X selected (Y more needed)"
/// - Shake animation when attempting to select a 6th interest
/// - `.preferredColorScheme(.dark)` for full dark theme including container chrome
struct OnboardingInterestsView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    @State private var searchText = ""
    @State private var shakingCard: String? = nil

    /// Interests filtered by the search text (case-insensitive).
    private var filteredInterests: [String] {
        if searchText.isEmpty { return Constants.interestCategories }
        return Constants.interestCategories.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
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
                    Text("No interests match \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(filteredInterests, id: \.self) { interest in
                            InterestImageCard(
                                title: interest,
                                isSelected: viewModel.selectedInterests.contains(interest),
                                iconName: Self.iconName(for: interest),
                                gradient: Self.cardGradient(for: interest),
                                imageName: Self.imageName(for: interest),
                                isShaking: shakingCard == interest
                            ) {
                                toggleInterest(interest)
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
        .onChange(of: viewModel.selectedInterests) { _, _ in
            viewModel.validateCurrentStep()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "Them" : name

            Text("What does \(displayName) love?")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Choose at least 5 things your partner enjoys.\nThis helps us personalize gift and date ideas.")
                .font(.subheadline)
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
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)

            TextField(
                "",
                text: $searchText,
                prompt: Text("Search interests...")
                    .foregroundStyle(Theme.textTertiary)
            )
            .font(.subheadline)
            .foregroundStyle(.white)
            .tint(Theme.accent)
            .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
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
        let count = viewModel.selectedInterests.count
        let remaining = Constants.Validation.requiredInterests - count

        return HStack(spacing: 4) {
            Text("\(count) selected")
                .fontWeight(.semibold)

            if remaining > 0 {
                Text("(\(remaining) more needed)")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    // MARK: - Selection Logic

    private func toggleInterest(_ interest: String) {
        if viewModel.selectedInterests.contains(interest) {
            viewModel.selectedInterests.remove(interest)
        } else if viewModel.selectedInterests.count < Constants.Validation.requiredInterests {
            viewModel.selectedInterests.insert(interest)
        } else {
            // Reject — already at 5 selected
            triggerShake(for: interest)
        }
    }

    private func triggerShake(for interest: String) {
        shakingCard = interest
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if shakingCard == interest {
                shakingCard = nil
            }
        }
    }

    // MARK: - Card Gradient Colors

    /// Generates a themed gradient for each interest based on its position.
    /// Spreads colors across the full hue spectrum so each card is visually distinct.
    static func cardGradient(for interest: String) -> LinearGradient {
        let index = Constants.interestCategories.firstIndex(of: interest) ?? 0
        let hue = Double(index) / Double(max(Constants.interestCategories.count, 1))

        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.60, brightness: 0.50),
                Color(
                    hue: (hue + 0.03).truncatingRemainder(dividingBy: 1.0),
                    saturation: 0.70,
                    brightness: 0.22
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Asset Catalog Image Name

    /// Maps an interest name to its asset catalog image name.
    /// Convention: `"Interests/interest-{lowercased-hyphenated}"`.
    /// Returns nil if no image has been added to the asset catalog yet.
    static func imageName(for interest: String) -> String? {
        let slug = interest
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let name = "Interests/interest-\(slug)"
        // Only return the name if the image actually exists in the catalog.
        guard UIImage(named: name) != nil else { return nil }
        return name
    }

    // MARK: - SF Symbol Icons

    /// Maps each interest category to a themed SF Symbol.
    static func iconName(for interest: String) -> String {
        let icons: [String: String] = [
            "Travel": "airplane",
            "Cooking": "flame.fill",
            "Movies": "film",
            "Music": "music.note",
            "Reading": "book.fill",
            "Sports": "figure.run",
            "Gaming": "gamecontroller.fill",
            "Art": "paintbrush.pointed.fill",
            "Photography": "camera.fill",
            "Fitness": "dumbbell.fill",
            "Fashion": "tshirt.fill",
            "Technology": "laptopcomputer",
            "Nature": "leaf.fill",
            "Food": "fork.knife",
            "Coffee": "cup.and.saucer.fill",
            "Wine": "wineglass.fill",
            "Dancing": "figure.dance",
            "Theater": "theatermasks.fill",
            "Concerts": "music.mic",
            "Museums": "building.columns.fill",
            "Shopping": "bag.fill",
            "Yoga": "figure.mind.and.body",
            "Hiking": "figure.hiking",
            "Beach": "sun.max.fill",
            "Pets": "pawprint.fill",
            "Cars": "car.fill",
            "DIY": "wrench.and.screwdriver.fill",
            "Gardening": "sparkles",
            "Meditation": "brain.head.profile",
            "Podcasts": "headphones",
            "Baking": "birthday.cake.fill",
            "Camping": "tent.fill",
            "Cycling": "bicycle",
            "Running": "figure.run",
            "Swimming": "figure.pool.swim",
            "Skiing": "figure.skiing.downhill",
            "Surfing": "figure.surfing",
            "Painting": "paintpalette.fill",
            "Board Games": "dice.fill",
            "Karaoke": "mic.fill"
        ]
        return icons[interest] ?? "star.fill"
    }
}

// MARK: - Interest Image Card

/// A visual card representing a single interest category.
///
/// When an image is available in the asset catalog, the card displays it as
/// a full-bleed photo with a dark gradient overlay at the bottom for text
/// readability. When no image is available, it falls back to the themed
/// gradient background with a centered SF Symbol icon.
///
/// Visual states:
/// - **Unselected:** Photo (or gradient) background, white text
/// - **Selected:** Pink border, checkmark badge in top-right corner
/// - **Shaking:** Horizontal shake animation when the 6th selection is rejected
private struct InterestImageCard: View {
    let title: String
    let isSelected: Bool
    let iconName: String
    let gradient: LinearGradient
    /// Asset catalog image name (e.g., "Interests/interest-travel"). Nil if no image added yet.
    let imageName: String?
    let isShaking: Bool
    let action: () -> Void

    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background: prefer asset image, fall back to gradient + icon
                if let imageName {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Gradient background
                    gradient

                    // SF Symbol icon (large, centered, semi-transparent)
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
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        Spacer()
                    }
                }
                .padding(10)

                // Selection checkmark badge — top-right
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
        .offset(x: shakeOffset)
        .animation(.easeInOut(duration: 0.25), value: isSelected)
        .onChange(of: isShaking) { _, newValue in
            if newValue { performShake() }
        }
    }

    /// Quick horizontal shake animation to signal a rejected selection.
    private func performShake() {
        let step = 0.06
        withAnimation(.easeInOut(duration: step)) { shakeOffset = -8 }
        DispatchQueue.main.asyncAfter(deadline: .now() + step) {
            withAnimation(.easeInOut(duration: step)) { shakeOffset = 8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * 2) {
            withAnimation(.easeInOut(duration: step)) { shakeOffset = -5 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * 3) {
            withAnimation(.easeInOut(duration: step)) { shakeOffset = 3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * 4) {
            withAnimation(.easeInOut(duration: step)) { shakeOffset = 0 }
        }
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

//
//  OnboardingDislikesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 4 — Dislikes (5 hard avoids).
//  Step 3.4: Full implementation — dark-themed 3-column image card grid
//            with disabled "liked" interests and exactly-5 validation.
//

import SwiftUI
import LucideIcons

/// Step 4: Select exactly 5 things the partner dislikes ("Hard Avoids").
///
/// Dark-themed screen matching the Interests screen (Step 3.3) visual style.
/// Uses the same 3-column image card grid with themed gradients and SF Symbol icons.
///
/// Key difference from InterestsView: interests already selected as "likes" in
/// Step 3.3 are grayed out and disabled, preventing conflicts.
///
/// Features:
/// - Personalized title using the partner's name from Step 3.2
/// - Search bar to filter the 40 interest categories
/// - Liked interests grayed out with "Already liked" badge — not tappable
/// - Selection counter showing "X selected (Y more needed)"
/// - Shake animation when attempting to select a 6th dislike
struct OnboardingDislikesView: View {
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
                            let isLiked = viewModel.selectedInterests.contains(interest)
                            let isDisliked = viewModel.selectedDislikes.contains(interest)

                            DislikeImageCard(
                                title: interest,
                                isSelected: isDisliked,
                                isDisabled: isLiked,
                                iconName: OnboardingInterestsView.iconName(for: interest),
                                gradient: OnboardingInterestsView.cardGradient(for: interest),
                                imageName: OnboardingInterestsView.imageName(for: interest),
                                isShaking: shakingCard == interest
                            ) {
                                if !isLiked {
                                    toggleDislike(interest)
                                }
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
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "them" : name

            Text("What doesn't \(displayName) like?")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Choose 5 things your partner avoids.\nWe'll make sure to steer clear of these.")
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
        let count = viewModel.selectedDislikes.count
        let remaining = Constants.Validation.requiredDislikes - count

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

    private func toggleDislike(_ interest: String) {
        if viewModel.selectedDislikes.contains(interest) {
            viewModel.selectedDislikes.remove(interest)
        } else if viewModel.selectedDislikes.count < Constants.Validation.requiredDislikes {
            viewModel.selectedDislikes.insert(interest)
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
}

// MARK: - Dislike Image Card

/// A visual card representing a single interest category for the dislikes screen.
///
/// Matches the `InterestImageCard` style from Step 3.3 but adds a disabled state
/// for interests already selected as "likes." Disabled cards appear desaturated
/// with reduced opacity and an "Already liked" badge, and are not tappable.
///
/// When an image is available in the asset catalog, the card displays it as a
/// full-bleed photo. When no image is available, it falls back to the themed
/// gradient background with a centered SF Symbol icon.
///
/// Visual states:
/// - **Unselected:** Photo (or gradient) background, white text
/// - **Selected (disliked):** Pink border, checkmark badge in top-right corner
/// - **Disabled (liked):** Desaturated, reduced opacity, heart badge, not tappable
/// - **Shaking:** Horizontal shake animation when the 6th selection is rejected
private struct DislikeImageCard: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
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
                if isDisabled {
                    // Disabled state — always flat gray regardless of image availability
                    Color(white: 0.18)
                } else if let imageName {
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
                    colors: [.clear, .clear, .black.opacity(isDisabled ? 0.30 : 0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Interest name — bottom-left
                VStack {
                    Spacer()
                    HStack {
                        Text(title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(isDisabled ? 0.35 : 1.0))
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        Spacer()
                    }
                }
                .padding(10)

                // Disabled badge — "Liked" indicator with heart icon
                if isDisabled {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.40))
                                }
                        }
                        Spacer()
                    }
                    .padding(7)
                }

                // Selection checkmark badge — top-right (only when selected as dislike)
                if isSelected && !isDisabled {
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
                        isSelected && !isDisabled
                            ? Color.pink
                            : Color.white.opacity(isDisabled ? 0.03 : 0.06),
                        lineWidth: isSelected && !isDisabled ? 2.5 : 0.5
                    )
            )
            .opacity(isDisabled ? 0.50 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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

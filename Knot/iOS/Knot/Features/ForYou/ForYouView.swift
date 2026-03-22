//
//  ForYouView.swift
//  Knot
//
//  Created on March 20, 2026.
//  Milestone timeline with integrated recommendation CTAs — the main For You tab.
//

import SwiftUI
import LucideIcons

/// The main For You tab view combining a milestone timeline with recommendation entry points.
///
/// Layout:
/// - "Just Because" recommendation card at top
/// - "Upcoming" section with chronological milestone timeline
/// - Each milestone within 60 days has an inline "Get Recommendations" CTA
/// - Tapping any CTA pushes to `RecommendationsView` with milestone context
struct ForYouView: View {

    @State private var viewModel = ForYouViewModel()
    @State private var milestoneFormViewModel = MilestonesViewModel()

    /// Navigation destination for programmatic push.
    @State private var navigationDestination: RecommendationDestination?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if viewModel.isLoading && viewModel.milestones.isEmpty {
                    ProgressView()
                        .tint(Theme.accent)
                } else {
                    timelineContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("For You")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        milestoneFormViewModel.prepareAdd()
                    } label: {
                        Image(uiImage: Lucide.plus)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(Theme.accent)
                }
            }
            .navigationDestination(item: $navigationDestination) { destination in
                RecommendationsView(
                    milestoneId: destination.milestoneId,
                    milestoneContext: destination.context
                )
            }
            .task {
                await viewModel.loadData()
            }
            .sheet(isPresented: $milestoneFormViewModel.showAddSheet) {
                MilestoneFormSheet(viewModel: milestoneFormViewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .onDisappear {
                        Task { await viewModel.refreshMilestones() }
                    }
            }
        }
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // "Just Because" card
                JustBecauseCard(
                    partnerName: viewModel.partnerName,
                    onGenerate: {
                        navigationDestination = RecommendationDestination(
                            milestoneId: nil,
                            context: nil
                        )
                    }
                )

                // Timeline section
                if viewModel.milestones.isEmpty {
                    emptyTimeline
                } else {
                    milestoneTimeline
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 80)
        }
        .refreshable {
            await viewModel.refreshMilestones()
        }
    }

    // MARK: - Milestone Timeline

    private var milestoneTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Upcoming")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 16)

            // Timeline entries
            ForEach(Array(viewModel.milestones.enumerated()), id: \.element.id) { index, milestone in
                let daysUntil = milestone.daysUntil ?? 365
                let urgency = viewModel.urgencyLevel(for: daysUntil)

                TimelineEntryView(
                    milestone: milestone,
                    partnerName: viewModel.partnerName,
                    isLast: index == viewModel.milestones.count - 1,
                    urgency: urgency,
                    formattedDate: viewModel.formattedDate(milestone.milestoneDate),
                    onGetRecommendations: daysUntil <= 60 ? {
                        navigationDestination = RecommendationDestination(
                            milestoneId: milestone.id,
                            context: MilestoneDisplayContext(
                                name: milestone.milestoneName,
                                type: milestone.milestoneType,
                                daysUntil: daysUntil,
                                partnerName: viewModel.partnerName,
                                occasionType: viewModel.occasionType(for: milestone)
                            )
                        )
                    } : nil
                )
            }
        }
    }

    // MARK: - Empty Timeline

    private var emptyTimeline: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)

            Text("No milestones yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Add important dates like birthdays and anniversaries to get proactive reminders and personalized ideas.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                milestoneFormViewModel.prepareAdd()
            } label: {
                Text("Add Your First Milestone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.accent))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Navigation Destination

/// Identifies a recommendation navigation target for programmatic push.
struct RecommendationDestination: Identifiable, Hashable {
    let id = UUID()
    let milestoneId: String?
    let context: MilestoneDisplayContext?

    static func == (lhs: RecommendationDestination, rhs: RecommendationDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Milestone Display Context

/// Lightweight context passed to RecommendationsView when navigating from a milestone CTA.
struct MilestoneDisplayContext {
    let name: String
    let type: String
    let daysUntil: Int
    let partnerName: String
    let occasionType: String
}

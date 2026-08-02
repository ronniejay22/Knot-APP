//
//  MilestoneRecommendationsCoverView.swift
//  Knot
//
//  Milestone push tap-through: full-screen cover presented by `ContentView`
//  when the user taps a milestone push notification. Hosts the standard
//  `RecommendationsView` in preloaded mode so the PRE-GENERATED batch stored
//  when the push fired is displayed instantly (no pipeline re-run).
//

import SwiftUI
import LucideIcons

/// Full-screen shell for the milestone push tap-through.
///
/// Responsibilities beyond hosting `RecommendationsView`:
/// - Best-effort lookup of the milestone via `MilestoneService.listMilestones()`
///   to build the `MilestoneDisplayContext` (title + days-until + occasion
///   type). The push payload only carries the milestone's ID. Proceeds with a
///   nil context on failure — the hosted view then shows a generic title and
///   its generate-fallback stays milestone-scoped.
/// - Fire-and-forget mark-viewed of the originating notification_queue entry.
/// - A close (X) button, mirroring `DeepLinkRecommendationView`.
struct MilestoneRecommendationsCoverView: View {
    let milestoneId: String
    let notificationId: String?
    let onDismiss: @MainActor () -> Void

    @State private var milestoneContext: MilestoneDisplayContext?
    @State private var contextLoaded = false

    var body: some View {
        NavigationStack {
            Group {
                if contextLoaded {
                    RecommendationsView(
                        milestoneId: milestoneId,
                        milestoneContext: milestoneContext,
                        preferPregenerated: true,
                        isModal: true
                    )
                } else {
                    // Brief spinner while the milestone lookup resolves —
                    // typically well under a second.
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.backgroundGradient.ignoresSafeArea())
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(uiImage: Lucide.x)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(Theme.textPrimary)
                }
            }
        }
        .task {
            await loadMilestoneContext()

            if let notificationId {
                // Fire-and-forget: removes the unviewed marker for this
                // notification. Never blocks or fails the tap-through.
                Task {
                    await NotificationHistoryService().markViewed(notificationId: notificationId)
                }
            }
        }
    }

    /// Looks up the milestone so the header can show its name and countdown.
    /// Best-effort — `contextLoaded` flips true regardless so the user is
    /// never stuck on the spinner.
    private func loadMilestoneContext() async {
        defer { contextLoaded = true }

        guard let milestone = try? await MilestoneService().listMilestones()
            .milestones.first(where: { $0.id == milestoneId }) else {
            return
        }

        milestoneContext = MilestoneDisplayContext(
            name: milestone.milestoneName,
            type: milestone.milestoneType,
            daysUntil: milestone.daysUntil ?? 0,
            // RecommendationsView loads the partner name itself for the
            // detail page; the display context doesn't surface it here.
            partnerName: "",
            occasionType: milestone.budgetTier ?? "major_milestone"
        )
    }
}

#Preview {
    MilestoneRecommendationsCoverView(
        milestoneId: "preview-milestone",
        notificationId: nil,
        onDismiss: {}
    )
    .environment(AuthViewModel())
}

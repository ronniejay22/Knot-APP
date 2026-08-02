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
/// **Nothing blocks the first frame.** The header comes from the push payload
/// (`MilestonePushDisplay`), so `RecommendationsView` mounts immediately and
/// its single `GET /by-milestone/{id}` fetch starts right away. An earlier
/// version awaited `MilestoneService().listMilestones()` — fetching the whole
/// milestone list just for a name and a day count — behind a bare spinner,
/// which meant the user sat through two serialized round-trips before seeing
/// anything.
///
/// Also fires a fire-and-forget mark-viewed for the originating
/// notification_queue entry, and shows a close (X) button mirroring
/// `DeepLinkRecommendationView`.
struct MilestoneRecommendationsCoverView: View {
    let milestoneId: String
    let notificationId: String?
    let display: MilestonePushDisplay?
    let onDismiss: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            RecommendationsView(
                milestoneId: milestoneId,
                milestoneContext: milestoneContext,
                preferPregenerated: true,
                isModal: true
            )
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
            if let notificationId {
                // Fire-and-forget: clears the unviewed marker. Never blocks
                // or fails the tap-through.
                await NotificationHistoryService().markViewed(notificationId: notificationId)
            }
        }
    }

    /// Header context built purely from the push payload — no network call.
    ///
    /// `nil` when the push predates the display keys; `RecommendationsView`
    /// then shows its generic title and keeps its generation fallback
    /// milestone-scoped via the `milestoneId`.
    private var milestoneContext: MilestoneDisplayContext? {
        guard let display else { return nil }
        return MilestoneDisplayContext(
            name: display.milestoneName,
            type: "milestone",
            daysUntil: display.daysBefore ?? 0,
            partnerName: display.partnerName ?? "",
            // The push fires for major milestones (birthday/anniversary/
            // holiday); this only seeds the generation fallback's budget tier.
            occasionType: "major_milestone"
        )
    }
}

#Preview {
    MilestoneRecommendationsCoverView(
        milestoneId: "preview-milestone",
        notificationId: nil,
        display: MilestonePushDisplay(
            milestoneName: "Jas's Birthday",
            partnerName: "Jas",
            daysBefore: 7
        ),
        onDismiss: {}
    )
    .environment(AuthViewModel())
}

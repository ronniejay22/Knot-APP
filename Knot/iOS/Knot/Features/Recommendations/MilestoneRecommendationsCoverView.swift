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

    /// Gates the occasion entry modal. Starts on so the card is on screen from
    /// the first frame — the recommendations keep loading behind it, so the
    /// modal costs the user nothing and usually hides the fetch entirely.
    ///
    /// A push from a backend predating this feature carries no display payload,
    /// which would leave the modal showing nothing but its own placeholder
    /// copy. `headerContext` suppresses itself in exactly that case; this does
    /// the same, and the user lands straight on the picks.
    @State private var showEntryModal: Bool

    init(
        milestoneId: String,
        notificationId: String?,
        display: MilestonePushDisplay?,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.milestoneId = milestoneId
        self.notificationId = notificationId
        self.display = display
        self.onDismiss = onDismiss
        _showEntryModal = State(initialValue: display != nil)
    }

    /// The initial gate, exposed for tests — `showEntryModal` is `@State` and
    /// unreadable from outside once the view is constructed.
    var showsEntryModalOnAppear: Bool { display != nil }

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
        .fullScreenCover(isPresented: $showEntryModal) {
            OccasionEntryModal(
                copy: entryCopy,
                // Continue and close land in the same place — the picks are
                // already behind the card. The X is "skip the framing", not
                // "leave", which is what the toolbar X is for.
                onContinue: { dismissEntryModal() },
                onClose: { dismissEntryModal() }
            )
            .presentationBackground(.clear)
        }
        .task {
            if let notificationId {
                // Fire-and-forget: clears the unviewed marker. Never blocks
                // or fails the tap-through.
                await NotificationHistoryService().markViewed(notificationId: notificationId)
            }
        }
    }

    /// Copy for the tapped occasion, built entirely from the push payload.
    private var entryCopy: OccasionCopy {
        OccasionCopy.resolve(
            category: display?.occasionCategory ?? OccasionCopy.defaultCategory,
            partnerName: display?.partnerName,
            daysUntil: display?.daysBefore,
            milestoneName: display?.milestoneName
        )
    }

    /// Tears the cover down with no animation — `OccasionEntryModal` has
    /// already played its own exit by the time this runs, so the system's
    /// bottom-slide would be a second, conflicting transition.
    private func dismissEntryModal() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showEntryModal = false }
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
            daysBefore: 7,
            occasionCategory: "birthday"
        ),
        onDismiss: {}
    )
    .environment(AuthViewModel())
}

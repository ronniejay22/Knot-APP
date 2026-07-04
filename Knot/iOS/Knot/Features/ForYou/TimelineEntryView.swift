//
//  TimelineEntryView.swift
//  Knot
//
//  Created on March 20, 2026.
//  Individual milestone row in the For You timeline with vertical line, dot, and CTA.
//

import SwiftUI
import LucideIcons

/// A single milestone entry in the vertical timeline.
///
/// Layout:
/// ```
/// [dot]── Mar 28 ────────────
///  |     Birthday cake  Alex's Birthday        [✦]
///  |     in 8 days
///  |
/// ```
/// The trailing `[✦]` is the recommendation icon button.
struct TimelineEntryView: View {

    let milestone: MilestoneItemResponse
    let partnerName: String
    let isLast: Bool
    let urgency: MilestoneUrgency
    let formattedDate: String
    let onGetRecommendations: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline line + dot
            timelineIndicator
                .frame(width: 32)

            // Content
            milestoneContent
                .padding(.leading, 8)
                .padding(.bottom, isLast ? 0 : 24)
        }
    }

    // MARK: - Timeline Indicator

    private var timelineIndicator: some View {
        VStack(spacing: 0) {
            // Dot
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .fill(dotColor.opacity(0.3))
                        .frame(width: 18, height: 18)
                        .opacity(urgency == .critical || urgency == .soon ? 1 : 0)
                )
                .padding(.top, 5)

            // Line
            if !isLast {
                Rectangle()
                    .fill(Theme.surfaceBorder)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Content

    private var milestoneContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date badge
            KnotBadge(formattedDate, variant: .secondary, size: .sm)

            // Info row: milestone details on the leading edge, recommendation
            // icon button on the trailing edge.
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    // Milestone info
                    HStack(spacing: 8) {
                        Image(systemName: MilestonesViewModel.iconName(for: milestone.milestoneType))
                            .font(.subheadline)
                            .foregroundStyle(milestoneTypeColor)

                        Text(milestone.milestoneName)
                            .knotFont(Theme.Typography.cta)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }

                    // Countdown
                    if let days = milestone.daysUntil {
                        Text(MilestonesViewModel.daysUntilText(days))
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(dotColor)
                    }
                }

                Spacer(minLength: 8)

                // Recommendation icon button
                if let action = onGetRecommendations {
                    Button(action: action) {
                        Image(uiImage: Lucide.sparkles)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Theme.accent)
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Get recommendations for \(milestone.milestoneName)")
                }
            }
        }
    }

    // MARK: - Colors

    private var dotColor: Color {
        switch urgency {
        case .critical: return .red
        case .soon: return .orange
        case .upcoming: return .yellow
        case .planning: return Theme.accent
        case .distant: return Theme.textTertiary
        }
    }

    private var milestoneTypeColor: Color {
        switch milestone.milestoneType {
        case "birthday": return .pink
        case "anniversary": return .red
        case "holiday": return .orange
        case "custom": return Theme.accent
        default: return Theme.accent
        }
    }
}

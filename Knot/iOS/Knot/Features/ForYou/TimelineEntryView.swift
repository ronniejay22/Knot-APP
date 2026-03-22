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
///  |     Birthday cake  Alex's Birthday
///  |     in 8 days
///  |     [ Get Recommendations → ]   (if ≤60 days)
///  |
/// ```
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
            Text(formattedDate)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Theme.surfaceElevated)
                )

            // Milestone info
            HStack(spacing: 8) {
                Image(systemName: MilestonesViewModel.iconName(for: milestone.milestoneType))
                    .font(.subheadline)
                    .foregroundStyle(milestoneTypeColor)

                Text(milestone.milestoneName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }

            // Countdown
            if let days = milestone.daysUntil {
                Text(MilestonesViewModel.daysUntilText(days))
                    .font(.caption)
                    .foregroundStyle(dotColor)
            }

            // Recommendation CTA (shown for milestones within 60 days)
            if let action = onGetRecommendations {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(uiImage: Lucide.sparkles)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)

                        Text("Get Recommendations")
                            .font(.caption.weight(.semibold))

                        Spacer()

                        Image(uiImage: Lucide.chevronRight)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.accent.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .padding(.top, 2)
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

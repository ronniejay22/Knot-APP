//
//  NotificationsView.swift
//  Knot
//
//  Created on February 12, 2026.
//  Step 7.7: Notification History screen showing past notifications
//  with links to associated recommendations.
//

import SwiftUI
import LucideIcons

/// Notification History screen showing past notifications with milestone info.
///
/// Features:
/// - Displays sent notifications in reverse chronological order
/// - Shows milestone name, type icon, days-before label, and sent date
/// - Unviewed notifications have an accent dot indicator
/// - Tapping a notification opens a sheet with associated recommendations
/// - Empty state when no notifications exist
/// - Pull-to-refresh
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = NotificationsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                Theme.backgroundGradient.ignoresSafeArea()

                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    // Initial loading state
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(1.2)
                } else if viewModel.notifications.isEmpty {
                    // Empty state
                    emptyStateView
                } else {
                    // Notifications list
                    List {
                        ForEach(viewModel.notifications) { notification in
                            notificationRow(notification)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if notification.recommendationsCount > 0 {
                                        Task {
                                            await viewModel.selectNotification(notification)
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await viewModel.loadHistory()
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(uiImage: Lucide.x)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.white)
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: Binding(
                get: { viewModel.showRecommendationsSheet },
                set: { if !$0 { viewModel.dismissRecommendations() } }
            )) {
                recommendationsSheet
            }
            .task {
                await viewModel.loadHistory()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(uiImage: Lucide.bellRing)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(Theme.textTertiary)

            Text("No notifications yet")
                .font(.headline)
                .foregroundStyle(.white)

            Text("You'll see past milestone reminders here once they've been sent.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Notification Row

    private func notificationRow(_ notification: NotificationHistoryItemResponse) -> some View {
        HStack(spacing: 14) {
            // Milestone type icon
            Image(systemName: viewModel.milestoneTypeIcon(notification.milestoneType))
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent.opacity(0.12))
                )

            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(notification.milestoneName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // Unviewed indicator dot
                    if notification.viewedAt == nil && notification.status == "sent" {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 7, height: 7)
                    }
                }

                HStack(spacing: 6) {
                    Text(viewModel.daysBeforeLabel(notification.daysBefore))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)

                    Text(viewModel.formattedDate(notification.sentAt))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                // Status and recommendations count
                HStack(spacing: 8) {
                    statusBadge(notification.status)

                    if notification.recommendationsCount > 0 {
                        HStack(spacing: 3) {
                            Image(uiImage: Lucide.sparkles)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 10, height: 10)
                                .foregroundStyle(Theme.accent)

                            Text("\(notification.recommendationsCount) recommendations")
                                .font(.caption2)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }

            Spacer()

            // Chevron if has recommendations
            if notification.recommendationsCount > 0 {
                Image(uiImage: Lucide.chevronRight)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Status Badge

    private func statusBadge(_ status: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status == "sent" ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 9))

            Text(status == "sent" ? "Delivered" : "Failed")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(status == "sent" ? .green : .red)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill((status == "sent" ? Color.green : Color.red).opacity(0.12))
        )
    }

    // MARK: - Recommendations Sheet

    private var recommendationsSheet: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if viewModel.isLoadingRecommendations {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(1.2)
                } else if let error = viewModel.recommendationsError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else if viewModel.milestoneRecommendations.isEmpty {
                    VStack(spacing: 12) {
                        Image(uiImage: Lucide.sparkles)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .foregroundStyle(Theme.textTertiary)

                        Text("No recommendations")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("No recommendations were generated for this notification.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(viewModel.milestoneRecommendations) { rec in
                                recommendationCard(rec)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(viewModel.selectedNotification?.milestoneName ?? "Recommendations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.dismissRecommendations()
                    } label: {
                        Image(uiImage: Lucide.x)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    // MARK: - Recommendation Card

    private func recommendationCard(_ rec: MilestoneRecommendationItemResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: type icon + title
            HStack(spacing: 10) {
                Image(systemName: recommendationTypeIcon(rec.recommendationType))
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let merchantName = rec.merchantName, !merchantName.isEmpty {
                            Text(merchantName)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }

                        if let price = viewModel.formattedPrice(cents: rec.priceCents) {
                            Text(price)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }

                Spacer()
            }

            // Description
            if let description = rec.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
            }

            // External link button
            if let urlString = rec.externalUrl, let url = URL(string: urlString) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(uiImage: Lucide.externalLink)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)

                        Text("View Details")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func recommendationTypeIcon(_ type: String) -> String {
        switch type {
        case "gift": return "gift.fill"
        case "experience": return "sparkles"
        case "date": return "heart.fill"
        default: return "star.fill"
        }
    }
}

// MARK: - Previews

#Preview("Notifications — Empty") {
    NotificationsView()
}

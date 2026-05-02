//
//  HintsListView.swift
//  Knot
//
//  Created on February 9, 2026.
//  Step 4.5: Full hints list view with swipe-to-delete.
//

import SwiftUI
import LucideIcons

/// Full-screen list of all captured hints in reverse chronological order.
///
/// Features:
/// - Displays hint text, date captured, and source icon
/// - Swipe-to-delete functionality
/// - Empty state when no hints exist
/// - Pull-to-refresh
struct HintsListView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = HintsListViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                Theme.backgroundGradient.ignoresSafeArea()

                if viewModel.isLoading && viewModel.hints.isEmpty {
                    // Initial loading state
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(1.2)
                } else if viewModel.hints.isEmpty {
                    // Empty state
                    emptyStateView
                } else {
                    // Hints list
                    List {
                        ForEach(viewModel.hints) { hint in
                            hintRow(hint)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await viewModel.loadHints()
                    }
                }
            }
            .navigationTitle("All Hints")
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
                            .foregroundStyle(Theme.textPrimary)
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
            .task {
                await viewModel.loadHints()
            }
        }
    }

    // MARK: - Hint Row

    /// A single hint row with swipe-to-delete.
    private func hintRow(_ hint: HintItem) -> some View {
        KnotCard(padding: .md) {
            HStack(spacing: 14) {
                // Source icon
                Image(uiImage: hint.source == "voice_transcription" ? Lucide.mic : Lucide.penLine)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.accent.opacity(0.12))
                    )

                // Text and date
                VStack(alignment: .leading, spacing: 4) {
                    Text(hint.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        Text(hint.createdAt, style: .date)
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)

                        Text(hint.createdAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)

                        if hint.isUsed {
                            Spacer()

                            KnotBadge(
                                "Used",
                                variant: .success,
                                size: .sm,
                                leadingIcon: Lucide.check
                            )
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteHint(hint)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .opacity(viewModel.isDeletingHintId == hint.id ? 0.5 : 1.0)
    }

    // MARK: - Empty State

    /// Empty state when no hints have been captured.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(uiImage: Lucide.messageSquarePlus)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 8) {
                Text("No hints yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Start capturing hints from the Home screen to remember what your partner mentions.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            KnotButton(
                "Back to Home",
                variant: .primary,
                size: .md,
                shape: .pill,
                action: { dismiss() }
            )
            .fixedSize()
            .padding(.top, 8)
        }
        .frame(maxWidth: 300)
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    /// Deletes a hint with animation.
    private func deleteHint(_ hint: HintItem) {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Animate removal
        Task {
            await viewModel.deleteHint(id: hint.id)
        }
    }
}

// MARK: - Previews

#Preview("Hints List") {
    HintsListView()
}

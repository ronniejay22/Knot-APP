//
//  HintsTabView.swift
//  Knot
//
//  Created on February 27, 2026.
//  Dedicated Hints tab — hint capture input and recent hints history.
//  Extracted from HomeView as part of the recommendation-first navigation restructure.
//

import SwiftUI
import LucideIcons

/// Dedicated Hints tab for capturing and reviewing partner hints.
///
/// Contains:
/// - **Hint Capture** — text input + microphone button for recording observations
/// - **Recent Hints** — preview of last 3 captured hints with "View All" link
///
/// Hints feed the recommendation engine with preference data, making this
/// the second most important user action after browsing recommendations.
struct HintsTabView: View {
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var viewModel = HomeViewModel()

    /// Text for the hint capture input.
    @State private var hintText = ""

    /// Controls the Hints List sheet presentation.
    @State private var showHintsList = false

    /// Focus state for the hint text field.
    @FocusState private var isHintFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // MARK: - Offline Banner
                        if !networkMonitor.isConnected {
                            offlineBanner
                        }

                        // MARK: - Hint Capture
                        hintCaptureSection
                            .disabled(!networkMonitor.isConnected)
                            .opacity(networkMonitor.isConnected ? 1.0 : 0.5)

                        // MARK: - Recent Hints
                        recentHintsSection
                            .disabled(!networkMonitor.isConnected)
                            .opacity(networkMonitor.isConnected ? 1.0 : 0.5)

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Hints")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .sheet(isPresented: $showHintsList) {
                HintsListView()
            }
            .onChange(of: showHintsList) { _, isPresented in
                if !isPresented {
                    Task {
                        await viewModel.loadRecentHints()
                    }
                }
            }
            .task {
                await viewModel.loadVault()
                await viewModel.loadRecentHints()
            }
        }
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(uiImage: Lucide.wifiOff)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(.white)

            Text("No internet connection. Connect to use Knot.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.85))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
    }

    // MARK: - Hint Capture Section

    private var hintCaptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(uiImage: Lucide.lightbulb)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Theme.accent)

                Text("Capture a Hint")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            HStack(alignment: .bottom, spacing: 10) {
                ZStack {
                    ZStack(alignment: .topLeading) {
                        if hintText.isEmpty && !viewModel.showHintSuccess {
                            Text("What did they mention today?")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 10)
                        }

                        TextEditor(text: $hintText)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 40, maxHeight: 80)
                            .focused($isHintFieldFocused)
                            .opacity(viewModel.showHintSuccess ? 0 : 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        viewModel.showHintSuccess
                                            ? Color.green.opacity(0.5)
                                            : (isHintFieldFocused ? Theme.accent.opacity(0.5) : Theme.surfaceBorder),
                                        lineWidth: 1
                                    )
                            )
                    )

                    if viewModel.showHintSuccess {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)

                            Text("Hint saved!")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.showHintSuccess)

                VStack(spacing: 8) {
                    Button {
                        // Voice capture (Step 4.3)
                    } label: {
                        Image(uiImage: Lucide.mic)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Theme.surface)
                                    .overlay(
                                        Circle()
                                            .stroke(Theme.surfaceBorder, lineWidth: 1)
                                    )
                            )
                    }

                    Button {
                        submitHint()
                    } label: {
                        ZStack {
                            if viewModel.isSubmittingHint {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.7)
                            } else {
                                Image(uiImage: Lucide.arrowUp)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(canSubmitHint ? Theme.accent : Theme.surface)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            canSubmitHint ? Theme.accent : Theme.surfaceBorder,
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .disabled(!canSubmitHint || viewModel.isSubmittingHint)
                }
            }

            HStack {
                if let error = viewModel.hintErrorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(hintText.count)/\(Constants.Validation.maxHintLength)")
                    .font(.caption2)
                    .foregroundStyle(hintCharacterCountColor)
            }
        }
    }

    // MARK: - Recent Hints Section

    private var recentHintsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(uiImage: Lucide.sparkles)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.accent)

                    Text("Recent Hints")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                if !viewModel.recentHints.isEmpty {
                    Button {
                        showHintsList = true
                    } label: {
                        Text("View All")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            if viewModel.recentHints.isEmpty {
                emptyHintsCard
            } else {
                ForEach(viewModel.recentHints) { hint in
                    hintPreviewCard(hint)
                }
            }
        }
    }

    // MARK: - Component: Empty Hints Card

    private var emptyHintsCard: some View {
        VStack(spacing: 10) {
            Image(uiImage: Lucide.messageSquarePlus)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .foregroundStyle(Theme.textTertiary)

            Text("No hints yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            Text("Capture what your partner mentions — favorite things, wishes, places they want to visit.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            Theme.surfaceBorder,
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                        )
                )
        )
    }

    // MARK: - Component: Hint Preview Card

    private func hintPreviewCard(_ hint: HintPreview) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: hint.source == "voice_transcription" ? Lucide.mic : Lucide.penLine)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(hint.text)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(hint.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private var canSubmitHint: Bool {
        let trimmed = hintText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && hintText.count <= Constants.Validation.maxHintLength
    }

    private var hintCharacterCountColor: Color {
        if hintText.count > Constants.Validation.maxHintLength {
            return .red
        } else if hintText.count >= 450 {
            return .red.opacity(0.8)
        } else {
            return Theme.textTertiary
        }
    }

    private func submitHint() {
        guard canSubmitHint else { return }

        let textToSubmit = hintText.trimmingCharacters(in: .whitespacesAndNewlines)

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        hintText = ""
        isHintFieldFocused = false

        Task {
            let success = await viewModel.submitHint(text: textToSubmit)

            if success {
                let successGenerator = UINotificationFeedbackGenerator()
                successGenerator.notificationOccurred(.success)
            } else {
                let errorGenerator = UINotificationFeedbackGenerator()
                errorGenerator.notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Previews

#Preview("Hints Tab") {
    HintsTabView()
        .environment(NetworkMonitor())
}

//
//  MilestoneDateModal.swift
//  Knot
//
//  Month/day capture: a tappable date field that opens a centered dialog with
//  two side-by-side wheel pickers (Month | Day) and Cancel / Save actions.
//
//  Mirrors the RelationshipLengthField + RelationshipLengthModal pattern, but
//  captures a month/day pair instead of a tenure. Used by the onboarding
//  birthday and anniversary steps so a date is never auto-chosen — the field
//  starts empty and `hasSelection` only flips true once the user taps Save.
//

import SwiftUI
import LucideIcons

// MARK: - Field

/// Tappable select-style field showing the chosen date (or a placeholder when
/// nothing has been picked yet) and a dropdown chevron. Opens
/// `MilestoneDateModal` as a centered dialog.
struct MilestoneDateField: View {
    @Binding var month: Int
    @Binding var day: Int
    /// Whether the user has explicitly chosen a date. When `false`, the field
    /// shows `placeholder` and the modal opens at the current `month`/`day`
    /// defaults without committing them until Save.
    @Binding var hasSelection: Bool

    /// Header shown at the top of the modal (e.g. "Set Birthday").
    var title: String
    /// Text shown in the field before a date is chosen.
    var placeholder: String = "Select a date"

    @State private var showingModal = false

    var body: some View {
        Button {
            present()
        } label: {
            HStack(spacing: 8) {
                Text(hasSelection ? formattedMilestoneDate(month: month, day: day) : placeholder)
                    .knotFont(Theme.Typography.body)
                    .foregroundStyle(hasSelection ? Theme.textPrimary : Theme.textTertiary)

                Spacer(minLength: 0)

                Image(uiImage: Lucide.chevronDown)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.surfaceBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showingModal) {
            MilestoneDateModal(
                title: title,
                initialMonth: month,
                initialDay: day,
                onSave: { newMonth, newDay in
                    month = newMonth
                    day = newDay
                    hasSelection = true
                    dismiss()
                },
                onClose: { dismiss() }
            )
            .presentationBackground(.clear)
        }
    }

    /// Present without the cover's built-in bottom-slide — the modal runs its
    /// own fade/scale animation instead.
    private func present() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showingModal = true }
    }

    /// Tear down the (already animated-out) modal instantly, so there's no
    /// trailing bottom-slide on the way out either.
    private func dismiss() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showingModal = false }
    }
}

// MARK: - Modal

/// Centered dialog with Month / Day wheel pickers and Cancel / Save actions.
/// The card and its dimmed backdrop animate independently: the backdrop fades
/// while the card scales + fades in with a smooth spring (no bottom slide).
struct MilestoneDateModal: View {
    let title: String
    let initialMonth: Int
    let initialDay: Int
    let onSave: @MainActor (Int, Int) -> Void
    let onClose: @MainActor () -> Void

    @State private var month: Int
    @State private var day: Int
    @State private var appeared = false

    private let appearAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.86)
    private let dismissAnimation: Animation = .easeIn(duration: 0.2)
    private let dismissDuration: Duration = .seconds(0.2)

    init(
        title: String,
        initialMonth: Int,
        initialDay: Int,
        onSave: @escaping @MainActor (Int, Int) -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.initialMonth = initialMonth
        self.initialDay = initialDay
        self.onSave = onSave
        self.onClose = onClose
        _month = State(initialValue: initialMonth)
        _day = State(initialValue: initialDay)
    }

    var body: some View {
        ZStack {
            // Dimmed + blurred backdrop — fades independently of the card.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Theme.overlayDim)
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)
                .onTapGesture { animateOut(then: onClose) }

            // The card — scales + fades on its own.
            card
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .shadow(Theme.Shadow.lg)
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            // Defer one runloop tick so the animation runs from the initial
            // (collapsed) state rather than being coalesced into first render.
            Task { @MainActor in
                await Task.yield()
                withAnimation(appearAnimation) { appeared = true }
            }
        }
    }

    private var card: some View {
        KnotCard(variant: .elevated, padding: .xl, radius: Theme.Radius.xl) {
            VStack(alignment: .leading, spacing: 28) {
                Text(title)
                    .knotFont(Theme.Typography.onboardingSubHeader)
                    .foregroundStyle(Theme.textPrimary)

                wheels
                footer
            }
        }
    }

    private var wheels: some View {
        HStack(spacing: 0) {
            Picker("Month", selection: $month) {
                ForEach(1...12, id: \.self) { m in
                    Text(MilestoneMonthNames.all[m - 1]).tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .onChange(of: month) { _, newMonth in
                day = OnboardingViewModel.clampDay(day, toMonth: newMonth)
            }

            Picker("Day", selection: $day) {
                ForEach(1...OnboardingViewModel.daysInMonth(month), id: \.self) { d in
                    Text("\(d)").tag(d)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 160)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            KnotButton("Cancel", variant: .secondary, size: .lg, shape: .pill) {
                animateOut(then: onClose)
            }
            .frame(maxWidth: .infinity)

            KnotButton("Save", variant: .primary, size: .lg, shape: .pill) {
                let chosenMonth = month
                let chosenDay = day
                animateOut { onSave(chosenMonth, chosenDay) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Animate the card + backdrop out, then hand control back to the parent
    /// (which removes the cover with no animation).
    private func animateOut(then action: @escaping @MainActor () -> Void) {
        withAnimation(dismissAnimation) { appeared = false }
        Task { @MainActor in
            try? await Task.sleep(for: dismissDuration)
            action()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Field") {
    struct Wrapper: View {
        @State private var month = 7
        @State private var day = 22
        @State private var hasSelection = false
        var body: some View {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                MilestoneDateField(
                    month: $month,
                    day: $day,
                    hasSelection: $hasSelection,
                    title: "Set Birthday"
                )
                .padding(24)
            }
        }
    }
    return Wrapper()
}

#Preview("Modal") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        MilestoneDateModal(
            title: "Set Birthday",
            initialMonth: 7,
            initialDay: 22,
            onSave: { _, _ in },
            onClose: {}
        )
    }
}
#endif

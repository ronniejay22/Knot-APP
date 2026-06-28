//
//  RelationshipLengthModal.swift
//  Knot
//
//  Relationship-tenure capture: a tappable "Relationship Length" field that
//  opens a centered stepper dialog. Ported from the "Create Relationship
//  Length Modal" Figma frame and restyled with the Knot design system.
//
//  Used by both the onboarding tenure step (OnboardingTenureView) and the
//  Settings → Edit Profile basic-info sheet (EditBasicInfoSheet), which
//  previously each carried their own near-identical dual `.menu` pickers.
//

import SwiftUI
import LucideIcons

// MARK: - Formatting

/// Human-readable tenure summary (e.g., "2 years, 6 months") with correct
/// singular/plural agreement. Shared by the field and both call sites that
/// used to declare a private `tenureSummary` of their own.
func relationshipTenureSummary(months totalMonths: Int) -> String {
    let years = totalMonths / 12
    let months = totalMonths % 12
    let yearText = years == 1 ? "1 year" : "\(years) years"
    let monthText = months == 1 ? "1 month" : "\(months) months"
    return "\(yearText), \(monthText)"
}

// MARK: - Stepper bounds

/// Allowed ranges for the steppers. Years bump to 50 (from the imported
/// design's `min(+1, 50)`); months clamp 0–11 with no wrap — a deliberate
/// override of the Figma's `% 12` modulo behavior, which silently jumps
/// 11 → 0 without adding a year.
enum RelationshipLengthBounds {
    static let years = 0...50
    static let months = 0...11
}

// MARK: - Field

/// Tappable select-style field showing the current tenure and a dropdown
/// chevron. Opens `RelationshipLengthModal` as a centered dialog.
struct RelationshipLengthField: View {
    @Binding var months: Int

    /// Optional label above the field. Defaults to "Relationship Length"
    /// to match the imported design.
    var label: String = "Relationship Length"

    /// Whether the user has explicitly chosen a length. When provided and
    /// `false`, the field shows `placeholder` and the modal opens at the
    /// current `months` default without committing it until Save. When `nil`
    /// the field always shows the formatted tenure (the Edit Profile flow).
    var hasSelection: Binding<Bool>? = nil

    /// Text shown in the field before a length is chosen.
    var placeholder: String = "Select length"

    @State private var showingModal = false

    /// True when an explicit selection is required but not yet made.
    private var isUnset: Bool {
        if let hasSelection { return !hasSelection.wrappedValue }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .knotFont(Theme.Typography.cta)

            Button {
                present()
            } label: {
                HStack(spacing: 8) {
                    Text(isUnset ? placeholder : relationshipTenureSummary(months: months))
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(isUnset ? Theme.textTertiary : Theme.textPrimary)

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
        }
        .fullScreenCover(isPresented: $showingModal) {
            RelationshipLengthModal(
                initialMonths: months,
                onSave: { newMonths in
                    months = newMonths
                    hasSelection?.wrappedValue = true
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

/// Centered dialog with Years / Months steppers and Cancel / Save actions.
/// The card and its dimmed backdrop animate independently: the backdrop fades
/// while the card scales + fades in with a smooth spring (no bottom slide).
struct RelationshipLengthModal: View {
    let initialMonths: Int
    let onSave: @MainActor (Int) -> Void
    let onClose: @MainActor () -> Void

    @State private var years: Int
    @State private var months: Int
    @State private var appeared = false

    private let appearAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.86)
    private let dismissAnimation: Animation = .easeIn(duration: 0.2)
    private let dismissDuration: Duration = .seconds(0.2)

    init(
        initialMonths: Int,
        onSave: @escaping @MainActor (Int) -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.initialMonths = initialMonths
        self.onSave = onSave
        self.onClose = onClose
        _years = State(initialValue: initialMonths / 12)
        _months = State(initialValue: initialMonths % 12)
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
                header
                stepperRow(label: "Years", value: $years, range: RelationshipLengthBounds.years)
                stepperRow(label: "Months", value: $months, range: RelationshipLengthBounds.months)
                footer
            }
        }
    }

    private var header: some View {
        Text("Set Relationship Length")
            .knotFont(Theme.Typography.onboardingSubHeader)
            .foregroundStyle(Theme.textPrimary)
    }

    private func stepperRow(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 16) {
                KnotIconButton(icon: Lucide.minus, variant: .surface, size: .lg) {
                    value.wrappedValue = max(value.wrappedValue - 1, range.lowerBound)
                }

                Text("\(value.wrappedValue)")
                    .knotFont(Theme.Typography.heroDisplay)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                KnotIconButton(icon: Lucide.plus, variant: .surface, size: .lg) {
                    value.wrappedValue = min(value.wrappedValue + 1, range.upperBound)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            KnotButton("Cancel", variant: .secondary, size: .lg, shape: .pill) {
                animateOut(then: onClose)
            }
            .frame(maxWidth: .infinity)

            KnotButton("Save", variant: .primary, size: .lg, shape: .pill) {
                let total = years * 12 + months
                animateOut { onSave(total) }
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
        @State private var months = 30
        var body: some View {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                RelationshipLengthField(months: $months)
                    .padding(24)
            }
        }
    }
    return Wrapper()
}

#Preview("Modal") {
    ZStack {
        Theme.backgroundGradient.ignoresSafeArea()
        RelationshipLengthModal(initialMonths: 30, onSave: { _ in }, onClose: {})
    }
}
#endif

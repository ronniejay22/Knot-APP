//
//  BudgetRangeSlider.swift
//  Knot
//
//  Custom dual-thumb range slider used by the budget tier cards. Two thumbs
//  pick a min and max spending amount (in cents), snapping to a per-tier step.
//  The max thumb's top stop is open-ended: reaching the ceiling stores the
//  shared "unlimited" sentinel and the readout shows "$<ceiling>+".
//

import SwiftUI

// MARK: - Pure Math Helpers
//
// Namespaced static functions (no SwiftUI dependency) so the test target can
// exercise the snapping / position math without instantiating a view.
enum BudgetSliderMath {
    /// Snaps a raw cents value to the nearest `step`, clamped to `lower...upper`.
    static func snap(_ raw: Int, step: Int, lower: Int, upper: Int) -> Int {
        guard step > 0, upper > lower else { return min(max(raw, lower), upper) }
        let clamped = min(max(raw, lower), upper)
        let steps = ((clamped - lower) + step / 2) / step
        let snapped = lower + steps * step
        return min(max(snapped, lower), upper)
    }

    /// Converts an x position (in `0...trackWidth`) to a snapped cents value.
    static func cents(forX x: CGFloat, trackWidth: CGFloat, lower: Int, upper: Int, step: Int) -> Int {
        guard trackWidth > 0, upper > lower else { return lower }
        let fraction = min(max(Double(x / trackWidth), 0), 1)
        let raw = lower + Int((Double(upper - lower) * fraction).rounded())
        return snap(raw, step: step, lower: lower, upper: upper)
    }

    /// Converts a cents value to an x position on the track (`0...trackWidth`).
    /// Values outside `lower...upper` are clamped, so the "unlimited" sentinel
    /// positions the thumb at the ceiling.
    static func x(forCents cents: Int, trackWidth: CGFloat, lower: Int, upper: Int) -> CGFloat {
        guard upper > lower, trackWidth > 0 else { return 0 }
        let clamped = min(max(cents, lower), upper)
        let fraction = Double(clamped - lower) / Double(upper - lower)
        return CGFloat(fraction) * trackWidth
    }
}

// MARK: - Budget Range Slider

/// A dual-thumb range slider over a tinted track.
///
/// - Both thumbs snap to `step` and keep a one-step gap so `max >= min` always
///   holds (validation can never fail from interaction).
/// - The max thumb is open-ended: when it snaps to `ceiling`, `maxCents` is set
///   to `BudgetTierConfig.unlimitedMaxCents`; the readout shows "$<ceiling>+".
struct BudgetRangeSlider: View {
    @Binding var minCents: Int
    @Binding var maxCents: Int
    let lower: Int          // tier floor, e.g. 500 ($5)
    let ceiling: Int        // tier ceiling / "+" point, e.g. 20000 ($200)
    let step: Int           // snap increment, e.g. 500 ($5)
    let accent: Color

    private let thumbDiameter: CGFloat = 28
    private let trackHeight: CGFloat = 6
    private var minGap: Int { step }

    private enum Thumb { case lower, upper }
    /// Thumb owned by the active drag, locked on the first event so a fast drag
    /// past the other thumb can't "hand off" mid-gesture.
    @State private var activeThumb: Thumb?

    /// The max value pinned to the visible track (the sentinel maps to ceiling).
    private var cappedMax: Int { min(maxCents, ceiling) }

    var body: some View {
        GeometryReader { geo in
            // Inset the track so thumb centers travel 0...trackWidth and the
            // glyph never clips the card edge.
            let trackWidth = geo.size.width - thumbDiameter
            let minX = BudgetSliderMath.x(forCents: minCents, trackWidth: trackWidth, lower: lower, upper: ceiling)
            let maxX = BudgetSliderMath.x(forCents: cappedMax, trackWidth: trackWidth, lower: lower, upper: ceiling)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surfaceElevated)
                    .frame(width: trackWidth, height: trackHeight)
                    .offset(x: thumbDiameter / 2)

                Capsule()
                    .fill(accent)
                    .frame(width: max(0, maxX - minX), height: trackHeight)
                    .offset(x: thumbDiameter / 2 + minX)

                thumb(at: minX, isLower: true)
                thumb(at: maxX, isLower: false)
            }
            .frame(height: thumbDiameter)
            .contentShape(Rectangle())
            .gesture(drag(trackWidth: trackWidth, minX: minX, maxX: maxX))
        }
        .frame(height: thumbDiameter)
    }

    private func thumb(at x: CGFloat, isLower: Bool) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(accent, lineWidth: 2))
            .frame(width: thumbDiameter, height: thumbDiameter)
            .shadow(Theme.Shadow.sm)
            .offset(x: x)
            .accessibilityElement()
            .accessibilityLabel(isLower ? "Minimum budget" : "Maximum budget")
            .accessibilityValue(isLower ? formatBudgetDollars(minCents) : maxLabel)
            .accessibilityAddTraits(.allowsDirectInteraction)
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? step : -step
                if isLower {
                    minCents = BudgetSliderMath.snap(
                        minCents + delta, step: step,
                        lower: lower, upper: max(lower, cappedMax - minGap)
                    )
                } else {
                    setMax(BudgetSliderMath.snap(
                        maxCents + delta, step: step,
                        lower: minCents + minGap, upper: ceiling
                    ))
                }
            }
    }

    private var maxLabel: String {
        maxCents >= ceiling ? "\(formatBudgetDollars(ceiling))+" : formatBudgetDollars(maxCents)
    }

    private func drag(trackWidth: CGFloat, minX: CGFloat, maxX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeThumb == nil {
                    let touchX = value.startLocation.x - thumbDiameter / 2
                    activeThumb = abs(touchX - minX) <= abs(touchX - maxX) ? .lower : .upper
                }
                let touchX = value.location.x - thumbDiameter / 2
                let raw = BudgetSliderMath.cents(
                    forX: touchX, trackWidth: trackWidth,
                    lower: lower, upper: ceiling, step: step
                )
                switch activeThumb {
                case .lower:
                    let lowerUpperBound = max(lower, cappedMax - minGap)
                    let snapped = BudgetSliderMath.snap(
                        min(raw, lowerUpperBound), step: step,
                        lower: lower, upper: lowerUpperBound
                    )
                    if snapped != minCents {
                        fireHaptic()
                        minCents = snapped
                    }
                case .upper:
                    let snapped = BudgetSliderMath.snap(
                        max(raw, minCents + minGap), step: step,
                        lower: minCents + minGap, upper: ceiling
                    )
                    setMax(snapped)
                case .none:
                    break
                }
            }
            .onEnded { _ in activeThumb = nil }
    }

    /// Stores the max, mapping the ceiling to the open-ended sentinel.
    private func setMax(_ snapped: Int) {
        let resolved = snapped >= ceiling ? BudgetTierConfig.unlimitedMaxCents : snapped
        if resolved != maxCents {
            fireHaptic()
            maxCents = resolved
        }
    }

    private func fireHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

#Preview {
    struct Harness: View {
        @State private var minCents = 2000
        @State private var maxCents = 5000
        var body: some View {
            VStack(spacing: 24) {
                Text("\(formatBudgetDollars(minCents)) – \(maxCents >= 20000 ? "\(formatBudgetDollars(20000))+" : formatBudgetDollars(maxCents))")
                BudgetRangeSlider(
                    minCents: $minCents, maxCents: $maxCents,
                    lower: 500, ceiling: 20000, step: 500, accent: .pink
                )
            }
            .padding(40)
        }
    }
    return Harness()
}

//
//  OnboardingDislikesView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 4 — Dislikes (5 hard avoids).
//  Full implementation in Step 3.4.
//

import SwiftUI
import LucideIcons

/// Step 4: Select 5 things the partner dislikes ("Hard Avoids").
///
/// This is a placeholder view for Step 3.1 navigation wiring.
/// Full chip-grid UI with disabled "liked" interests and validation
/// (exactly 5, no overlap with likes) will be built in Step 3.4.
struct OnboardingDislikesView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: Lucide.ban)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(.pink)

            Text("Hard Avoids")
                .font(.title2.weight(.bold))

            Text("Select 5 things they definitely don't like.\n\(viewModel.selectedDislikes.count) of 5 selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Placeholder for chip grid (Step 3.4)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 240)
                .overlay {
                    Text("Dislike chips coming in Step 3.4")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    OnboardingDislikesView()
        .environment(OnboardingViewModel())
}

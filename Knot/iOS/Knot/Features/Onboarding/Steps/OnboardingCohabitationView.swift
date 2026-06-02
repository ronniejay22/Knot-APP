//
//  OnboardingCohabitationView.swift
//  Knot
//
//  One-question screen: living situation (together / nearby / long distance).
//

import SwiftUI
import LucideIcons

struct OnboardingCohabitationView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    private struct Option: Identifiable {
        let id: String
        let title: String
        let description: String
    }

    private let options: [Option] = [
        Option(id: "living_together", title: "We live together", description: "You and your partner share a home."),
        Option(id: "separate", title: "We live separately, nearby", description: "You live in separate places nearby."),
        Option(id: "long_distance", title: "We live separately, long distance", description: "You're in a long-distance relationship."),
    ]

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(spacing: 24) {
                headerSection

                VStack(spacing: 12) {
                    ForEach(options) { option in
                        cohabitationOption(option, isSelected: viewModel.cohabitationStatus == option.id) {
                            vm.cohabitationStatus = option.id
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Do you live together?")
                .knotFont(Theme.Typography.onboardingHeader)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func cohabitationOption(
        _ option: Option,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(uiImage: isSelected ? Lucide.circleCheck : Lucide.circle)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(Theme.textPrimary)

                    Text(option.description)
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Theme.accent.opacity(0.12) : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    OnboardingCohabitationView().environment(OnboardingViewModel())
}

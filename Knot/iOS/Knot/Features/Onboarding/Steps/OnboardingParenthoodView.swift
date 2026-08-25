//
//  OnboardingParenthoodView.swift
//  Knot
//
//  One-question screen: is the partner a parent?
//
//  Gates Mother's Day and Father's Day. Before this step existed both were
//  seeded into every vault unconditionally, so a partner with no children still
//  generated three push notifications for each of them every year.
//

import SwiftUI
import LucideIcons

struct OnboardingParenthoodView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    private struct Option: Identifiable {
        let id: Bool
        let title: String
        let description: String
    }

    private let options: [Option] = [
        Option(
            id: true,
            title: "Yes",
            description: "We'll remind you about Mother's Day and Father's Day."
        ),
        Option(
            id: false,
            title: "No",
            description: "We'll skip those reminders. You can add them later."
        ),
    ]

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(spacing: 24) {
                headerSection

                VStack(spacing: 12) {
                    ForEach(options) { option in
                        parenthoodOption(
                            option,
                            isSelected: viewModel.isPartnerParent == option.id
                        ) {
                            vm.isPartnerParent = option.id
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
        OnboardingStepHeader(
            title: parenthoodTitle,
            subtitle: "This is only used to decide which holidays we remind you about."
        )
        .padding(.top, 8)
    }

    private var parenthoodTitle: String {
        let name = viewModel.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Is your partner a parent?" : "Is \(name) a parent?"
    }

    private func parenthoodOption(
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
                    .stroke(
                        isSelected ? Theme.accent.opacity(0.5) : Theme.surfaceBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    OnboardingParenthoodView().environment(OnboardingViewModel())
}

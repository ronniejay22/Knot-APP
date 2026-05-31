//
//  OnboardingPartnerNameView.swift
//  Knot
//
//  One-question screen: partner's first name.
//

import SwiftUI
import LucideIcons

struct OnboardingPartnerNameView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    @State private var hasInteracted = false
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(spacing: 24) {
                headerSection

                VStack(alignment: .leading, spacing: 6) {
                    Text("Partner's Name")
                        .knotFont(Theme.Typography.cta)

                    TextField("Their first name", text: $vm.partnerName)
                        .knotFont(Theme.Typography.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.surfaceBorder, lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { isFocused = true }
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onChange(of: viewModel.partnerName) { _, _ in
                            if !hasInteracted { hasInteracted = true }
                        }

                    if hasInteracted && viewModel.partnerName
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Name is required to continue")
                            .knotFont(Theme.Typography.label)
                            .foregroundStyle(.red.opacity(0.8))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            viewModel.validateCurrentStep()
        }
        .onChange(of: viewModel.partnerName) { _, _ in
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(uiImage: Lucide.user)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.accent)

            Text("What's your partner's name?")
                .knotFont(Theme.Typography.cardTitle)
                .multilineTextAlignment(.center)

            Text("We'll use this to personalize your experience.")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
}

#Preview("Empty") {
    OnboardingPartnerNameView()
        .environment(OnboardingViewModel())
}

#Preview("Filled") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Alex"
    return OnboardingPartnerNameView()
        .environment(vm)
}

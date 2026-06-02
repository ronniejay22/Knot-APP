//
//  OnboardingLocationView.swift
//  Knot
//
//  One-question screen: city + state for local recommendations.
//

import SwiftUI
import MapKit
import LucideIcons

struct OnboardingLocationView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    @State private var locationCompleter = LocationSearchCompleter()
    @State private var locationQuery = ""
    @State private var showLocationResults = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                locationFieldSection
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if !viewModel.locationCity.isEmpty {
                locationQuery = [viewModel.locationCity, viewModel.locationState]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
            viewModel.validateCurrentStep()
        }
        .onChange(of: viewModel.locationCity) { _, _ in
            viewModel.validateCurrentStep()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Where do you live?")
                .knotFont(Theme.Typography.onboardingHeader)
                .multilineTextAlignment(.center)

            Text("Helps us find local experiences and restaurants.")
                .knotFont(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var locationFieldSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location")
                .knotFont(Theme.Typography.cta)

            TextField("Search city, state, or zip code", text: $locationQuery)
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
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onChange(of: locationQuery) { _, newValue in
                    let resolvedText = [viewModel.locationCity, viewModel.locationState]
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                    guard newValue != resolvedText else { return }

                    viewModel.locationCity = ""
                    viewModel.locationState = ""
                    showLocationResults = true
                    locationCompleter.search(query: newValue)
                }
                .onSubmit {
                    isFocused = false
                    showLocationResults = false
                }

            if showLocationResults && !locationCompleter.results.isEmpty {
                resultsList
            }
        }
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(locationCompleter.results.prefix(5), id: \.self) { result in
                Button {
                    selectLocation(result)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .knotFont(Theme.Typography.body)
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .knotFont(Theme.Typography.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                if result != locationCompleter.results.prefix(5).last {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.surfaceBorder, lineWidth: 0.5)
        )
    }

    private func selectLocation(_ completion: MKLocalSearchCompletion) {
        showLocationResults = false
        isFocused = false

        Task {
            await locationCompleter.resolve(completion)
            viewModel.locationCity = locationCompleter.selectedCity
            viewModel.locationState = locationCompleter.selectedState

            locationQuery = [locationCompleter.selectedCity, locationCompleter.selectedState]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }
}

#Preview {
    OnboardingLocationView().environment(OnboardingViewModel())
}

//
//  OnboardingBasicInfoView.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.1: Placeholder for onboarding Step 2.
//  Step 3.2: Full implementation — Partner Basic Info form.
//

import SwiftUI
import LucideIcons

/// Step 2: Partner basic information collection.
///
/// Collects the partner's name (required), relationship tenure (years + months pickers),
/// cohabitation status (segmented control), and location (city/state text fields, optional).
///
/// The "Next" button in the container is disabled until the partner's name is non-empty.
/// Validation is driven by `.onAppear` and `.onChange(of:)` modifiers that update
/// `viewModel.canProceed` — following the pattern described in architecture note #24.
struct OnboardingBasicInfoView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    /// Whether the user has interacted with the name field.
    /// "Required" hint only shows after interaction to avoid jarring first-load UX.
    @State private var hasInteractedWithName = false

    /// Focus state for keyboard management across form fields.
    @FocusState private var focusedField: Field?

    /// Identifiers for each focusable text field.
    private enum Field: Hashable {
        case name
        case city
        case state
    }

    var body: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Header
                headerSection

                // MARK: - Form Fields
                VStack(spacing: 22) {
                    nameSection(name: $vm.partnerName)
                    tenureSection
                    cohabitationSection(status: $vm.cohabitationStatus)
                    locationSection(city: $vm.locationCity, state: $vm.locationState)
                }
                .padding(.horizontal, 24)
            }
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

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(uiImage: Lucide.user)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(.pink)

            Text("Tell us about your partner")
                .font(.title3.weight(.semibold))

            Text("We'll use this to personalize recommendations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Name Field

    private func nameSection(name: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Partner's Name")
                .font(.subheadline.weight(.medium))

            TextField("Their first name", text: name)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit {
                    focusedField = .city
                }
                .onChange(of: viewModel.partnerName) { _, _ in
                    if !hasInteractedWithName {
                        hasInteractedWithName = true
                    }
                }

            // Show "Required" only after user has interacted and field is empty
            if hasInteractedWithName && viewModel.partnerName
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Name is required to continue")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Relationship Tenure

    private var tenureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How long have you been together?")
                .font(.subheadline.weight(.medium))

            HStack(spacing: 12) {
                // Years picker
                HStack(spacing: 6) {
                    Picker("Years", selection: Binding(
                        get: { viewModel.relationshipTenureMonths / 12 },
                        set: { newYears in
                            let remainingMonths = viewModel.relationshipTenureMonths % 12
                            viewModel.relationshipTenureMonths = newYears * 12 + remainingMonths
                        }
                    )) {
                        ForEach(0..<31, id: \.self) { year in
                            Text("\(year)").tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.pink)

                    Text(viewModel.relationshipTenureMonths / 12 == 1 ? "year" : "years")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Months picker
                HStack(spacing: 6) {
                    Picker("Months", selection: Binding(
                        get: { viewModel.relationshipTenureMonths % 12 },
                        set: { newMonths in
                            let currentYears = viewModel.relationshipTenureMonths / 12
                            viewModel.relationshipTenureMonths = currentYears * 12 + newMonths
                        }
                    )) {
                        ForEach(0..<12, id: \.self) { month in
                            Text("\(month)").tag(month)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.pink)

                    Text(viewModel.relationshipTenureMonths % 12 == 1 ? "month" : "months")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer()
            }

            // Summary text
            Text(tenureSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Human-readable tenure summary (e.g., "1 year, 0 months").
    private var tenureSummary: String {
        let years = viewModel.relationshipTenureMonths / 12
        let months = viewModel.relationshipTenureMonths % 12
        let yearText = years == 1 ? "1 year" : "\(years) years"
        let monthText = months == 1 ? "1 month" : "\(months) months"
        return "\(yearText), \(monthText)"
    }

    // MARK: - Cohabitation Status

    private func cohabitationSection(status: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Living Situation")
                .font(.subheadline.weight(.medium))

            Picker("Cohabitation", selection: status) {
                Text("Living Together").tag("living_together")
                Text("Separate").tag("separate")
                Text("Long Distance").tag("long_distance")
            }
            .pickerStyle(.segmented)

            // Contextual description
            Text(cohabitationDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Description text for the currently selected cohabitation status.
    private var cohabitationDescription: String {
        switch viewModel.cohabitationStatus {
        case "living_together":
            return "You and your partner share a home."
        case "separate":
            return "You live in separate places nearby."
        case "long_distance":
            return "You're in a long-distance relationship."
        default:
            return ""
        }
    }

    // MARK: - Location

    private func locationSection(
        city: Binding<String>,
        state: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(uiImage: Lucide.mapPin)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.secondary)

                Text("Location")
                    .font(.subheadline.weight(.medium))

                Text("(optional)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("Helps us find local experiences and restaurants.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("City", text: city)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .textContentType(.addressCity)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .city)
                    .onSubmit {
                        focusedField = .state
                    }

                TextField("State", text: state)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .textContentType(.addressState)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedField, equals: .state)
                    .frame(maxWidth: 120)
                    .onSubmit {
                        focusedField = nil
                    }
            }
        }
    }
}

// MARK: - Preview

#Preview("Empty") {
    OnboardingBasicInfoView()
        .environment(OnboardingViewModel())
}

#Preview("Pre-filled") {
    let vm = OnboardingViewModel()
    vm.partnerName = "Alex"
    vm.relationshipTenureMonths = 30
    vm.cohabitationStatus = "living_together"
    vm.locationCity = "San Francisco"
    vm.locationState = "CA"
    return OnboardingBasicInfoView()
        .environment(vm)
}

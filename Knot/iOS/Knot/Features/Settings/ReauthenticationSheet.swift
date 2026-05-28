//
//  ReauthenticationSheet.swift
//  Knot
//
//  Step 15.5 (May 2026): Replaced the Apple Sign-In re-authentication gate
//  with a typed-confirmation sheet. The user now types "DELETE ACCOUNT" to
//  enable the destructive button. Works for Apple and Google users alike.
//
//  Filename is kept for Xcode project-file compatibility; the type is named
//  to reflect its new purpose.
//

import SwiftUI
import LucideIcons

/// Sheet presented during account deletion that requires the user to type
/// `DELETE ACCOUNT` (case-sensitive, exact match) to enable the submit
/// button. On submit the backend schedules the deletion for 60 days out
/// and the user is signed out locally.
struct ReauthenticationSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Called when the user submits a valid confirmation.
    /// The closure runs the backend call (`executeAccountDeletion`) and
    /// returns whether it succeeded — the sheet stays open while it runs
    /// and dismisses itself on success.
    let onConfirm: () async -> Bool

    /// Called when the user cancels.
    let onCancel: () -> Void

    @State private var typedConfirmation: String = ""
    @State private var isSubmitting: Bool = false

    private static let requiredPhrase = "DELETE ACCOUNT"

    private var isPhraseValid: Bool {
        typedConfirmation == Self.requiredPhrase
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer().frame(height: 24)

                    Image(uiImage: Lucide.shieldAlert)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.red)

                    Text("Delete Account")
                        .knotFont(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Your account will be locked and your data held for 60 days, then permanently erased. Sign in within 60 days to restore it.")
                        .knotFont(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type ")
                            .foregroundStyle(Theme.textSecondary)
                        + Text("DELETE ACCOUNT")
                            .foregroundStyle(Theme.textPrimary)
                            .fontWeight(.semibold)
                        + Text(" to confirm.")
                            .foregroundStyle(Theme.textSecondary)

                        TextField("DELETE ACCOUNT", text: $typedConfirmation)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        isPhraseValid ? Color.red : Color.black.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                            .disabled(isSubmitting)
                    }
                    .knotFont(Theme.Typography.label)
                    .padding(.horizontal, 24)

                    Spacer()

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSubmitting ? "Scheduling deletion..." : "Delete My Account")
                                .knotFont(Theme.Typography.cta)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(isPhraseValid ? Color.red : Color.red.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!isPhraseValid || isSubmitting)
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 24)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        guard !isSubmitting else { return }
                        onCancel()
                        dismiss()
                    } label: {
                        Image(uiImage: Lucide.x)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .tint(Theme.textPrimary)
                    .disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func submit() async {
        guard isPhraseValid, !isSubmitting else { return }
        isSubmitting = true
        let ok = await onConfirm()
        isSubmitting = false
        if ok {
            dismiss()
        }
    }
}

// MARK: - Previews

#Preview("Delete Account Confirmation") {
    ReauthenticationSheet(
        onConfirm: { true },
        onCancel: { print("Cancel") }
    )
}

//
//  PendingDeletionView.swift
//  Knot
//
//  Step 15.5 (May 2026): Full-screen gate shown after sign-in when the
//  user's account is still inside the 60-day deletion grace window.
//  Lets them restore the account or sign out.
//

import SwiftUI
import LucideIcons

struct PendingDeletionView: View {
    /// The timestamp at which the hard-delete will run.
    let scheduledAt: Date

    /// Called after a successful restore. Parent clears the pending-deletion flag.
    let onRestored: () -> Void

    /// Called when the user chooses to sign out instead.
    let onSignOut: () async -> Void

    @State private var isRestoring = false
    @State private var errorMessage: String?

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: scheduledAt)
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(uiImage: Lucide.shieldAlert)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.red)

                Text("Account Pending Deletion")
                    .knotFont(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Text("Your account is scheduled to be permanently deleted on \(formattedDate).")
                        .multilineTextAlignment(.center)
                    Text("Restore your account to keep your data and continue using Knot.")
                        .multilineTextAlignment(.center)
                }
                .knotFont(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 32)

                if let errorMessage {
                    Text(errorMessage)
                        .knotFont(Theme.Typography.label)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Task { await restore() }
                    } label: {
                        HStack(spacing: 8) {
                            if isRestoring {
                                ProgressView().tint(.white)
                            }
                            Text(isRestoring ? "Restoring..." : "Restore Account")
                                .knotFont(Theme.Typography.cta)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isRestoring)

                    Button {
                        Task { await onSignOut() }
                    } label: {
                        Text("Sign Out")
                            .knotFont(Theme.Typography.cta)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .disabled(isRestoring)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)
            }
        }
    }

    private func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        do {
            let service = AccountService()
            try await service.restoreAccount()
            isRestoring = false
            onRestored()
        } catch {
            isRestoring = false
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    PendingDeletionView(
        scheduledAt: Date().addingTimeInterval(60 * 24 * 60 * 60),
        onRestored: {},
        onSignOut: {}
    )
}

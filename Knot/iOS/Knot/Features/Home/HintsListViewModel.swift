//
//  HintsListViewModel.swift
//  Knot
//
//  Created on February 9, 2026.
//  Step 4.5: Hint List View ViewModel — manages loading and deleting hints.
//

import Foundation

/// State container for the full hints list screen.
///
/// Loads all hints from the backend via `HintService` and manages deletion.
/// Step 4.6 will add the actual DELETE API call.
@MainActor
@Observable
final class HintsListViewModel {

    // MARK: - State

    /// Loading state
    var isLoading = false

    /// All hints loaded from the backend
    var hints: [HintItem] = []

    /// Error message to display
    var errorMessage: String?

    /// Deletion state
    var isDeletingHintId: String?

    // MARK: - Dependencies

    private let hintService: HintService

    init(hintService: HintService = HintService()) {
        self.hintService = hintService
    }

    // MARK: - Data Loading

    /// Loads all hints from the backend.
    func loadHints() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await hintService.listHints(limit: 100, offset: 0)

            // Map to local model
            hints = response.hints.map { item in
                HintItem(
                    id: item.id,
                    text: item.hintText,
                    source: item.source,
                    isUsed: item.isUsed,
                    createdAt: parseISO8601(item.createdAt) ?? Date()
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Deletion (Step 4.6)

    /// Deletes a hint via `DELETE /api/v1/hints/{id}` and removes it from local state.
    func deleteHint(id: String) async {
        isDeletingHintId = id

        do {
            try await hintService.deleteHint(id: id)
            hints.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }

        isDeletingHintId = nil
    }

    // MARK: - Helpers

    /// Parses an ISO 8601 date string from the backend.
    private func parseISO8601(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()

        // Try with fractional seconds first
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }

        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}

// MARK: - Supporting Models

/// Local representation of a hint for display in the list.
struct HintItem: Identifiable, Sendable {
    let id: String
    let text: String
    let source: String
    let isUsed: Bool
    let createdAt: Date
}

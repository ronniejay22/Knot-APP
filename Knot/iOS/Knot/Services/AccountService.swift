//
//  AccountService.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.2: Account Deletion — calls DELETE /api/v1/users/me.
//

import Foundation
import Supabase

// MARK: - Account Service Errors

/// Errors that can occur during account deletion API operations.
enum AccountServiceError: LocalizedError, Sendable {
    case noAuthSession
    case networkError(String)
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAuthSession:
            return "Not authenticated. Please sign in again."
        case .networkError(let message):
            return "Unable to connect to the server. \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}

// MARK: - Account Service

/// Service for account management API operations.
///
/// Communicates with the FastAPI backend to delete the user's account.
/// Uses the Supabase access token for Bearer authentication.
///
/// Follows the same pattern as `DeviceTokenService` and `HintService`:
/// authenticated HTTP calls via `URLSession` with error mapping.
@MainActor
final class AccountService: Sendable {

    private let baseURL: String
    private let session: URLSession

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    init(baseURL: String = Constants.API.baseURL) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    // MARK: - Delete Account

    /// Calls DELETE /api/v1/users/me to permanently delete the user's account.
    ///
    /// The backend deletes the auth.users record via Supabase Admin API,
    /// which cascades through all public tables (users, partner_vaults,
    /// hints, recommendations, notification_queue, etc.).
    ///
    /// - Throws: `AccountServiceError` if the request fails.
    func deleteAccount() async throws {
        let accessToken = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/users/me") else {
            throw AccountServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw AccountServiceError.networkError(mapURLError(urlError))
        } catch {
            throw AccountServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            return

        case 401:
            throw AccountServiceError.noAuthSession

        default:
            let message = parseErrorMessage(from: data)
            throw AccountServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Private Helpers

    private func getAccessToken() async throws -> String {
        do {
            let session = try await SupabaseManager.client.auth.session
            return session.accessToken
        } catch {
            throw AccountServiceError.noAuthSession
        }
    }

    private func mapURLError(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "No internet connection."
        case .timedOut:
            return "The request timed out."
        case .cannotConnectToHost, .cannotFindHost:
            return "Unable to reach the server."
        default:
            return error.localizedDescription
        }
    }

    private func parseErrorMessage(from data: Data) -> String {
        struct StringErrorResponse: Codable { let detail: String }
        if let error = try? decoder.decode(StringErrorResponse.self, from: data) {
            return error.detail
        }
        return "An unexpected error occurred."
    }
}

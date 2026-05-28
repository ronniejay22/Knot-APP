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

// MARK: - Account Status

/// Result of `AccountService.fetchAccountStatus()`. Surfaced by the
/// `AuthViewModel` after sign-in so the root navigator can present
/// `PendingDeletionView` when the account is in the 60-day grace window.
enum AccountStatus: Sendable, Equatable {
    case active
    case pendingDeletion(scheduledAt: Date)
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

    // MARK: - Restore Account (Step 15.5)

    /// Calls POST /api/v1/users/me/restore to cancel a pending deletion.
    ///
    /// Backend is idempotent: succeeds whether the account is currently
    /// pending or already active.
    func restoreAccount() async throws {
        let accessToken = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/users/me/restore") else {
            throw AccountServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
            throw AccountServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: parseErrorMessage(from: data)
            )
        }
    }

    // MARK: - Fetch Account Status (Step 15.5)

    /// Calls GET /api/v1/users/me to detect whether the account is pending deletion.
    ///
    /// Used by `AuthViewModel` right after sign-in. The endpoint stays on
    /// `get_current_user_id` so a pending user gets a 200 with the scheduled
    /// timestamp — every other authenticated endpoint returns 410 for them.
    func fetchAccountStatus() async throws -> AccountStatus {
        let accessToken = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/users/me") else {
            throw AccountServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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
            struct StatusDTO: Decodable {
                let user_id: String
                let scheduled_deletion_at: String?
            }
            let dto = try decoder.decode(StatusDTO.self, from: data)
            if let iso = dto.scheduled_deletion_at,
               let date = Self.parseISODate(iso) {
                return .pendingDeletion(scheduledAt: date)
            }
            return .active

        case 401:
            throw AccountServiceError.noAuthSession

        default:
            throw AccountServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: parseErrorMessage(from: data)
            )
        }
    }

    /// Parses an ISO 8601 timestamp produced by Python's `datetime.isoformat()`,
    /// which may or may not include fractional seconds (microseconds).
    static func parseISODate(_ s: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: s) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: s)
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

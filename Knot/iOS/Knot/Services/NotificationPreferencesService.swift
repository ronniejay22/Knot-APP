//
//  NotificationPreferencesService.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.4: Notification Preferences — calls GET/PUT /api/v1/users/me/notification-preferences.
//

import Foundation
import Supabase

// MARK: - Service Errors

/// Errors that can occur during notification preferences API operations.
enum NotificationPreferencesServiceError: LocalizedError, Sendable {
    case noAuthSession
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .noAuthSession:
            return "Not authenticated. Please sign in again."
        case .networkError(let message):
            return "Unable to connect to the server. \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let message):
            return "Failed to read server response. \(message)"
        }
    }
}

// MARK: - Service

/// Service for managing notification preferences via the backend API.
///
/// Communicates with FastAPI backend to retrieve and update the user's
/// notification settings (global toggle, quiet hours, timezone).
///
/// Follows the same pattern as `ExportService` and `AccountService`:
/// authenticated HTTP calls via `URLSession` with typed error mapping.
@MainActor
final class NotificationPreferencesService: Sendable {

    private let baseURL: String
    private let session: URLSession

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    init(baseURL: String = Constants.API.baseURL) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    // MARK: - Fetch Preferences

    /// Retrieves the user's current notification preferences from the backend.
    ///
    /// - Returns: The current notification preferences.
    /// - Throws: `NotificationPreferencesServiceError` if the request fails.
    func fetchPreferences() async throws -> NotificationPreferencesDTO {
        let accessToken = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/users/me/notification-preferences") else {
            throw NotificationPreferencesServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw NotificationPreferencesServiceError.networkError(mapURLError(urlError))
        } catch {
            throw NotificationPreferencesServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotificationPreferencesServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try decoder.decode(NotificationPreferencesDTO.self, from: data)
            } catch {
                throw NotificationPreferencesServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw NotificationPreferencesServiceError.noAuthSession

        default:
            let message = parseErrorMessage(from: data)
            throw NotificationPreferencesServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Update Preferences

    /// Updates the user's notification preferences on the backend.
    ///
    /// Only provided fields are updated — omitted fields remain unchanged.
    ///
    /// - Parameter update: The fields to update.
    /// - Returns: The updated notification preferences.
    /// - Throws: `NotificationPreferencesServiceError` if the request fails.
    func updatePreferences(_ update: NotificationPreferencesUpdateDTO) async throws -> NotificationPreferencesDTO {
        let accessToken = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/users/me/notification-preferences") else {
            throw NotificationPreferencesServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        do {
            request.httpBody = try encoder.encode(update)
        } catch {
            throw NotificationPreferencesServiceError.networkError("Failed to encode request.")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw NotificationPreferencesServiceError.networkError(mapURLError(urlError))
        } catch {
            throw NotificationPreferencesServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotificationPreferencesServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try decoder.decode(NotificationPreferencesDTO.self, from: data)
            } catch {
                throw NotificationPreferencesServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw NotificationPreferencesServiceError.noAuthSession

        default:
            let message = parseErrorMessage(from: data)
            throw NotificationPreferencesServiceError.serverError(
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
            throw NotificationPreferencesServiceError.noAuthSession
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

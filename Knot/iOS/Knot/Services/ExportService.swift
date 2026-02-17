//
//  ExportService.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.3: Data Export — calls GET /api/v1/users/me/export.
//

import Foundation
import Supabase

// MARK: - Export Service Errors

/// Errors that can occur during data export API operations.
enum ExportServiceError: LocalizedError, Sendable {
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

// MARK: - Export Service

/// Service for exporting all user data as JSON.
///
/// Communicates with the FastAPI backend to retrieve a complete export
/// of the user's data (vault, hints, recommendations, feedback, notifications).
/// Returns the raw JSON `Data` for saving or sharing as a file.
///
/// Follows the same pattern as `AccountService` and `DeviceTokenService`:
/// authenticated HTTP calls via `URLSession` with error mapping.
@MainActor
final class ExportService: Sendable {

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

    // MARK: - Export Data

    /// Calls GET /api/v1/users/me/export to retrieve all user data as JSON.
    ///
    /// Returns the raw response `Data` (not decoded into a model) so it can
    /// be saved directly as a `.json` file and shared via `UIActivityViewController`.
    ///
    /// - Returns: Raw JSON data of the complete user export.
    /// - Throws: `ExportServiceError` if the request fails.
    func exportData() async throws -> Data {
        let accessToken = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/users/me/export") else {
            throw ExportServiceError.networkError("Invalid server URL.")
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
            throw ExportServiceError.networkError(mapURLError(urlError))
        } catch {
            throw ExportServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExportServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            return data

        case 401:
            throw ExportServiceError.noAuthSession

        default:
            let message = parseErrorMessage(from: data)
            throw ExportServiceError.serverError(
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
            throw ExportServiceError.noAuthSession
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

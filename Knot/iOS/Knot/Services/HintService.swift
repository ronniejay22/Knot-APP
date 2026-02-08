//
//  HintService.swift
//  Knot
//
//  Created on February 8, 2026.
//  Step 4.2: Text Hint Capture — create and list hints via backend API.
//

import Foundation
import Supabase

// MARK: - Hint Service Errors

/// Errors that can occur during hint API operations.
enum HintServiceError: LocalizedError, Sendable {
    case noAuthSession
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case decodingError(String)
    case validationError(String)
    case noVault

    var errorDescription: String? {
        switch self {
        case .noAuthSession:
            return "Not authenticated. Please sign in again."
        case .networkError(let message):
            return "Unable to connect to the server. \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let message):
            return "Unable to process the server response. \(message)"
        case .validationError(let message):
            return message
        case .noVault:
            return "No partner vault found. Complete onboarding first."
        }
    }
}

// MARK: - Hint Service

/// Service for Hint Capture API operations.
///
/// Communicates with the FastAPI backend to create and list hints.
/// Uses the Supabase access token for Bearer authentication with the backend.
@MainActor
final class HintService: Sendable {

    /// The base URL for the backend API.
    private let baseURL: String

    /// Shared URL session for API requests.
    private let session: URLSession

    /// JSON encoder for request payloads.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    /// JSON decoder for response payloads.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    init(baseURL: String = Constants.API.baseURL) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    // MARK: - Create Hint

    /// Submits a new hint to the backend.
    ///
    /// Sends a `POST /api/v1/hints` request with the hint text and source.
    /// The backend validates the text length, looks up the vault, and stores the hint.
    ///
    /// - Parameters:
    ///   - text: The hint text (max 500 characters)
    ///   - source: The source of the hint ("text_input" or "voice_transcription")
    /// - Returns: The created hint response
    /// - Throws: `HintServiceError` if the request fails
    func createHint(text: String, source: String = "text_input") async throws -> HintCreateResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/hints") else {
            throw HintServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let payload = HintCreatePayload(hintText: text, source: source)

        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw HintServiceError.decodingError("Failed to encode request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw HintServiceError.networkError(mapURLError(urlError))
        } catch {
            throw HintServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HintServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 201:
            do {
                return try decoder.decode(HintCreateResponse.self, from: data)
            } catch {
                throw HintServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw HintServiceError.noAuthSession

        case 404:
            throw HintServiceError.noVault

        case 422:
            let message = parseErrorMessage(from: data)
            throw HintServiceError.validationError(message)

        default:
            let message = parseErrorMessage(from: data)
            throw HintServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - List Hints

    /// Fetches recent hints from the backend.
    ///
    /// Sends a `GET /api/v1/hints` request with limit and offset parameters.
    /// Returns hints in reverse chronological order (newest first).
    ///
    /// - Parameters:
    ///   - limit: Maximum number of hints to return (default 50)
    ///   - offset: Number of hints to skip (default 0)
    /// - Returns: The hint list response with total count
    /// - Throws: `HintServiceError` if the request fails
    func listHints(limit: Int = 50, offset: Int = 0) async throws -> HintListResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/hints?limit=\(limit)&offset=\(offset)") else {
            throw HintServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw HintServiceError.networkError(mapURLError(urlError))
        } catch {
            throw HintServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HintServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try decoder.decode(HintListResponse.self, from: data)
            } catch {
                throw HintServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw HintServiceError.noAuthSession

        case 404:
            throw HintServiceError.noVault

        default:
            let message = parseErrorMessage(from: data)
            throw HintServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Private Helpers

    /// Gets the current Supabase access token from the stored session.
    private func getAccessToken() async throws -> String {
        do {
            let session = try await SupabaseManager.client.auth.session
            return session.accessToken
        } catch {
            throw HintServiceError.noAuthSession
        }
    }

    /// Maps URLError codes to human-readable messages.
    private func mapURLError(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "No internet connection. Please check your connection and try again."
        case .timedOut:
            return "The request timed out. Please try again."
        case .cannotConnectToHost, .cannotFindHost:
            return "Unable to reach the server. Please try again later."
        default:
            return error.localizedDescription
        }
    }

    /// Parses an error message from the backend response body.
    private func parseErrorMessage(from data: Data) -> String {
        // Try string detail first (404, 500 errors)
        struct StringErrorResponse: Codable { let detail: String }
        if let error = try? decoder.decode(StringErrorResponse.self, from: data) {
            return error.detail
        }

        // Try array detail (422 validation errors from Pydantic)
        struct ValidationDetail: Codable { let msg: String }
        struct ArrayErrorResponse: Codable { let detail: [ValidationDetail] }
        if let error = try? decoder.decode(ArrayErrorResponse.self, from: data) {
            return error.detail.map(\.msg).joined(separator: "\n")
        }

        return "An unexpected error occurred."
    }
}

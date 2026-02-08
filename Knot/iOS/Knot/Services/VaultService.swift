//
//  VaultService.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.11: Connect iOS Onboarding to Backend API.
//

import Foundation
import Supabase

// MARK: - Vault Service Errors

/// Errors that can occur during vault API operations.
enum VaultServiceError: LocalizedError, Sendable {
    case noAuthSession
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case decodingError(String)
    case vaultAlreadyExists
    case validationError(String)

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
        case .vaultAlreadyExists:
            return "A partner vault already exists for this account."
        case .validationError(let message):
            return message
        }
    }
}

// MARK: - Vault Service

/// Service for Partner Vault API operations.
///
/// Communicates with the FastAPI backend to create vault data.
/// Uses the Supabase access token for Bearer authentication with the backend.
/// Also queries Supabase PostgREST directly to check vault existence (RLS-scoped).
@MainActor
final class VaultService: Sendable {

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

    // MARK: - Create Vault

    /// Submits the complete Partner Vault to the backend.
    ///
    /// Sends a `POST /api/v1/vault` request with the full onboarding payload.
    /// The backend validates all data, inserts into 6 database tables, and
    /// returns a summary response.
    ///
    /// - Parameter payload: The vault creation payload built from onboarding data
    /// - Returns: The created vault response with summary counts
    /// - Throws: `VaultServiceError` if the request fails
    func createVault(_ payload: VaultCreatePayload) async throws -> VaultCreateResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/vault") else {
            throw VaultServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw VaultServiceError.decodingError("Failed to encode request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw VaultServiceError.networkError("No internet connection. Please check your connection and try again.")
            case .timedOut:
                throw VaultServiceError.networkError("The request timed out. Please try again.")
            case .cannotConnectToHost, .cannotFindHost:
                throw VaultServiceError.networkError("Unable to reach the server. Please try again later.")
            default:
                throw VaultServiceError.networkError(urlError.localizedDescription)
            }
        } catch {
            throw VaultServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 201:
            do {
                return try decoder.decode(VaultCreateResponse.self, from: data)
            } catch {
                throw VaultServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw VaultServiceError.noAuthSession

        case 409:
            throw VaultServiceError.vaultAlreadyExists

        case 422:
            let message = parseErrorMessage(from: data)
            throw VaultServiceError.validationError(message)

        default:
            let message = parseErrorMessage(from: data)
            throw VaultServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Check Vault Exists

    /// Checks if the authenticated user already has a Partner Vault.
    ///
    /// Queries Supabase PostgREST directly using the anon client.
    /// Row Level Security (RLS) ensures only the current user's vault is returned.
    ///
    /// - Returns: `true` if a vault exists for the current user, `false` otherwise.
    func vaultExists() async -> Bool {
        do {
            let response = try await SupabaseManager.client
                .from("partner_vaults")
                .select("id")
                .limit(1)
                .execute()

            // Parse the JSON array — if non-empty, the user has a vault
            if let results = try? JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] {
                return !results.isEmpty
            }
            return false
        } catch {
            // If the query fails, assume no vault (safe default — user sees onboarding,
            // and submitting will return 409 if a vault actually exists)
            print("[Knot] Vault existence check failed: \(error)")
            return false
        }
    }

    // MARK: - Private Helpers

    /// Gets the current Supabase access token from the stored session.
    private func getAccessToken() async throws -> String {
        do {
            let session = try await SupabaseManager.client.auth.session
            return session.accessToken
        } catch {
            throw VaultServiceError.noAuthSession
        }
    }

    /// Parses an error message from the backend response body.
    ///
    /// Handles two FastAPI error formats:
    /// - String detail: `{"detail": "Error message"}` (409, 500 errors)
    /// - Array detail: `{"detail": [{"msg": "..."}]}` (422 validation errors)
    private func parseErrorMessage(from data: Data) -> String {
        // Try string detail first (409, 500 errors)
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

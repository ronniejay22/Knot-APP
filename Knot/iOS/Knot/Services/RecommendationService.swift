//
//  RecommendationService.swift
//  Knot
//
//  Created on February 10, 2026.
//  Step 6.2: Service for generating and refreshing AI recommendations via backend API.
//

import Foundation
import Supabase

// MARK: - Recommendation Service Errors

/// Errors that can occur during recommendation API operations.
enum RecommendationServiceError: LocalizedError, Sendable {
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

// MARK: - Recommendation Service

/// Service for Recommendation API operations.
///
/// Communicates with the FastAPI backend to generate and refresh
/// Choice-of-Three recommendations. Uses the Supabase access token
/// for Bearer authentication.
@MainActor
final class RecommendationService: Sendable {

    private let baseURL: String
    private let session: URLSession

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    init(baseURL: String = Constants.API.baseURL) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    // MARK: - Generate Recommendations

    /// Generates a fresh set of Choice-of-Three recommendations.
    ///
    /// Sends `POST /api/v1/recommendations/generate` with the occasion type
    /// and optional milestone ID. The backend runs the full LangGraph pipeline
    /// and returns exactly 3 recommendations (or fewer if insufficient candidates).
    ///
    /// - Parameters:
    ///   - occasionType: One of "just_because", "minor_occasion", "major_milestone"
    ///   - milestoneId: Optional milestone ID to generate targeted recommendations
    /// - Returns: The generate response with up to 3 recommendations
    /// - Throws: `RecommendationServiceError` if the request fails
    func generateRecommendations(
        occasionType: String,
        milestoneId: String? = nil
    ) async throws -> RecommendationGenerateResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/recommendations/generate") else {
            throw RecommendationServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60 // AI pipeline may take longer

        let payload = RecommendationGeneratePayload(
            milestoneId: milestoneId,
            occasionType: occasionType
        )

        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw RecommendationServiceError.decodingError(
                "Failed to encode request: \(error.localizedDescription)"
            )
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw RecommendationServiceError.networkError(mapURLError(urlError))
        } catch {
            throw RecommendationServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecommendationServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try decoder.decode(RecommendationGenerateResponse.self, from: data)
            } catch {
                throw RecommendationServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw RecommendationServiceError.noAuthSession

        case 404:
            throw RecommendationServiceError.noVault

        case 422:
            let message = parseErrorMessage(from: data)
            throw RecommendationServiceError.validationError(message)

        default:
            let message = parseErrorMessage(from: data)
            throw RecommendationServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Refresh Recommendations

    /// Refreshes recommendations by excluding rejected ones with a reason.
    ///
    /// Sends `POST /api/v1/recommendations/refresh` with the IDs of rejected
    /// recommendations and a reason that determines exclusion filters:
    /// - "too_expensive": excludes candidates at or above rejected price tier
    /// - "too_cheap": excludes candidates at or below rejected price tier
    /// - "not_their_style": excludes matching vibe categories
    /// - "already_have_similar": excludes same merchant + type combos
    /// - "show_different": excludes only exact same items
    ///
    /// - Parameters:
    ///   - rejectedIds: IDs of the current recommendations being rejected
    ///   - reason: The rejection reason for exclusion filtering
    /// - Returns: The refresh response with up to 3 new recommendations
    /// - Throws: `RecommendationServiceError` if the request fails
    func refreshRecommendations(
        rejectedIds: [String],
        reason: String
    ) async throws -> RecommendationRefreshResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/recommendations/refresh") else {
            throw RecommendationServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let payload = RecommendationRefreshPayload(
            rejectedRecommendationIds: rejectedIds,
            rejectionReason: reason
        )

        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw RecommendationServiceError.decodingError(
                "Failed to encode request: \(error.localizedDescription)"
            )
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw RecommendationServiceError.networkError(mapURLError(urlError))
        } catch {
            throw RecommendationServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecommendationServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try decoder.decode(RecommendationRefreshResponse.self, from: data)
            } catch {
                throw RecommendationServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw RecommendationServiceError.noAuthSession

        case 404:
            throw RecommendationServiceError.noVault

        case 422:
            let message = parseErrorMessage(from: data)
            throw RecommendationServiceError.validationError(message)

        default:
            let message = parseErrorMessage(from: data)
            throw RecommendationServiceError.serverError(
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
            throw RecommendationServiceError.noAuthSession
        }
    }

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

    private func parseErrorMessage(from data: Data) -> String {
        struct StringErrorResponse: Codable { let detail: String }
        if let error = try? decoder.decode(StringErrorResponse.self, from: data) {
            return error.detail
        }

        struct ValidationDetail: Codable { let msg: String }
        struct ArrayErrorResponse: Codable { let detail: [ValidationDetail] }
        if let error = try? decoder.decode(ArrayErrorResponse.self, from: data) {
            return error.detail.map(\.msg).joined(separator: "\n")
        }

        return "An unexpected error occurred."
    }
}

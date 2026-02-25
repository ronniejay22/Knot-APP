//
//  RecommendationService.swift
//  Knot
//
//  Created on February 10, 2026.
//  Step 6.2: Service for generating and refreshing AI recommendations via backend API.
//  Step 6.5: Added vibeOverride parameter to refreshRecommendations for manual vibe override.
//  Step 14.7: Added Knot Originals idea methods (generateIdeas, fetchIdeas, fetchIdea).
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
    case notFound

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
        case .notFound:
            return "Recommendation not found."
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
    ///   - vibeOverride: Optional vibe tags to use instead of vault vibes (session-only override)
    /// - Returns: The refresh response with up to 3 new recommendations
    /// - Throws: `RecommendationServiceError` if the request fails
    func refreshRecommendations(
        rejectedIds: [String],
        reason: String,
        vibeOverride: [String]? = nil
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
            rejectionReason: reason,
            vibeOverride: vibeOverride
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

    // MARK: - Record Feedback

    /// Records user feedback on a recommendation.
    ///
    /// Sends `POST /api/v1/recommendations/feedback` with the recommendation ID
    /// and the action taken (e.g., "selected", "purchased"). Used when the user confirms
    /// a card selection, completes a purchase, or rates a recommendation.
    ///
    /// - Parameters:
    ///   - recommendationId: The ID of the recommendation being acted on
    ///   - action: The feedback action ("selected", "saved", "shared", "rated", "handoff", "purchased")
    ///   - rating: Optional 1-5 star rating (used with "rated" action)
    ///   - feedbackText: Optional text feedback (used with "rated" action)
    /// - Returns: The feedback response with the stored record ID
    /// - Throws: `RecommendationServiceError` if the request fails
    @discardableResult
    func recordFeedback(
        recommendationId: String,
        action: String,
        rating: Int? = nil,
        feedbackText: String? = nil
    ) async throws -> RecommendationFeedbackResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/recommendations/feedback") else {
            throw RecommendationServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let payload = RecommendationFeedbackPayload(
            recommendationId: recommendationId,
            action: action,
            rating: rating,
            feedbackText: feedbackText
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
        case 201:
            do {
                return try decoder.decode(RecommendationFeedbackResponse.self, from: data)
            } catch {
                throw RecommendationServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw RecommendationServiceError.noAuthSession

        case 404:
            let message = parseErrorMessage(from: data)
            throw RecommendationServiceError.validationError(message)

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

    // MARK: - Fetch Single Recommendation (Step 9.2)

    /// Fetches a single recommendation by its database ID.
    ///
    /// Sends `GET /api/v1/recommendations/{recommendationId}`.
    /// Used by the deep link handler to load a shared recommendation.
    ///
    /// - Parameter recommendationId: The UUID of the recommendation to fetch
    /// - Returns: The recommendation details
    /// - Throws: `RecommendationServiceError` if the request fails
    func fetchRecommendation(
        id recommendationId: String
    ) async throws -> MilestoneRecommendationItemResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/recommendations/\(recommendationId)") else {
            throw RecommendationServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

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
                return try decoder.decode(MilestoneRecommendationItemResponse.self, from: data)
            } catch {
                throw RecommendationServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw RecommendationServiceError.noAuthSession

        case 404:
            throw RecommendationServiceError.notFound

        default:
            let message = parseErrorMessage(from: data)
            throw RecommendationServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Generate Ideas (Step 14.7)

    /// Generates personalized Knot Original ideas using Claude.
    ///
    /// Sends `POST /api/v1/ideas/generate` with count, occasion type,
    /// and optional category filter. The backend generates rich, structured
    /// idea content using the partner's vault data and captured hints.
    ///
    /// - Parameters:
    ///   - count: Number of ideas to generate (1-10, default 3)
    ///   - occasionType: Budget tier context
    ///   - category: Optional category filter (e.g., "activity", "gesture")
    /// - Returns: The generate response with ideas and content sections
    /// - Throws: `RecommendationServiceError` if the request fails
    func generateIdeas(
        count: Int = 3,
        occasionType: String = "just_because",
        category: String? = nil
    ) async throws -> IdeaGenerateResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/ideas/generate") else {
            throw RecommendationServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let payload = IdeaGeneratePayload(
            count: count,
            occasionType: occasionType,
            category: category
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
                return try decoder.decode(IdeaGenerateResponse.self, from: data)
            } catch {
                throw RecommendationServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw RecommendationServiceError.noAuthSession

        case 404:
            throw RecommendationServiceError.noVault

        default:
            let message = parseErrorMessage(from: data)
            throw RecommendationServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Fetch Ideas (Step 14.7)

    /// Fetches the user's Knot Original ideas (paginated).
    ///
    /// Sends `GET /api/v1/ideas?limit=N&offset=M`.
    /// Returns ideas ordered by most recent first.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of ideas to return (default 20)
    ///   - offset: Number of ideas to skip for pagination (default 0)
    /// - Returns: Paginated list of ideas with total count
    /// - Throws: `RecommendationServiceError` if the request fails
    func fetchIdeas(
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> IdeaListResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/ideas/?limit=\(limit)&offset=\(offset)") else {
            throw RecommendationServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

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
                return try decoder.decode(IdeaListResponse.self, from: data)
            } catch {
                throw RecommendationServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw RecommendationServiceError.noAuthSession

        case 404:
            throw RecommendationServiceError.noVault

        default:
            let message = parseErrorMessage(from: data)
            throw RecommendationServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Fetch Single Idea (Step 14.7)

    /// Fetches a single Knot Original idea by its database ID.
    ///
    /// Sends `GET /api/v1/ideas/{ideaId}`.
    ///
    /// - Parameter ideaId: The UUID of the idea to fetch
    /// - Returns: The idea with full content sections
    /// - Throws: `RecommendationServiceError` if the request fails
    func fetchIdea(id ideaId: String) async throws -> IdeaItemResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/ideas/\(ideaId)") else {
            throw RecommendationServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

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
                return try decoder.decode(IdeaItemResponse.self, from: data)
            } catch {
                throw RecommendationServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw RecommendationServiceError.noAuthSession

        case 404:
            throw RecommendationServiceError.notFound

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

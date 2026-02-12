//
//  NotificationHistoryService.swift
//  Knot
//
//  Created on February 12, 2026.
//  Step 7.7: Service for fetching notification history and milestone recommendations.
//

import Foundation
import Supabase

// MARK: - Notification History Service Errors

/// Errors that can occur during notification history API operations.
enum NotificationHistoryServiceError: LocalizedError, Sendable {
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
            return "Unable to process the server response. \(message)"
        }
    }
}

// MARK: - Notification History Service

/// Service for Notification History API operations.
///
/// Communicates with the FastAPI backend to fetch notification history,
/// milestone-specific recommendations, and mark notifications as viewed.
/// Uses the Supabase access token for Bearer authentication.
@MainActor
final class NotificationHistoryService: Sendable {

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

    // MARK: - Fetch Notification History

    /// Fetches the user's notification history.
    ///
    /// Sends `GET /api/v1/notifications/history` with optional pagination.
    /// Returns sent/failed notifications with milestone metadata and recommendation counts.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of notifications to return (default 50)
    ///   - offset: Pagination offset (default 0)
    /// - Returns: The notification history response
    /// - Throws: `NotificationHistoryServiceError` if the request fails
    func fetchHistory(
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> NotificationHistoryResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/notifications/history?limit=\(limit)&offset=\(offset)") else {
            throw NotificationHistoryServiceError.networkError("Invalid server URL.")
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
            throw NotificationHistoryServiceError.networkError(mapURLError(urlError))
        } catch {
            throw NotificationHistoryServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotificationHistoryServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try decoder.decode(NotificationHistoryResponse.self, from: data)
            } catch {
                throw NotificationHistoryServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw NotificationHistoryServiceError.noAuthSession

        default:
            let message = parseErrorMessage(from: data)
            throw NotificationHistoryServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Fetch Milestone Recommendations

    /// Fetches pre-generated recommendations for a specific milestone.
    ///
    /// Sends `GET /api/v1/recommendations/by-milestone/{milestoneId}`.
    /// Returns recommendations that were generated when the notification fired.
    ///
    /// - Parameter milestoneId: The UUID of the milestone
    /// - Returns: The milestone recommendations response
    /// - Throws: `NotificationHistoryServiceError` if the request fails
    func fetchMilestoneRecommendations(
        milestoneId: String
    ) async throws -> MilestoneRecommendationsResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/recommendations/by-milestone/\(milestoneId)") else {
            throw NotificationHistoryServiceError.networkError("Invalid server URL.")
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
            throw NotificationHistoryServiceError.networkError(mapURLError(urlError))
        } catch {
            throw NotificationHistoryServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotificationHistoryServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try decoder.decode(MilestoneRecommendationsResponse.self, from: data)
            } catch {
                throw NotificationHistoryServiceError.decodingError(error.localizedDescription)
            }

        case 401:
            throw NotificationHistoryServiceError.noAuthSession

        case 404:
            throw NotificationHistoryServiceError.serverError(
                statusCode: 404,
                message: "No vault found or milestone not found."
            )

        default:
            let message = parseErrorMessage(from: data)
            throw NotificationHistoryServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    // MARK: - Mark Notification as Viewed

    /// Marks a notification as viewed by setting its viewed_at timestamp.
    ///
    /// Sends `PATCH /api/v1/notifications/{notificationId}/viewed`.
    /// This is a fire-and-forget operation — errors are logged but not thrown.
    ///
    /// - Parameter notificationId: The UUID of the notification to mark as viewed
    func markViewed(notificationId: String) async {
        do {
            let token = try await getAccessToken()

            guard let url = URL(string: "\(baseURL)/api/v1/notifications/\(notificationId)/viewed") else {
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10

            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("[Knot] Failed to mark notification \(notificationId) as viewed: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("[Knot] Failed to mark notification \(notificationId) as viewed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func getAccessToken() async throws -> String {
        do {
            let session = try await SupabaseManager.client.auth.session
            return session.accessToken
        } catch {
            throw NotificationHistoryServiceError.noAuthSession
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

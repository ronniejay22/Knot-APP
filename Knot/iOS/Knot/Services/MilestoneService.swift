//
//  MilestoneService.swift
//  Knot
//
//  Created on March 12, 2026.
//  Service for milestone CRUD operations via the backend API.
//

import Foundation

// MARK: - Milestone Service Errors

enum MilestoneServiceError: LocalizedError, Sendable {
    case noAuthSession
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case decodingError(String)
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
        case .notFound:
            return "Milestone not found."
        }
    }
}

// MARK: - Milestone Service

@MainActor
final class MilestoneService: Sendable {

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

    // MARK: - List Milestones

    func listMilestones() async throws -> MilestoneListResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/milestones") else {
            throw MilestoneServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MilestoneServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            return try decoder.decode(MilestoneListResponse.self, from: data)
        case 401:
            throw MilestoneServiceError.noAuthSession
        default:
            throw MilestoneServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: parseErrorMessage(from: data)
            )
        }
    }

    // MARK: - Create Milestone

    func createMilestone(_ payload: MilestoneCreatePayload) async throws -> MilestoneItemResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/milestones") else {
            throw MilestoneServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MilestoneServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 201:
            return try decoder.decode(MilestoneItemResponse.self, from: data)
        case 401:
            throw MilestoneServiceError.noAuthSession
        default:
            throw MilestoneServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: parseErrorMessage(from: data)
            )
        }
    }

    // MARK: - Update Milestone

    func updateMilestone(id: String, _ payload: MilestoneUpdatePayload) async throws -> MilestoneItemResponse {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/milestones/\(id)") else {
            throw MilestoneServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MilestoneServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            return try decoder.decode(MilestoneItemResponse.self, from: data)
        case 401:
            throw MilestoneServiceError.noAuthSession
        case 404:
            throw MilestoneServiceError.notFound
        default:
            throw MilestoneServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: parseErrorMessage(from: data)
            )
        }
    }

    // MARK: - Delete Milestone

    func deleteMilestone(id: String) async throws {
        let token = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/milestones/\(id)") else {
            throw MilestoneServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MilestoneServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 204:
            return
        case 401:
            throw MilestoneServiceError.noAuthSession
        case 404:
            throw MilestoneServiceError.notFound
        default:
            throw MilestoneServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: parseErrorMessage(from: data)
            )
        }
    }

    // MARK: - Helpers

    private func getAccessToken() async throws -> String {
        do {
            let session = try await SupabaseManager.client.auth.session
            return session.accessToken
        } catch {
            throw MilestoneServiceError.noAuthSession
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw MilestoneServiceError.networkError("No internet connection.")
            case .timedOut:
                throw MilestoneServiceError.networkError("The request timed out.")
            default:
                throw MilestoneServiceError.networkError(urlError.localizedDescription)
            }
        } catch {
            throw MilestoneServiceError.networkError(error.localizedDescription)
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

//
//  DeviceTokenService.swift
//  Knot
//
//  Created on February 12, 2026.
//  Step 7.4: Push Notification Registration — sends device token to backend.
//

import Foundation
import Supabase

// MARK: - Device Token Service Errors

/// Errors that can occur during device token API operations.
enum DeviceTokenServiceError: LocalizedError, Sendable {
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

// MARK: - Device Token Service

/// Service for registering APNs device tokens with the backend.
///
/// Called from `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`
/// on every app launch. Uses a singleton so the AppDelegate can access it
/// without needing environment injection (AppDelegate is created before
/// the SwiftUI view hierarchy).
@MainActor
final class DeviceTokenService: Sendable {

    /// Shared singleton instance.
    ///
    /// The AppDelegate needs to call this from the UIKit callback, which
    /// fires before the SwiftUI environment is available. A singleton
    /// avoids the need to thread the service through the view hierarchy.
    static let shared = DeviceTokenService()

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

    // MARK: - Register Token

    /// Sends the APNs device token to the backend for storage.
    ///
    /// Called on every app launch after successful APNs registration.
    /// The backend upserts the token, so repeated calls are safe.
    ///
    /// This method does not throw — push notification registration is
    /// a non-blocking, best-effort operation. Failures are logged but
    /// not surfaced to the user.
    ///
    /// - Parameter token: The hex-encoded APNs device token string.
    func registerToken(_ token: String) async {
        do {
            try await sendToken(token)
            print("[Knot] Device token registered with backend")
        } catch {
            print("[Knot] Failed to register device token: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    /// Sends the device token to POST /api/v1/users/device-token.
    private func sendToken(_ token: String) async throws {
        let accessToken = try await getAccessToken()

        guard let url = URL(string: "\(baseURL)/api/v1/users/device-token") else {
            throw DeviceTokenServiceError.networkError("Invalid server URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let payload = DeviceTokenPayload(deviceToken: token, platform: "ios")

        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw DeviceTokenServiceError.networkError("Failed to encode request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw DeviceTokenServiceError.networkError(mapURLError(urlError))
        } catch {
            throw DeviceTokenServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeviceTokenServiceError.networkError("Invalid server response.")
        }

        switch httpResponse.statusCode {
        case 200:
            return

        case 401:
            throw DeviceTokenServiceError.noAuthSession

        default:
            let message = parseErrorMessage(from: data)
            throw DeviceTokenServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    /// Gets the current Supabase access token from the stored session.
    private func getAccessToken() async throws -> String {
        do {
            let session = try await SupabaseManager.client.auth.session
            return session.accessToken
        } catch {
            throw DeviceTokenServiceError.noAuthSession
        }
    }

    /// Maps URLError codes to human-readable messages.
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

    /// Parses an error message from the backend response body.
    private func parseErrorMessage(from data: Data) -> String {
        struct StringErrorResponse: Codable { let detail: String }
        if let error = try? decoder.decode(StringErrorResponse.self, from: data) {
            return error.detail
        }
        return "An unexpected error occurred."
    }
}

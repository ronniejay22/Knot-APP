//
//  RecommendationsViewTests.swift
//  KnotTests
//
//  Created on February 10, 2026.
//  Step 6.2: Unit tests for RecommendationsView, RecommendationsViewModel, DTOs, and RecommendationService.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - DTO Decoding Tests

final class RecommendationDTOTests: XCTestCase {

    /// Verify RecommendationItemResponse decodes correctly from full JSON.
    func testRecommendationItemDecodesFullJSON() throws {
        let json = """
        {
            "id": "abc-123",
            "recommendation_type": "gift",
            "title": "Ceramic Pottery Class",
            "description": "A hands-on pottery experience.",
            "price_cents": 8500,
            "currency": "USD",
            "external_url": "https://example.com/pottery",
            "image_url": "https://example.com/image.jpg",
            "merchant_name": "Clay Studio",
            "source": "yelp",
            "location": {
                "city": "Brooklyn",
                "state": "NY",
                "country": "US",
                "address": "123 Main St"
            },
            "interest_score": 0.85,
            "vibe_score": 0.72,
            "love_language_score": 0.9,
            "final_score": 0.82
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(RecommendationItemResponse.self, from: json)

        XCTAssertEqual(item.id, "abc-123")
        XCTAssertEqual(item.recommendationType, "gift")
        XCTAssertEqual(item.title, "Ceramic Pottery Class")
        XCTAssertEqual(item.description, "A hands-on pottery experience.")
        XCTAssertEqual(item.priceCents, 8500)
        XCTAssertEqual(item.currency, "USD")
        XCTAssertEqual(item.externalUrl, "https://example.com/pottery")
        XCTAssertEqual(item.imageUrl, "https://example.com/image.jpg")
        XCTAssertEqual(item.merchantName, "Clay Studio")
        XCTAssertEqual(item.source, "yelp")
        XCTAssertEqual(item.location?.city, "Brooklyn")
        XCTAssertEqual(item.location?.state, "NY")
        XCTAssertEqual(item.interestScore, 0.85, accuracy: 0.001)
        XCTAssertEqual(item.vibeScore, 0.72, accuracy: 0.001)
        XCTAssertEqual(item.loveLanguageScore, 0.9, accuracy: 0.001)
        XCTAssertEqual(item.finalScore, 0.82, accuracy: 0.001)
    }

    /// Verify RecommendationItemResponse decodes with nil optionals.
    func testRecommendationItemDecodesMinimalJSON() throws {
        let json = """
        {
            "id": "def-456",
            "recommendation_type": "experience",
            "title": "Sunset Sailing",
            "description": null,
            "price_cents": null,
            "currency": "USD",
            "external_url": "https://example.com/sailing",
            "image_url": null,
            "merchant_name": null,
            "source": "manual",
            "location": null,
            "interest_score": 0.5,
            "vibe_score": 0.5,
            "love_language_score": 0.5,
            "final_score": 0.5
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(RecommendationItemResponse.self, from: json)

        XCTAssertEqual(item.id, "def-456")
        XCTAssertEqual(item.recommendationType, "experience")
        XCTAssertEqual(item.title, "Sunset Sailing")
        XCTAssertNil(item.description)
        XCTAssertNil(item.priceCents)
        XCTAssertNil(item.imageUrl)
        XCTAssertNil(item.merchantName)
        XCTAssertNil(item.location)
    }

    /// Verify RecommendationGenerateResponse decodes correctly.
    func testGenerateResponseDecodes() throws {
        let json = """
        {
            "recommendations": [
                {
                    "id": "r1",
                    "recommendation_type": "gift",
                    "title": "Gift 1",
                    "description": null,
                    "price_cents": 5000,
                    "currency": "USD",
                    "external_url": "https://example.com/1",
                    "image_url": null,
                    "merchant_name": null,
                    "source": "amazon",
                    "location": null,
                    "interest_score": 0.8,
                    "vibe_score": 0.7,
                    "love_language_score": 0.6,
                    "final_score": 0.7
                },
                {
                    "id": "r2",
                    "recommendation_type": "experience",
                    "title": "Experience 2",
                    "description": "Fun activity",
                    "price_cents": 12000,
                    "currency": "USD",
                    "external_url": "https://example.com/2",
                    "image_url": null,
                    "merchant_name": "Fun Co",
                    "source": "yelp",
                    "location": null,
                    "interest_score": 0.9,
                    "vibe_score": 0.8,
                    "love_language_score": 0.7,
                    "final_score": 0.8
                },
                {
                    "id": "r3",
                    "recommendation_type": "date",
                    "title": "Date 3",
                    "description": null,
                    "price_cents": null,
                    "currency": "USD",
                    "external_url": "https://example.com/3",
                    "image_url": null,
                    "merchant_name": null,
                    "source": "opentable",
                    "location": null,
                    "interest_score": 0.6,
                    "vibe_score": 0.5,
                    "love_language_score": 0.9,
                    "final_score": 0.65
                }
            ],
            "count": 3,
            "milestone_id": null,
            "occasion_type": "just_because"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RecommendationGenerateResponse.self, from: json)

        XCTAssertEqual(response.recommendations.count, 3)
        XCTAssertEqual(response.count, 3)
        XCTAssertNil(response.milestoneId)
        XCTAssertEqual(response.occasionType, "just_because")
        XCTAssertEqual(response.recommendations[0].title, "Gift 1")
        XCTAssertEqual(response.recommendations[1].title, "Experience 2")
        XCTAssertEqual(response.recommendations[2].title, "Date 3")
    }

    /// Verify RecommendationRefreshResponse decodes correctly.
    func testRefreshResponseDecodes() throws {
        let json = """
        {
            "recommendations": [
                {
                    "id": "r4",
                    "recommendation_type": "gift",
                    "title": "Refreshed Gift",
                    "description": null,
                    "price_cents": 3000,
                    "currency": "USD",
                    "external_url": "https://example.com/4",
                    "image_url": null,
                    "merchant_name": null,
                    "source": "shopify",
                    "location": null,
                    "interest_score": 0.7,
                    "vibe_score": 0.6,
                    "love_language_score": 0.8,
                    "final_score": 0.7
                }
            ],
            "count": 1,
            "rejection_reason": "too_expensive"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RecommendationRefreshResponse.self, from: json)

        XCTAssertEqual(response.recommendations.count, 1)
        XCTAssertEqual(response.count, 1)
        XCTAssertEqual(response.rejectionReason, "too_expensive")
        XCTAssertEqual(response.recommendations[0].title, "Refreshed Gift")
    }

    /// Verify RecommendationGeneratePayload encodes to correct snake_case JSON keys.
    func testGeneratePayloadEncodesCorrectly() throws {
        let payload = RecommendationGeneratePayload(
            milestoneId: "m-123",
            occasionType: "major_milestone"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["milestone_id"] as? String, "m-123")
        XCTAssertEqual(json?["occasion_type"] as? String, "major_milestone")
    }

    /// Verify RecommendationRefreshPayload encodes to correct snake_case JSON keys.
    func testRefreshPayloadEncodesCorrectly() throws {
        let payload = RecommendationRefreshPayload(
            rejectedRecommendationIds: ["r1", "r2", "r3"],
            rejectionReason: "not_their_style"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["rejected_recommendation_ids"] as? [String], ["r1", "r2", "r3"])
        XCTAssertEqual(json?["rejection_reason"] as? String, "not_their_style")
    }

    /// Verify RecommendationLocationResponse decodes all fields.
    func testLocationResponseDecodes() throws {
        let json = """
        {
            "city": "San Francisco",
            "state": "CA",
            "country": "US",
            "address": "456 Market St"
        }
        """.data(using: .utf8)!

        let location = try JSONDecoder().decode(RecommendationLocationResponse.self, from: json)

        XCTAssertEqual(location.city, "San Francisco")
        XCTAssertEqual(location.state, "CA")
        XCTAssertEqual(location.country, "US")
        XCTAssertEqual(location.address, "456 Market St")
    }

    /// Verify RecommendationItemResponse conforms to Identifiable.
    func testRecommendationItemIsIdentifiable() throws {
        let json = """
        {
            "id": "unique-id",
            "recommendation_type": "date",
            "title": "Test",
            "description": null,
            "price_cents": null,
            "currency": "USD",
            "external_url": "https://example.com",
            "image_url": null,
            "merchant_name": null,
            "source": "manual",
            "location": null,
            "interest_score": 0.0,
            "vibe_score": 0.0,
            "love_language_score": 0.0,
            "final_score": 0.0
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(RecommendationItemResponse.self, from: json)

        // Identifiable conformance uses `id` property
        XCTAssertEqual(item.id, "unique-id")
    }
}

// MARK: - ViewModel Tests

@MainActor
final class RecommendationsViewModelTests: XCTestCase {

    /// Verify ViewModel initializes with empty state.
    func testInitialState() {
        let vm = RecommendationsViewModel()

        XCTAssertTrue(vm.recommendations.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isRefreshing)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.currentPage, 0)
    }

    /// Verify currentPage can be updated.
    func testCurrentPageUpdates() {
        let vm = RecommendationsViewModel()

        vm.currentPage = 2
        XCTAssertEqual(vm.currentPage, 2)

        vm.currentPage = 0
        XCTAssertEqual(vm.currentPage, 0)
    }
}

// MARK: - View Rendering Tests

@MainActor
final class RecommendationsViewRenderingTests: XCTestCase {

    /// Verify the RecommendationsView renders without crashing.
    func testViewRenders() {
        let view = RecommendationsView()
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "RecommendationsView should render a valid view")
    }
}

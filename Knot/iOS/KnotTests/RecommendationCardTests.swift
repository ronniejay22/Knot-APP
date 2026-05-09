//
//  RecommendationCardTests.swift
//  KnotTests
//
//  Created on February 10, 2026.
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class RecommendationCardTests: XCTestCase {

    // MARK: - Rendering Tests

    /// Verify the card renders without crashing with complete data.
    func testCardRendersWithFullData() throws {
        let card = RecommendationCard(
            title: "Ceramic Pottery Class for Two",
            descriptionText: "A hands-on pottery experience with custom pieces.",
            recommendationType: "gift",
            priceCents: 8500,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: "https://example.com/image.jpg",
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: {}
        )

        let hostingController = UIHostingController(rootView: card)
        XCTAssertNotNil(hostingController.view, "Card should render a valid view")
    }

    /// Verify the card renders without crashing with minimal data (nil optionals).
    func testCardRendersWithMinimalData() throws {
        let card = RecommendationCard(
            title: "Simple Gift",
            descriptionText: nil,
            recommendationType: "gift",
            priceCents: nil,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: {}
        )

        let hostingController = UIHostingController(rootView: card)
        XCTAssertNotNil(hostingController.view, "Card should render with minimal data")
    }

    /// Verify the card renders for each recommendation type.
    func testCardRendersAllTypes() throws {
        let types = ["gift", "experience", "date"]

        for type in types {
            let card = RecommendationCard(
                title: "Test \(type)",
                descriptionText: "Test description",
                recommendationType: type,
                priceCents: 1000,
                currency: "USD",
                priceConfidence: "unknown",
                imageURL: nil,
                isSaved: false,
                matchedInterests: [],
                matchedVibes: [],
                matchedLoveLanguages: [],
                personalizationNote: nil,
                onSelect: {},
                onSave: {}
            )

            let hostingController = UIHostingController(rootView: card)
            XCTAssertNotNil(hostingController.view, "Card should render for type: \(type)")
        }
    }

    /// Verify the card handles an unknown recommendation type gracefully.
    func testCardRendersUnknownType() throws {
        let card = RecommendationCard(
            title: "Unknown Type Item",
            descriptionText: "Something new",
            recommendationType: "workshop",
            priceCents: 5000,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: {}
        )

        let hostingController = UIHostingController(rootView: card)
        XCTAssertNotNil(hostingController.view, "Card should handle unknown type gracefully")
    }

    // MARK: - Price Formatting Tests

    func testFormattedPriceWholeDollar() throws {
        let formatted = RecommendationCard.formattedPrice(cents: 5000, currency: "USD")
        XCTAssertEqual(formatted, "$50", "5000 cents should format as $50")
    }

    func testFormattedPriceWithCents() throws {
        let formatted = RecommendationCard.formattedPrice(cents: 4999, currency: "USD")
        XCTAssertEqual(formatted, "$49.99", "4999 cents should format as $49.99")
    }

    func testFormattedPriceGBP() throws {
        let formatted = RecommendationCard.formattedPrice(cents: 3500, currency: "GBP")
        XCTAssertTrue(formatted.contains("£") || formatted.contains("GBP"),
                       "GBP price should contain £ symbol, got: \(formatted)")
    }

    func testFormattedPriceZero() throws {
        let formatted = RecommendationCard.formattedPrice(cents: 0, currency: "USD")
        XCTAssertEqual(formatted, "$0", "0 cents should format as $0")
    }

    func testFormattedPriceLargeAmount() throws {
        let formatted = RecommendationCard.formattedPrice(cents: 100000, currency: "USD")
        XCTAssertTrue(formatted.contains("1") && formatted.contains("000"),
                       "100000 cents should format as $1,000 (got: \(formatted))")
    }

    // MARK: - Select Button Tests

    /// Verify the onSelect callback fires when invoked.
    func testSelectCallbackFires() throws {
        var selected = false

        let card = RecommendationCard(
            title: "Tappable Card",
            descriptionText: nil,
            recommendationType: "gift",
            priceCents: 2000,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: { selected = true },
            onSave: {}
        )

        card.onSelect()
        XCTAssertTrue(selected, "onSelect callback should fire")
    }

    // MARK: - Text Truncation Tests

    /// Verify the card handles very long titles without crashing.
    func testLongTitleTruncation() throws {
        let longTitle = String(repeating: "Long Title Word ", count: 20)

        let card = RecommendationCard(
            title: longTitle,
            descriptionText: nil,
            recommendationType: "gift",
            priceCents: 1000,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: {}
        )

        let hostingController = UIHostingController(rootView: card)
        XCTAssertNotNil(hostingController.view, "Card should handle long titles")
    }

    /// Verify the card handles very long descriptions without crashing
    /// (description is shown as fallback when personalizationNote is nil).
    func testLongDescriptionTruncation() throws {
        let longDescription = String(repeating: "This is a very detailed description. ", count: 30)

        let card = RecommendationCard(
            title: "Normal Title",
            descriptionText: longDescription,
            recommendationType: "experience",
            priceCents: 15000,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: {}
        )

        let hostingController = UIHostingController(rootView: card)
        XCTAssertNotNil(hostingController.view, "Card should handle long descriptions")
    }

    // MARK: - Save Button Tests

    /// Verify the save callback fires when invoked.
    func testSaveCallbackFires() throws {
        var saved = false

        let card = RecommendationCard(
            title: "Saveable Card",
            descriptionText: nil,
            recommendationType: "gift",
            priceCents: 2000,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: { saved = true }
        )

        card.onSave()
        XCTAssertTrue(saved, "onSave callback should fire")
    }

    /// Verify the card renders with isSaved = true (saved state).
    func testCardRendersWithSavedState() throws {
        let card = RecommendationCard(
            title: "Already Saved Card",
            descriptionText: "A gift that was saved.",
            recommendationType: "gift",
            priceCents: 5000,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: true,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: {}
        )

        let hostingController = UIHostingController(rootView: card)
        XCTAssertNotNil(hostingController.view, "Card should render in saved state")
    }

    /// Verify the card renders with isSaved = false (unsaved state).
    func testCardRendersWithUnsavedState() throws {
        let card = RecommendationCard(
            title: "Unsaved Card",
            descriptionText: nil,
            recommendationType: "experience",
            priceCents: 8000,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: false,
            matchedInterests: [],
            matchedVibes: [],
            matchedLoveLanguages: [],
            personalizationNote: nil,
            onSelect: {},
            onSave: {}
        )

        let hostingController = UIHostingController(rootView: card)
        XCTAssertNotNil(hostingController.view, "Card should render in unsaved state")
    }

    // MARK: - Match Factor Overflow Tests

    /// Verify the card renders cleanly when many match factors would overflow the 3-chip cap.
    func testCardRendersWithManyMatchFactors() throws {
        let card = RecommendationCard(
            title: "Many Matches Card",
            descriptionText: nil,
            recommendationType: "experience",
            priceCents: 12500,
            currency: "USD",
            priceConfidence: "unknown",
            imageURL: nil,
            isSaved: false,
            matchedInterests: ["Food", "Wine", "Cooking"],
            matchedVibes: ["romantic", "playful"],
            matchedLoveLanguages: ["quality_time", "acts_of_service"],
            personalizationNote: "She's mentioned wanting to learn together.",
            onSelect: {},
            onSave: {}
        )

        let hostingController = UIHostingController(rootView: card)
        XCTAssertNotNil(hostingController.view, "Card should render with overflow chip")
    }
}

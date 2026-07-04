//
//  SavedRecommendationDetailTests.swift
//  KnotTests
//
//  Tests for SavedRecommendation.toDetailItem() — the snapshot → detail-view DTO
//  converter that lets a tapped Saved card open RecommendationDetailView.
//

import XCTest
@testable import Knot

final class SavedRecommendationDetailTests: XCTestCase {

    /// A purchasable snapshot maps its core fields into the detail DTO and is not an idea.
    func testPurchasableSnapshotMapsCoreFields() {
        let saved = SavedRecommendation(
            recommendationId: "gift-1",
            recommendationType: "gift",
            title: "Ceramic Pottery Class for Two",
            descriptionText: "A thoughtful gift.",
            externalURL: "https://example.com/x",
            priceCents: 4999,
            currency: "USD",
            merchantName: "Clay Studio",
            imageURL: "https://example.com/img.jpg",
            isIdea: false
        )

        let item = saved.toDetailItem()

        XCTAssertEqual(item.id, "gift-1")
        XCTAssertEqual(item.recommendationType, "gift")
        XCTAssertEqual(item.title, "Ceramic Pottery Class for Two")
        XCTAssertEqual(item.description, "A thoughtful gift.")
        XCTAssertEqual(item.priceCents, 4999)
        XCTAssertEqual(item.currency, "USD")
        XCTAssertEqual(item.externalUrl, "https://example.com/x")
        XCTAssertEqual(item.merchantName, "Clay Studio")
        XCTAssertEqual(item.imageUrl, "https://example.com/img.jpg")
        XCTAssertEqual(item.isIdea, false)
        XCTAssertNil(item.contentSections)
    }

    /// A Knot Original snapshot round-trips its stored content sections back into the DTO.
    func testIdeaSnapshotRestoresContentSections() throws {
        let sectionsJSON = """
        [
            {"type": "overview", "heading": "The Idea", "body": "A cozy night in.", "items": null},
            {"type": "steps", "heading": "How", "body": null, "items": ["Cook dinner", "Watch a film"]}
        ]
        """.data(using: .utf8)!

        let saved = SavedRecommendation(
            recommendationId: "idea-1",
            recommendationType: "idea",
            title: "Cozy Night In",
            currency: "USD",
            isIdea: true,
            contentSectionsData: sectionsJSON
        )

        let item = saved.toDetailItem()

        XCTAssertEqual(item.isIdea, true)
        let sections = try XCTUnwrap(item.contentSections)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.first?.heading, "The Idea")
        XCTAssertEqual(sections.first?.body, "A cozy night in.")
        XCTAssertEqual(sections.last?.items, ["Cook dinner", "Watch a film"])
    }

    /// A snapshot with no stored content sections yields nil sections (no crash).
    func testSnapshotWithoutContentSectionsYieldsNil() {
        let saved = SavedRecommendation(
            recommendationId: "date-1",
            recommendationType: "date",
            title: "Sunset Walk",
            contentSectionsData: nil
        )

        let item = saved.toDetailItem()

        XCTAssertNil(item.contentSections)
    }
}

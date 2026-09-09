//
//  RecommendationDetailLayoutTests.swift
//  KnotTests
//
//  Created on September 8, 2026.
//  Pins the pure copy rules behind the recommendation detail page's
//  "experience" layout (Step 19.47): the shared type display, the category
//  pill, the meta line, and the contextual stats strip.
//

import XCTest
@testable import Knot

// MARK: - Shared type display

final class RecommendationTypeDisplayTests: XCTestCase {

    func testLabelsForKnownTypes() {
        XCTAssertEqual(RecommendationTypeDisplay.label(for: "gift"), "Gift")
        XCTAssertEqual(RecommendationTypeDisplay.label(for: "experience"), "Experience")
        XCTAssertEqual(RecommendationTypeDisplay.label(for: "date"), "Date")
        XCTAssertEqual(RecommendationTypeDisplay.label(for: "idea"), "Idea")
        XCTAssertEqual(RecommendationTypeDisplay.label(for: "plan"), "Date Plan")
    }

    func testLabelFallsBackToCapitalized() {
        XCTAssertEqual(RecommendationTypeDisplay.label(for: "workshop"), "Workshop")
    }
}

// MARK: - Detail content

final class RecommendationDetailContentTests: XCTestCase {

    // Inputs mirroring `PreviewRecommendations.bookablePurchasable`, the item
    // the PR screenshot harness renders.
    private let fondaVibes = ["quiet_luxury", "street_urban"]
    private let fondaLoveLanguages = ["words_of_affirmation", "acts_of_service"]
    private let fondaInterests = ["Music", "Travel"]
    private let fondaMerchant = "The Fonda Theatre / Ticketmaster"

    // MARK: isIdea

    func testIsIdeaTreatsIdeaTypesAndFlagAsIdea() {
        XCTAssertTrue(RecommendationDetailContent.isIdea(type: "plan", isIdeaFlag: nil))
        // An `idea`-typed item is a Knot Original even when the flag is stale —
        // the same rule the feed card applies.
        XCTAssertTrue(RecommendationDetailContent.isIdea(type: "idea", isIdeaFlag: false))
        XCTAssertTrue(RecommendationDetailContent.isIdea(type: "gift", isIdeaFlag: true))
        XCTAssertFalse(RecommendationDetailContent.isIdea(type: "date", isIdeaFlag: false))
        XCTAssertFalse(RecommendationDetailContent.isIdea(type: "date", isIdeaFlag: nil))
    }

    // MARK: matchCount

    func testMatchCountSumsAllFactors() {
        XCTAssertEqual(
            RecommendationDetailContent.matchCount(
                vibes: fondaVibes, loveLanguages: fondaLoveLanguages, interests: fondaInterests
            ),
            6
        )
        XCTAssertEqual(RecommendationDetailContent.matchCount(vibes: [], loveLanguages: [], interests: []), 0)
    }

    // MARK: categoryLabel

    func testCategoryLabelUsesFirstTwoVibesUppercased() {
        XCTAssertEqual(
            RecommendationDetailContent.categoryLabel(
                vibes: ["quiet_luxury", "street_urban", "romantic"], type: "date"
            ),
            "QUIET LUXURY & STREET / URBAN"
        )
    }

    func testCategoryLabelSingleVibe() {
        XCTAssertEqual(RecommendationDetailContent.categoryLabel(vibes: ["romantic"], type: "date"), "ROMANTIC")
    }

    func testCategoryLabelFallsBackToType() {
        XCTAssertEqual(RecommendationDetailContent.categoryLabel(vibes: [], type: "date"), "DATE")
        XCTAssertEqual(RecommendationDetailContent.categoryLabel(vibes: [], type: "plan"), "DATE PLAN")
    }

    // MARK: metaLine

    func testMetaLineJoinsLocationAndMerchant() {
        XCTAssertEqual(
            RecommendationDetailContent.metaLine(
                locationText: "Sonoma, CA", merchantName: "Terroir & Table", isIdea: false
            ),
            "Sonoma, CA • Terroir & Table"
        )
    }

    func testMetaLineOmitsMerchantForIdeas() {
        XCTAssertEqual(
            RecommendationDetailContent.metaLine(
                locationText: "Sonoma, CA", merchantName: "Terroir & Table", isIdea: true
            ),
            "Sonoma, CA"
        )
    }

    func testMetaLineMerchantOnly() {
        XCTAssertEqual(
            RecommendationDetailContent.metaLine(locationText: nil, merchantName: "Terroir & Table", isIdea: false),
            "Terroir & Table"
        )
    }

    func testMetaLineNilWhenEmpty() {
        XCTAssertNil(RecommendationDetailContent.metaLine(locationText: nil, merchantName: nil, isIdea: false))
        XCTAssertNil(RecommendationDetailContent.metaLine(locationText: "", merchantName: "  ", isIdea: false))
        // An idea with only a merchant has nothing to show.
        XCTAssertNil(RecommendationDetailContent.metaLine(locationText: nil, merchantName: "Shop", isIdea: true))
    }

    // MARK: locationText

    func testLocationTextJoinsCityState() {
        XCTAssertEqual(RecommendationDetailContent.locationText(city: "Brooklyn", state: "NY"), "Brooklyn, NY")
        XCTAssertEqual(RecommendationDetailContent.locationText(city: "Brooklyn", state: nil), "Brooklyn")
        XCTAssertEqual(RecommendationDetailContent.locationText(city: nil, state: "NY"), "NY")
        XCTAssertNil(RecommendationDetailContent.locationText(city: nil, state: nil))
        XCTAssertNil(RecommendationDetailContent.locationText(city: "", state: " "))
    }

    // MARK: whereText

    /// The "Where you'll meet" card uses the same trim + join rule as the meta
    /// line, so whitespace-only parts never leak a stray comma.
    func testWhereTextJoinsAddressCityState() {
        XCTAssertEqual(
            RecommendationDetailContent.whereText(address: " 1 Main St ", city: "Brooklyn", state: "NY"),
            "1 Main St, Brooklyn, NY"
        )
        XCTAssertEqual(
            RecommendationDetailContent.whereText(address: nil, city: "  ", state: "CA"),
            "CA"
        )
        XCTAssertNil(RecommendationDetailContent.whereText(address: nil, city: "  ", state: nil))
    }

    // MARK: knotPickLabel

    func testKnotPickLabelHumanizesFirstLoveLanguage() {
        XCTAssertEqual(
            RecommendationDetailContent.knotPickLabel(loveLanguages: fondaLoveLanguages),
            "Words of Affirmation"
        )
        XCTAssertEqual(RecommendationDetailContent.knotPickLabel(loveLanguages: ["quality_time"]), "Quality Time")
    }

    func testKnotPickLabelFallback() {
        XCTAssertEqual(RecommendationDetailContent.knotPickLabel(loveLanguages: []), "Hand-picked")
    }

    // MARK: typeStatLabel

    func testTypeStatLabel() {
        XCTAssertEqual(
            RecommendationDetailContent.typeStatLabel(isIdea: true, merchantName: "Ignored"),
            "Knot Original"
        )
        XCTAssertEqual(
            RecommendationDetailContent.typeStatLabel(isIdea: false, merchantName: fondaMerchant),
            fondaMerchant
        )
        XCTAssertEqual(
            RecommendationDetailContent.typeStatLabel(isIdea: false, merchantName: nil),
            "Purchasable"
        )
        XCTAssertEqual(
            RecommendationDetailContent.typeStatLabel(isIdea: false, merchantName: "  "),
            "Purchasable"
        )
    }

    // MARK: stats

    func testStatsBuildsThreeColumns() {
        let stats = RecommendationDetailContent.stats(
            type: "date",
            isIdea: false,
            merchantName: fondaMerchant,
            vibes: fondaVibes,
            loveLanguages: fondaLoveLanguages,
            interests: fondaInterests
        )
        XCTAssertEqual(stats, [
            .init(value: "6", label: "Profile matches", isAccent: false),
            .init(value: "Knot Pick", label: "Words of Affirmation", isAccent: true),
            .init(value: "Date", label: fondaMerchant, isAccent: false)
        ])
    }

    func testStatsForIdeaUsesKnotOriginal() {
        let stats = RecommendationDetailContent.stats(
            type: "plan",
            isIdea: true,
            merchantName: nil,
            vibes: ["romantic"],
            loveLanguages: [],
            interests: ["Cooking"]
        )
        XCTAssertEqual(stats, [
            .init(value: "2", label: "Profile matches", isAccent: false),
            .init(value: "Knot Pick", label: "Hand-picked", isAccent: true),
            .init(value: "Date Plan", label: "Knot Original", isAccent: false)
        ])
    }

    /// Saved-tab snapshots carry no matched arrays — the strip is omitted
    /// rather than rendered with a "0".
    func testStatsNilWithoutMatches() {
        XCTAssertNil(RecommendationDetailContent.stats(
            type: "gift", isIdea: false, merchantName: "Shop", vibes: [], loveLanguages: [], interests: []
        ))
    }
}

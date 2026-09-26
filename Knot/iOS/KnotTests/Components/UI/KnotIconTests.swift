//
//  KnotIconTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotIconTests: XCTestCase {

    /// Every case has its generated asset in the bundle. A case added without
    /// re-running `scripts/generate-mui-icons.mjs` would otherwise draw nothing.
    func testEveryCaseHasABundledAsset() {
        for icon in KnotIcon.allCases {
            let image = UIImage(named: icon.assetName)
            XCTAssertNotNil(image, "\(icon.rawValue) has no asset — run iOS/scripts/generate-mui-icons.mjs")
            XCTAssertEqual(image?.size, CGSize(width: 24, height: 24), "\(icon.rawValue) should be a 24pt MUI glyph")
        }
    }

    /// Assets live in the `MUI/` namespace so they can never collide with the
    /// app's other image assets.
    func testAssetNameIsNamespaced() {
        XCTAssertEqual(KnotIcon.homeOutlined.assetName, "MUI/HomeOutlined")
        XCTAssertEqual(KnotIcon.bookmark.assetName, "MUI/Bookmark")
    }

    /// `uiImage` resolves the real glyph (the navigation bar's back arrow
    /// depends on it), not the empty fallback.
    func testUIImageResolvesTheGlyph() {
        XCTAssertEqual(KnotIcon.arrowBackIosNewOutlined.uiImage.size, CGSize(width: 24, height: 24))
    }

    /// MUI's `FavoriteOutlined`, `BookmarkOutlined` and `StarOutlined` are solid
    /// despite their names. The outlines are the `*Border` glyphs; the solid
    /// names must never sneak in as "outlined" icons.
    func testNoSolidGlyphMasqueradingAsOutlined() {
        let traps: Set<String> = ["FavoriteOutlined", "BookmarkOutlined", "StarOutlined"]
        let offenders = KnotIcon.allCases.map(\.rawValue).filter(traps.contains)
        XCTAssertEqual(offenders, [], "Use FavoriteBorder / BookmarkBorder / StarBorder for outlines")
    }

    func testKnotIconViewRenders() {
        let view = KnotIconView(.homeOutlined, size: 24).foregroundStyle(Theme.accent)
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }
}

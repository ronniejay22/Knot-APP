//
//  KnotProgressIndicatorTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotProgressIndicatorTests: XCTestCase {

    func testInlineRenders() throws {
        let inline = KnotProgressIndicator.Inline()
        XCTAssertNotNil(UIHostingController(rootView: inline).view)
    }

    func testOverlayRendersWithoutMessage() throws {
        let overlay = KnotProgressIndicator.Overlay()
        XCTAssertNotNil(UIHostingController(rootView: overlay).view)
    }

    func testOverlayRendersWithMessage() throws {
        let overlay = KnotProgressIndicator.Overlay(message: "Deleting account...")
        XCTAssertNotNil(UIHostingController(rootView: overlay).view)
    }
}

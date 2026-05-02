//
//  KnotButtonTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotButtonTests: XCTestCase {

    func testRendersAllVariants() throws {
        for variant in KnotButton<Text>.Variant.allCases {
            let button = KnotButton("Tap me", variant: variant, action: {})
            let host = UIHostingController(rootView: button)
            XCTAssertNotNil(host.view, "Button should render variant: \(variant)")
        }
    }

    func testRendersAllSizes() throws {
        for size in KnotButton<Text>.Size.allCases {
            let button = KnotButton("Size", size: size, action: {})
            let host = UIHostingController(rootView: button)
            XCTAssertNotNil(host.view, "Button should render size: \(size)")
        }
    }

    func testRendersBothShapes() throws {
        let rounded = KnotButton("R", shape: .rounded, action: {})
        let pill = KnotButton("P", shape: .pill, action: {})
        XCTAssertNotNil(UIHostingController(rootView: rounded).view)
        XCTAssertNotNil(UIHostingController(rootView: pill).view)
    }

    func testLoadingStateRenders() throws {
        let button = KnotButton("Loading", isLoading: true, action: {})
        let host = UIHostingController(rootView: button)
        XCTAssertNotNil(host.view)
    }

    func testActionFires() {
        var fired = false
        let button = KnotButton("Tap", action: { fired = true })
        button.action()
        XCTAssertTrue(fired, "action closure should fire")
    }

    func testLongTitleDoesNotCrash() {
        let title = String(repeating: "Long ", count: 30)
        let button = KnotButton(title, action: {})
        let host = UIHostingController(rootView: button)
        XCTAssertNotNil(host.view)
    }
}

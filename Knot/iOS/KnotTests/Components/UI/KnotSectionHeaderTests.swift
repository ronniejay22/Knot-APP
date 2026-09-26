//
//  KnotSectionHeaderTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotSectionHeaderTests: XCTestCase {

    func testCaptionStyleRenders() throws {
        let header = KnotSectionHeader<EmptyView>("Account", style: .caption)
        XCTAssertNotNil(UIHostingController(rootView: header).view)
    }

    func testSubheadStyleWithIconRenders() throws {
        let header = KnotSectionHeader<EmptyView>("Recent Hints", icon: .lightbulbOutlined)
        XCTAssertNotNil(UIHostingController(rootView: header).view)
    }

    func testSubheadWithTrailingActionRenders() throws {
        let header = KnotSectionHeader("Upcoming") {
            Text("View All")
        }
        XCTAssertNotNil(UIHostingController(rootView: header).view)
    }
}

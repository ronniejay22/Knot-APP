//
//  KnotBadgeTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
import LucideIcons
@testable import Knot

@MainActor
final class KnotBadgeTests: XCTestCase {

    func testRendersAllVariants() throws {
        for variant in KnotBadge<Text>.Variant.allCases {
            let badge = KnotBadge("Label", variant: variant)
            let host = UIHostingController(rootView: badge)
            XCTAssertNotNil(host.view, "Badge should render variant: \(variant)")
        }
    }

    func testRendersAllSizes() throws {
        for size in KnotBadge<Text>.Size.allCases {
            let badge = KnotBadge("Label", size: size)
            let host = UIHostingController(rootView: badge)
            XCTAssertNotNil(host.view, "Badge should render size: \(size)")
        }
    }

    func testRendersWithLeadingIcon() throws {
        let badge = KnotBadge("Saved", leadingIcon: Lucide.bookmarkCheck)
        XCTAssertNotNil(UIHostingController(rootView: badge).view)
    }

    func testChipBothStates() throws {
        let selected = KnotChip(title: "S", isSelected: true, action: {})
        let unselected = KnotChip(title: "U", isSelected: false, action: {})
        XCTAssertNotNil(UIHostingController(rootView: selected).view)
        XCTAssertNotNil(UIHostingController(rootView: unselected).view)
    }

    func testChipActionFires() {
        var fired = false
        let chip = KnotChip(title: "Tap", isSelected: false, action: { fired = true })
        chip.action()
        XCTAssertTrue(fired)
    }
}

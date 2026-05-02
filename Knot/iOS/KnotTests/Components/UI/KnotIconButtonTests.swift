//
//  KnotIconButtonTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
import LucideIcons
@testable import Knot

@MainActor
final class KnotIconButtonTests: XCTestCase {

    func testRendersAllVariants() throws {
        for variant in KnotIconButton.Variant.allCases {
            let button = KnotIconButton(icon: Lucide.x, variant: variant, action: {})
            let host = UIHostingController(rootView: button)
            XCTAssertNotNil(host.view, "IconButton should render variant: \(variant)")
        }
    }

    func testRendersAllSizes() throws {
        for size in KnotIconButton.Size.allCases {
            let button = KnotIconButton(icon: Lucide.x, size: size, action: {})
            let host = UIHostingController(rootView: button)
            XCTAssertNotNil(host.view, "IconButton should render size: \(size)")
        }
    }

    func testActionFires() {
        var fired = false
        let button = KnotIconButton(icon: Lucide.x, action: { fired = true })
        button.action()
        XCTAssertTrue(fired)
    }
}

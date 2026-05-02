//
//  HintsListViewTests.swift
//  KnotTests
//
//  Step 18.2 (shadcn Phase 3): Render-without-crash tests for HintsListView
//  after migration to Knot* primitives (KnotCard, KnotBadge, KnotButton).
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class HintsListViewTests: XCTestCase {

    /// Verify HintsListView renders without crashing.
    /// Initial state shows either a loading spinner or the empty state CTA;
    /// either path exercises the migrated KnotButton primary pill.
    func testHintsListRenders() throws {
        let view = HintsListView()
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view, "HintsListView should render without crashing")
    }
}

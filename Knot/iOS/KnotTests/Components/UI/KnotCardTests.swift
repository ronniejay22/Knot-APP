//
//  KnotCardTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotCardTests: XCTestCase {

    func testRendersAllVariants() throws {
        let variants: [KnotCard<Text>.Variant] = [.default, .elevated, .outlinedDashed]
        for variant in variants {
            let card = KnotCard(variant: variant) {
                Text("Hello")
            }
            let host = UIHostingController(rootView: card)
            XCTAssertNotNil(host.view, "Card should render variant: \(variant)")
        }
    }

    func testRendersAllPaddings() throws {
        let paddings: [KnotCard<Text>.Padding] = [.none, .sm, .md, .lg, .xl]
        for padding in paddings {
            let card = KnotCard(padding: padding) { Text("x") }
            let host = UIHostingController(rootView: card)
            XCTAssertNotNil(host.view, "Card should render padding: \(padding)")
        }
    }

    func testRendersWithCustomRadius() throws {
        let card = KnotCard(radius: Theme.Radius.xl) { Text("x") }
        let host = UIHostingController(rootView: card)
        XCTAssertNotNil(host.view)
    }

    func testRendersComplexContent() throws {
        let card = KnotCard {
            VStack {
                Text("Title")
                Text(String(repeating: "Long content ", count: 30))
            }
        }
        let host = UIHostingController(rootView: card)
        XCTAssertNotNil(host.view)
    }
}

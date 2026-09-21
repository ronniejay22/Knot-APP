//
//  KnotAlertBannerTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
import LucideIcons
@testable import Knot

@MainActor
final class KnotAlertBannerTests: XCTestCase {

    private func makeBanner(
        action: @escaping @MainActor () -> Void = {},
        onDismiss: (@MainActor () -> Void)? = nil
    ) -> KnotAlertBanner {
        KnotAlertBanner(
            icon: Lucide.history,
            title: "Picking up where you left off",
            message: "These are the picks we found for Jas 2 days ago. Want a fresh set?",
            actionTitle: "Find new picks",
            action: action,
            onDismiss: onDismiss
        )
    }

    func testRendersWithDismiss() throws {
        let host = UIHostingController(rootView: makeBanner(onDismiss: {}))
        XCTAssertNotNil(host.view)
    }

    func testRendersWithoutDismiss() throws {
        let banner = makeBanner()
        XCTAssertNil(banner.onDismiss)
        let host = UIHostingController(rootView: banner)
        XCTAssertNotNil(host.view)
    }

    func testActionFires() {
        var fired = false
        let banner = makeBanner(action: { fired = true })
        banner.action()
        XCTAssertTrue(fired, "action closure should fire")
    }

    func testDismissFires() {
        var dismissed = false
        let banner = makeBanner(onDismiss: { dismissed = true })
        banner.onDismiss?()
        XCTAssertTrue(dismissed, "onDismiss closure should fire")
    }

    func testCarriesItsCopy() {
        let banner = makeBanner()
        XCTAssertEqual(banner.title, "Picking up where you left off")
        XCTAssertEqual(banner.actionTitle, "Find new picks")
        XCTAssertTrue(banner.message.contains("2 days ago"))
    }

    func testLongCopyDoesNotCrash() throws {
        let banner = KnotAlertBanner(
            icon: Lucide.history,
            title: String(repeating: "Long title ", count: 10),
            message: String(repeating: "Long message ", count: 40),
            actionTitle: String(repeating: "Go ", count: 20),
            action: {},
            onDismiss: {}
        )
        let host = UIHostingController(rootView: banner)
        XCTAssertNotNil(host.view)
    }
}

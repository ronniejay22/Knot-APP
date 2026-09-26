//
//  KnotListRowTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotListRowTests: XCTestCase {

    func testChevronRowRenders() throws {
        let row = KnotListRow.chevron(
            icon: .editOutlined,
            title: "Edit Profile",
            subtitle: "Update your details",
            action: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: row).view)
    }

    func testChevronRowActionFires() {
        var fired = false
        let row = KnotListRow.chevron(
            icon: .editOutlined,
            title: "Edit",
            action: { fired = true }
        )
        row.action?()
        XCTAssertTrue(fired)
    }

    func testInfoRowRenders() throws {
        let row = KnotListRow.info(
            icon: .mailOutlined,
            title: "Email",
            value: "user@example.com"
        )
        XCTAssertNotNil(UIHostingController(rootView: row).view)
    }

    func testToggleRowRenders() throws {
        let row = KnotListRow.toggle(
            icon: .notificationsActiveOutlined,
            title: "Notifications",
            isOn: .constant(true)
        )
        XCTAssertNotNil(UIHostingController(rootView: row).view)
    }

    func testActionRowRenders() throws {
        let row = KnotListRow.action(
            icon: .logoutOutlined,
            title: "Sign Out",
            action: {}
        )
        XCTAssertNotNil(UIHostingController(rootView: row).view)
    }
}

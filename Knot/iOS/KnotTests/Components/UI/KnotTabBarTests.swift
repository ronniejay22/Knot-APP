//
//  KnotTabBarTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotTabBarTests: XCTestCase {

    private func make(
        items: [KnotTabBar<Int>.Item],
        selection: Int = 0
    ) -> some View {
        StateBindingWrapper(initial: selection) { binding in
            KnotTabBar(selection: binding, items: items)
        }
    }

    func testRendersFourItems() {
        let view = make(items: [
            .init(id: 0, title: "For You", icon: .autoAwesomeOutlined, selectedIcon: .autoAwesomeOutlined),
            .init(id: 1, title: "Hints", icon: .lightbulbOutlined, selectedIcon: .lightbulbOutlined),
            .init(id: 2, title: "Saved", icon: .bookmarkBorder, selectedIcon: .bookmark),
            .init(id: 3, title: "Profile", icon: .accountCircleOutlined, selectedIcon: .accountCircle),
        ])
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    func testRendersSingleItem() {
        let view = make(items: [
            .init(id: 0, title: "Only", icon: .starBorder, selectedIcon: .star),
        ])
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    func testRendersWithNotificationDot() {
        let view = make(items: [
            .init(id: 0, title: "Hints", icon: .lightbulbOutlined, selectedIcon: .lightbulbOutlined, hasNotification: true),
            .init(id: 1, title: "Saved", icon: .bookmarkBorder, selectedIcon: .bookmark),
        ])
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    func testRendersAtEachSelection() {
        let items: [KnotTabBar<Int>.Item] = (0..<4).map {
            .init(id: $0, title: "T\($0)", icon: .radioButtonUncheckedOutlined, selectedIcon: .checkCircle)
        }
        for sel in 0..<4 {
            let view = make(items: items, selection: sel)
            XCTAssertNotNil(UIHostingController(rootView: view).view)
        }
    }

    func testItemHasNotificationDefaultsFalse() {
        let item = KnotTabBar<Int>.Item(id: 0, title: "x", icon: .homeOutlined, selectedIcon: .home)
        XCTAssertFalse(item.hasNotification)
    }

    func testItemRetainsExplicitHasNotification() {
        let item = KnotTabBar<Int>.Item(
            id: 0,
            title: "x",
            icon: .homeOutlined,
            selectedIcon: .home,
            hasNotification: true
        )
        XCTAssertTrue(item.hasNotification)
    }

    func testItemKeepsDistinctSelectedIcon() {
        let item = KnotTabBar<Int>.Item(id: 0, title: "Home", icon: .homeOutlined, selectedIcon: .home)
        XCTAssertEqual(item.icon, .homeOutlined)
        XCTAssertEqual(item.selectedIcon, .home)
    }
}

// MARK: - Test helper

/// Hosts a `@State` value and exposes a `Binding` to it. Lets tests instantiate
/// views that take a `Binding` without spinning up an enclosing view hierarchy.
private struct StateBindingWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(
        initial: Value,
        @ViewBuilder content: @escaping (Binding<Value>) -> Content
    ) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}

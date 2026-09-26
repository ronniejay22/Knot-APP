//
//  KnotListGroupTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotListGroupTests: XCTestCase {

    // MARK: - Row style environment

    func testRowStyleDefaultsToStandalone() {
        XCTAssertEqual(EnvironmentValues().knotListRowStyle, .standalone)
    }

    /// A group switches the rows inside it to `.grouped` — read back through a
    /// probe view, since the environment isn't otherwise observable.
    func testGroupPropagatesGroupedStyle() {
        let box = StyleBox()
        render(KnotListGroup("Partner") { StyleProbe(box: box) })
        XCTAssertEqual(box.value, .grouped)
    }

    func testRowsOutsideAGroupStayStandalone() {
        let box = StyleBox()
        render(StyleProbe(box: box))
        XCTAssertEqual(box.value, .standalone)
    }

    // MARK: - Rendering

    func testAllRowFactoriesRenderGrouped() {
        let group = KnotListGroup("Everything") {
            KnotListRow.chevron(icon: .favoriteBorder, title: "Partner profile", action: {})
            KnotListDivider()
            KnotListRow.info(icon: .mailOutlined, title: "Email", value: "you@example.com")
            KnotListDivider()
            KnotListRow.toggle(icon: .notificationsActiveOutlined, title: "Notifications", isOn: .constant(true))
            KnotListDivider()
            KnotListRow.action(icon: .refreshOutlined, title: "Reset", subtitle: "Subtitle", action: {})
        }
        XCTAssertNotNil(render(group))
    }

    func testGroupRendersWithAndWithoutTitle() {
        XCTAssertNotNil(render(KnotListGroup("Account") {
            KnotListRow.info(icon: .mailOutlined, title: "Email", value: "you@example.com")
        }))
        XCTAssertNotNil(render(KnotListGroup {
            KnotListRow.info(icon: .mailOutlined, title: "Email", value: "you@example.com")
        }))
    }

    // MARK: - Metrics

    /// Dividers start where a grouped row's title does: past the row padding,
    /// the icon tile, and the gap after it.
    func testDividerInsetLinesUpWithRowTitle() {
        XCTAssertEqual(
            KnotListRowMetrics.dividerLeadingInset,
            KnotListRowMetrics.horizontalPadding + KnotListRowMetrics.tileSize + KnotListRowMetrics.iconSpacing
        )
        XCTAssertEqual(KnotListRowMetrics.dividerLeadingInset, 62)
    }

    // MARK: - Pixel checks

    /// Rows outside a group must look exactly as they did before `.grouped`
    /// existed, so the default render has to match an explicit `.standalone`.
    func testDefaultRenderMatchesStandalone() throws {
        let defaultPNG = try png(of: Self.sampleRow())
        let standalonePNG = try png(of: Self.sampleRow().knotListRowStyle(.standalone))
        XCTAssertEqual(defaultPNG, standalonePNG)
    }

    func testGroupedRenderDiffersFromStandalone() throws {
        let standalonePNG = try png(of: Self.sampleRow().knotListRowStyle(.standalone))
        let groupedPNG = try png(of: Self.sampleRow().knotListRowStyle(.grouped))
        XCTAssertNotEqual(standalonePNG, groupedPNG)
    }

    // MARK: - Helpers

    private static func sampleRow() -> some View {
        KnotListRow.chevron(icon: .eventOutlined, title: "Milestones", action: {})
    }

    @discardableResult
    private func render(_ view: some View) -> UIImage? {
        ImageRenderer(content: view.frame(width: 320)).uiImage
    }

    private func png(of view: some View) throws -> Data {
        let image = try XCTUnwrap(render(view), "The row did not render")
        return try XCTUnwrap(image.pngData(), "The render has no PNG data")
    }
}

// MARK: - Probe

@MainActor
private final class StyleBox {
    var value: KnotListRowStyle?
}

/// Records the row style it sees in the environment when its body runs.
private struct StyleProbe: View {
    let box: StyleBox
    @Environment(\.knotListRowStyle) private var style

    var body: some View {
        box.value = style
        return Color.clear.frame(width: 1, height: 1)
    }
}

//
//  KnotInputTests.swift
//  KnotTests
//

import XCTest
import SwiftUI
@testable import Knot

@MainActor
final class KnotInputTests: XCTestCase {

    func testSingleLineRenders() throws {
        let input = KnotInput(text: .constant(""), placeholder: "Email")
        let host = UIHostingController(rootView: input)
        XCTAssertNotNil(host.view)
    }

    func testMultiLineRenders() throws {
        let input = KnotInput(
            text: .constant(""),
            placeholder: "Notes",
            style: .multiLine,
            minHeight: 80
        )
        let host = UIHostingController(rootView: input)
        XCTAssertNotNil(host.view)
    }

    func testRendersAllValidationStates() throws {
        let states: [KnotInput.ValidationState] = [.neutral, .focused, .error, .success]
        for state in states {
            let input = KnotInput(
                text: .constant("value"),
                placeholder: "p",
                validationState: state
            )
            let host = UIHostingController(rootView: input)
            XCTAssertNotNil(host.view, "Input should render validation state: \(state)")
        }
    }

    func testRendersWithLeadingIcon() throws {
        let input = KnotInput(
            text: .constant(""),
            placeholder: "Email",
            leadingIcon: .mailOutlined
        )
        XCTAssertNotNil(UIHostingController(rootView: input).view)
    }

    func testRendersWithTrailingAccessory() throws {
        let input = KnotInput(
            text: .constant("text"),
            placeholder: "p",
            trailingAccessory: AnyView(KnotIconView(.closeOutlined, size: 16))
        )
        XCTAssertNotNil(UIHostingController(rootView: input).view)
    }
}

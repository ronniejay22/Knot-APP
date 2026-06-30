//
//  DevAPIBaseURLResolutionTests.swift
//  KnotTests
//

import XCTest
@testable import Knot

/// Verifies the DEBUG base-URL resolution precedence:
/// UserDefaults override → injected Info.plist value → loopback fallback.
/// This is what lets the simulator and a physical device both reach the
/// local backend without manual edits.
final class DevAPIBaseURLResolutionTests: XCTestCase {

    func testUserDefaultsOverrideWins() {
        let result = Constants.API.resolveDebugBaseURL(
            override: "http://10.0.0.5:8000",
            injected: "http://192.168.1.20:8000"
        )
        XCTAssertEqual(result, "http://10.0.0.5:8000")
    }

    func testInjectedValueUsedWhenNoOverride() {
        let result = Constants.API.resolveDebugBaseURL(
            override: nil,
            injected: "http://192.168.1.20:8000"
        )
        XCTAssertEqual(result, "http://192.168.1.20:8000")
    }

    func testFallsBackToLoopback() {
        let result = Constants.API.resolveDebugBaseURL(override: nil, injected: nil)
        XCTAssertEqual(result, Constants.API.debugFallbackBaseURL)
        XCTAssertEqual(result, "http://127.0.0.1:8420")
    }

    func testBlankValuesAreIgnored() {
        let result = Constants.API.resolveDebugBaseURL(override: "   ", injected: "  ")
        XCTAssertEqual(result, Constants.API.debugFallbackBaseURL)
    }
}

//
//  DevAPIBaseURLResolutionTests.swift
//  KnotTests
//

import XCTest
@testable import Knot

/// Verifies the DEBUG base-URL resolution precedence:
/// UserDefaults override → injected LAN IP (physical device only) → loopback.
/// This is what lets the simulator and a physical device both reach the
/// local backend without manual edits. On the simulator the injected LAN IP is
/// skipped in favour of loopback, since the simulator shares the Mac's loopback.
final class DevAPIBaseURLResolutionTests: XCTestCase {

    func testUserDefaultsOverrideWins() {
        let result = Constants.API.resolveDebugBaseURL(
            override: "http://10.0.0.5:8000",
            injected: "http://192.168.1.20:8000"
        )
        XCTAssertEqual(result, "http://10.0.0.5:8000")
    }

    func testInjectedValueUsedOnDeviceWhenNoOverride() {
        let result = Constants.API.resolveDebugBaseURL(
            override: nil,
            injected: "http://192.168.1.20:8000",
            isSimulator: false
        )
        XCTAssertEqual(result, "http://192.168.1.20:8000")
    }

    func testSimulatorPrefersLoopbackOverInjected() {
        // The simulator reaches the Mac via loopback, so the injected LAN IP is
        // ignored — this is what keeps the simulator working when the backend
        // is bound to 127.0.0.1 only.
        let result = Constants.API.resolveDebugBaseURL(
            override: nil,
            injected: "http://192.168.1.20:8000",
            isSimulator: true
        )
        XCTAssertEqual(result, Constants.API.debugFallbackBaseURL)
        XCTAssertEqual(result, "http://127.0.0.1:8420")
    }

    func testOverrideWinsEvenOnSimulator() {
        let result = Constants.API.resolveDebugBaseURL(
            override: "http://10.0.0.5:8000",
            injected: "http://192.168.1.20:8000",
            isSimulator: true
        )
        XCTAssertEqual(result, "http://10.0.0.5:8000")
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

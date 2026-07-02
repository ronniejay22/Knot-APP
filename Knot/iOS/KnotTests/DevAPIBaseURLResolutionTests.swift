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

    func testDeviceHonorsLANIPOverride() {
        let result = Constants.API.resolveDebugBaseURL(
            override: "http://10.0.0.5:8420",
            injected: "http://192.168.1.20:8420",
            isSimulator: false
        )
        XCTAssertEqual(result, "http://10.0.0.5:8420")
    }

    func testInjectedValueUsedOnDeviceWhenNoOverride() {
        let result = Constants.API.resolveDebugBaseURL(
            override: nil,
            injected: "http://192.168.1.20:8420",
            isSimulator: false
        )
        XCTAssertEqual(result, "http://192.168.1.20:8420")
    }

    func testSimulatorPrefersLoopbackOverInjected() {
        // The simulator reaches the Mac via loopback, so the injected LAN IP is
        // ignored — this is what keeps the simulator working when the backend
        // is bound to 127.0.0.1 only.
        let result = Constants.API.resolveDebugBaseURL(
            override: nil,
            injected: "http://192.168.1.20:8420",
            isSimulator: true
        )
        XCTAssertEqual(result, Constants.API.debugFallbackBaseURL)
        XCTAssertEqual(result, "http://127.0.0.1:8420")
    }

    func testSimulatorIgnoresLANIPOverride() {
        // A stale LAN-IP override must NOT strand the simulator on an unreachable
        // host — it falls through to loopback (the new invariant).
        let result = Constants.API.resolveDebugBaseURL(
            override: "http://192.168.1.239:8000",
            injected: "http://192.168.1.20:8420",
            isSimulator: true
        )
        XCTAssertEqual(result, "http://127.0.0.1:8420")
    }

    func testSimulatorHonorsLoopbackOverride() {
        // A loopback override (e.g. a custom port) is still respected on the simulator.
        let result = Constants.API.resolveDebugBaseURL(
            override: "http://127.0.0.1:9999",
            injected: "http://192.168.1.20:8420",
            isSimulator: true
        )
        XCTAssertEqual(result, "http://127.0.0.1:9999")
    }

    func testSimulatorHonorsHostnameOverride() {
        // A hostname override (not a LAN IP) is still respected on the simulator.
        let result = Constants.API.resolveDebugBaseURL(
            override: "http://my-mac.local:8420",
            injected: nil,
            isSimulator: true
        )
        XCTAssertEqual(result, "http://my-mac.local:8420")
    }

    func testFallsBackToLoopback() {
        let result = Constants.API.resolveDebugBaseURL(
            override: nil, injected: nil, isSimulator: true
        )
        XCTAssertEqual(result, Constants.API.debugFallbackBaseURL)
        XCTAssertEqual(result, "http://127.0.0.1:8420")
    }

    func testBlankValuesAreIgnored() {
        let result = Constants.API.resolveDebugBaseURL(
            override: "   ", injected: "  ", isSimulator: true
        )
        XCTAssertEqual(result, Constants.API.debugFallbackBaseURL)
    }

    // MARK: - isPrivateLANHost

    func testIsPrivateLANHostTrueForRFC1918() {
        for url in [
            "http://10.0.0.5:8420",
            "http://192.168.1.239:8000",
            "http://172.16.0.1:8420",
            "http://172.31.255.255:8420",
            "192.168.1.239:8000",   // scheme-less (as a stale `defaults write` might be)
            "10.0.0.5",             // scheme-less, no port
        ] {
            XCTAssertTrue(Constants.API.isPrivateLANHost(url), url)
        }
    }

    func testIsPrivateLANHostFalseForLoopbackAndHostnames() {
        for url in [
            "http://127.0.0.1:8420",
            "http://localhost:8420",
            "http://my-mac.local:8420",
            "http://172.15.0.1:8420",   // just below the 172.16–31 private range
            "http://172.32.0.1:8420",   // just above it
            "https://api.knot-app.com",
        ] {
            XCTAssertFalse(Constants.API.isPrivateLANHost(url), url)
        }
    }
}

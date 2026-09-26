//
//  LaunchSplashTests.swift
//  KnotTests
//
//  Step 19.64: the launch splash — `LaunchScreen.storyboard` (drawn by iOS
//  before any app code runs) and `LaunchSplashView` (drawn by the app while
//  startup runs). Three things are pinned here:
//
//  1. Everything the launch screen needs actually ships. Its failure mode is
//     silent: a missing asset or a stale Info.plist key renders a blank screen
//     with no build error — which is exactly how the previous launch screen
//     stayed blank for months (it named `LaunchIcon` / `LaunchScreenBackground`
//     assets that never existed).
//  2. The storyboard and the SwiftUI view agree on geometry, so the hand-off
//     between them is invisible.
//  3. The storyboard's images stay color pre-compensated. iOS saves the launch
//     snapshot with sRGB pixel values but labels it Display P3, so a plain
//     sRGB re-export would show an oversaturated pink that visibly jumps to
//     coral when the app takes over — and nothing else would catch it.
//

import SwiftUI
import UIKit
import XCTest
@testable import Knot

@MainActor
final class LaunchSplashTests: XCTestCase {

    // MARK: - Bundle wiring

    func testLaunchStoryboardIsDeclaredAndBundled() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "UILaunchStoryboardName") as? String,
            "LaunchScreen",
            "Info.plist must point iOS at LaunchScreen.storyboard"
        )
        XCTAssertNil(
            Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen"),
            "The UILaunchScreen dict must be gone — keep one launch-screen source, and the dict can only draw a flat color"
        )
        XCTAssertNotNil(
            Bundle.main.path(forResource: "LaunchScreen", ofType: "storyboardc"),
            "The compiled launch storyboard is missing from the app bundle"
        )
    }

    func testLaunchAssetsAreBundled() {
        XCTAssertNotNil(UIImage(named: "LaunchLockup"), "LaunchLockup is missing — the launch screen would render without the logo")
        XCTAssertNotNil(UIImage(named: "LaunchGradient"), "LaunchGradient is missing — the launch screen would render with no background")
        XCTAssertNotNil(UIImage(named: "SplashLockup"), "SplashLockup is missing — the in-app splash would render without the logo")
    }

    /// Each lockup renders at its native size, so its point size is part of the
    /// hand-off contract — and the storyboard's and the app's must agree.
    func testLockupsHaveTheDesignedPointSize() throws {
        for name in ["LaunchLockup", "SplashLockup"] {
            let lockup = try XCTUnwrap(UIImage(named: name))
            XCTAssertEqual(lockup.size.width, 204, accuracy: 0.01, name)
            XCTAssertEqual(lockup.size.height, 92, accuracy: 0.01, name)
        }
    }

    // MARK: - Color (and the storyboard's pre-compensation)

    /// The gradient strip stores the Display P3 *encoding* of the design stops
    /// under an sRGB label, so the snapshot's P3 label reads it back as the
    /// design colors — the same ones `Theme.launchGradient` draws in-app.
    func testLaunchGradientIsColorPrecompensated() throws {
        let strip = try XCTUnwrap(UIImage(named: "LaunchGradient")?.cgImage)
        let pixels = storedPixels(of: strip)
        let stops: [(row: Int, color: Color, name: String)] = [
            (0, Theme.colorLaunchTop, "top stop"),
            (strip.height - 1, Theme.colorPrimaryDeep, "bottom stop"),
        ]
        for stop in stops {
            let expected = try encoding(of: UIColor(stop.color).cgColor, in: CGColorSpace.displayP3)
            let i = stop.row * strip.width * 4
            for channel in 0..<3 {
                XCTAssertEqual(Int(pixels[i + channel]), expected[channel], accuracy: 1, "\(stop.name), channel \(channel)")
            }
        }
    }

    /// `LaunchLockup` (storyboard) is `SplashLockup` (in-app) pre-compensated:
    /// every opaque pixel of one is the Display P3 encoding of the other. That
    /// is what makes the logo — tile, "K" and wordmark — keep its color across
    /// the hand-off.
    func testLaunchLockupIsTheSplashLockupPrecompensated() throws {
        let launch = try XCTUnwrap(UIImage(named: "LaunchLockup")?.cgImage)
        let splash = try XCTUnwrap(UIImage(named: "SplashLockup")?.cgImage)
        XCTAssertEqual(launch.width, splash.width)
        XCTAssertEqual(launch.height, splash.height)

        let launchPixels = storedPixels(of: launch)
        let splashPixels = storedPixels(of: splash)
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var compared = 0
        var worstDifference = 0
        // Every 97th pixel spreads the samples across the whole lockup.
        for i in stride(from: 0, to: splashPixels.count, by: 4 * 97)
        where splashPixels[i + 3] == 255 && launchPixels[i + 3] == 255 {
            let components = (0..<3).map { CGFloat(splashPixels[i + $0]) / 255 } + [1]
            let color = try XCTUnwrap(CGColor(colorSpace: srgb, components: components))
            let expected = try encoding(of: color, in: CGColorSpace.displayP3)
            for channel in 0..<3 {
                worstDifference = max(worstDifference, abs(Int(launchPixels[i + channel]) - expected[channel]))
            }
            compared += 1
        }
        XCTAssertGreaterThan(compared, 100, "Too few opaque pixels sampled to judge the lockup")
        // The two are separate renders of the same vector lockup, so the tile's
        // texture resamples a level or three apart. A lockup that was NOT
        // pre-compensated is 18 levels off, so 3 still catches it.
        XCTAssertLessThanOrEqual(worstDifference, 3, "LaunchLockup is not the P3 encoding of SplashLockup")
    }

    /// `Theme.launchGradient` is what the in-app splash draws, so it must run
    /// from `colorLaunchTop` at the top to `colorPrimaryDeep` at the bottom.
    /// Rendered and sampled, because a `LinearGradient` doesn't expose its
    /// stops — swapping them or the direction would otherwise go unnoticed.
    func testSplashGradientRunsFromTheTopStopToTheBottomStop() throws {
        let renderer = ImageRenderer(content: Theme.launchGradient.frame(width: 4, height: 200))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let pixels = storedPixels(of: image)
        let stops: [(row: Int, color: Color, name: String)] = [
            (0, Theme.colorLaunchTop, "top"),
            (image.height - 1, Theme.colorPrimaryDeep, "bottom"),
        ]
        for stop in stops {
            let expected = try encoding(of: UIColor(stop.color).cgColor, in: CGColorSpace.sRGB)
            let i = stop.row * image.width * 4
            for channel in 0..<3 {
                XCTAssertEqual(Int(pixels[i + channel]), expected[channel], accuracy: 2, "\(stop.name) row, channel \(channel)")
            }
        }
    }

    /// The image's pixels as 8-bit sRGB RGBA, top row first. For the
    /// sRGB-labelled launch images these are exactly their stored bytes.
    private func storedPixels(of image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    /// A color's RGB components in the named color space, as 0–255 values.
    private func encoding(of color: CGColor, in spaceName: CFString) throws -> [Int] {
        let space = try XCTUnwrap(CGColorSpace(name: spaceName))
        let converted = try XCTUnwrap(color.converted(to: space, intent: .defaultIntent, options: nil))
        let components = try XCTUnwrap(converted.components)
        return components.prefix(3).map { Int(($0 * 255).rounded()) }
    }

    // MARK: - Storyboard ↔ SwiftUI parity

    /// The storyboard pins the lockup to the same vertical offset that
    /// `LaunchSplashView` applies. If one changes without the other, the logo
    /// jumps on the first frame the app draws.
    func testStoryboardAndSwiftUIShareTheLockupOffset() throws {
        let controller = try XCTUnwrap(
            UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController()
        )
        let root = try XCTUnwrap(controller.view)
        let imageViews = root.subviews.compactMap { $0 as? UIImageView }
        XCTAssertEqual(imageViews.count, 2, "Expected the gradient and the lockup image views")

        let lockupView = try XCTUnwrap(
            imageViews.first { $0.image?.size == UIImage(named: "LaunchLockup")?.size },
            "No image view shows the LaunchLockup image"
        )
        let centerY = try XCTUnwrap(
            root.constraints.first {
                ($0.firstItem as? UIView) === lockupView && $0.firstAttribute == .centerY
            },
            "The lockup must be vertically centered by constraint"
        )
        XCTAssertEqual(centerY.constant, LaunchSplashView.lockupCenterOffset)

        let hasCenterX = root.constraints.contains {
            ($0.firstItem as? UIView) === lockupView && $0.firstAttribute == .centerX && $0.constant == 0
        }
        XCTAssertTrue(hasCenterX, "The lockup must be horizontally centered")
    }

    /// The gradient must fill the whole screen, not the safe area — the SwiftUI
    /// splash ignores the safe area too.
    func testStoryboardGradientIsPinnedToTheScreenEdges() throws {
        let controller = try XCTUnwrap(
            UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController()
        )
        let root = try XCTUnwrap(controller.view)
        let gradientView = try XCTUnwrap(
            root.subviews.compactMap { $0 as? UIImageView }
                .first { $0.image?.size == UIImage(named: "LaunchGradient")?.size }
        )
        XCTAssertEqual(gradientView.contentMode, .scaleToFill)
        for edge: NSLayoutConstraint.Attribute in [.top, .bottom, .leading, .trailing] {
            let pinned = root.constraints.contains {
                ($0.firstItem as? UIView) === gradientView
                    && $0.firstAttribute == edge
                    && ($0.secondItem as? UIView) === root
                    && $0.constant == 0
            }
            XCTAssertTrue(pinned, "Gradient is not pinned to the screen's \(edge.rawValue) edge")
        }
    }

    // MARK: - SwiftUI splash

    func testSplashRenders() {
        let host = UIHostingController(rootView: LaunchSplashView())
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }

    func testSplashIsReadableByVoiceOver() {
        XCTAssertEqual(LaunchSplashView.accessibilityLabel, "Knot. Always know what they love")
    }

    // MARK: - Overlay gate

    func testSplashCoversTheAppOnlyWhileStartingUp() {
        XCTAssertTrue(LaunchSplashView.showsLaunchSplash(isCheckingSession: true, isHarnessActive: false))
        XCTAssertFalse(LaunchSplashView.showsLaunchSplash(isCheckingSession: false, isHarnessActive: false))
    }

    /// The screenshot harness never finishes startup (it skips the auth
    /// lifecycle), so without this gate the splash would cover every capture.
    func testSplashNeverCoversTheScreenshotHarness() {
        XCTAssertFalse(LaunchSplashView.showsLaunchSplash(isCheckingSession: true, isHarnessActive: true))
        XCTAssertFalse(LaunchSplashView.showsLaunchSplash(isCheckingSession: false, isHarnessActive: true))
    }
}

// MARK: - Startup checks (Step 19.64)

/// `AuthViewModel.concurrently` is what lets the two startup network checks
/// overlap. These tests prove the overlap rather than inferring it from timing.
@MainActor
final class AuthStartupChecksTests: XCTestCase {

    /// A one-way latch the second operation opens.
    private actor Latch {
        private(set) var isOpen = false
        func open() { isOpen = true }
    }

    /// The first operation only succeeds if it observes the second one running
    /// while it is still in flight. Run sequentially, the first would poll
    /// alone for its whole budget and return `false` — so this fails instead
    /// of hanging, and can't pass by timing luck.
    func testBothOperationsRunAtTheSameTime() async {
        let latch = Latch()
        let (sawSecondStart, second) = await AuthViewModel.concurrently(
            { () async -> Bool in
                for _ in 0..<200 {
                    if await latch.isOpen { return true }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                return false
            },
            { () async -> Int in
                await latch.open()
                return 42
            }
        )
        XCTAssertTrue(sawSecondStart, "The second operation did not start until the first finished")
        XCTAssertEqual(second, 42)
    }

    /// Results come back in argument order, whatever order they finish in.
    func testResultsKeepTheirPositions() async {
        let (a, b) = await AuthViewModel.concurrently(
            { () async -> String in
                try? await Task.sleep(for: .milliseconds(50))
                return "slow first"
            },
            { () async -> Bool? in nil }
        )
        XCTAssertEqual(a, "slow first")
        XCTAssertNil(b)
    }
}

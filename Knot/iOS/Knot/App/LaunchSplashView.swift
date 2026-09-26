//
//  LaunchSplashView.swift
//  Knot
//
//  The in-app half of the launch splash (Figma node 1004:1373).
//

import SwiftUI

/// The branded screen the user sees while the app starts up — from the first
/// frame until `AuthViewModel` has restored the session and finished its
/// startup checks.
///
/// **It must look exactly like the system launch screen.** iOS shows
/// `LaunchScreen.storyboard` before any app code runs, then hands over to this
/// view. If the two disagree by a color or a point, the hand-off reads as a
/// flicker instead of one continuous screen. So both draw the same two things
/// at the same geometry:
///
/// - The `#FF385C → #E0295C` gradient. The storyboard stretches the
///   `LaunchGradient` strip; this view draws `Theme.launchGradient`. Both span
///   the full screen, ignoring the safe area.
/// - The pre-rendered lockup at its native size, centered `lockupCenterOffset`
///   points above screen center.
///
/// The lockup is an image rather than live `Text` because the storyboard cannot
/// reliably render the bundled DM Sans font. The tagline therefore doesn't
/// scale with Dynamic Type; the VoiceOver label carries the words instead.
///
/// This view draws `SplashLockup`, not the storyboard's `LaunchLockup`. The
/// storyboard's images are color pre-compensated for the way iOS mislabels the
/// launch snapshot (see the note in `LaunchScreen.storyboard`), so drawn here
/// they would look washed out. `SplashLockup` is the same render in true color.
struct LaunchSplashView: View {

    /// Vertical offset of the lockup from screen center. The design centers it
    /// in a content area with 28pt top and 48pt bottom padding, which puts it
    /// 10pt above center. `LaunchScreen.storyboard` pins the same constant.
    static let lockupCenterOffset: CGFloat = -10

    /// What VoiceOver reads for the lockup.
    static let accessibilityLabel = "Knot. Always know what they love"

    var body: some View {
        ZStack {
            Theme.launchGradient

            Image("SplashLockup")
                .offset(y: Self.lockupCenterOffset)
                .accessibilityLabel(Self.accessibilityLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    /// Whether the startup overlay covers the app.
    ///
    /// The UI-test screenshot harness skips the auth lifecycle entirely, so
    /// `isCheckingSession` never flips false under it. Without this gate the
    /// splash would sit over every screenshot the harness captures.
    static func showsLaunchSplash(isCheckingSession: Bool, isHarnessActive: Bool) -> Bool {
        isCheckingSession && !isHarnessActive
    }
}

// MARK: - Fade-out overlay

/// Keeps `LaunchSplashView` on top of the app until startup finishes, then fades
/// it out.
///
/// This is an overlay that stays mounted while it animates, not a transition on
/// the router's branch. Step 19.51 measured that a removal transition on a
/// switched-out branch doesn't animate in this app — the branch is unmounted on
/// the frame the condition changes. The same approach as
/// `RecommendationLoadingOverlay`.
private struct LaunchSplashOverlay: ViewModifier {

    /// True while the splash should cover the app.
    let isActive: Bool

    /// Mounted while covering and while fading out.
    @State private var isMounted: Bool

    /// Drives the fade. Animated, so opacity interpolates.
    @State private var isFading = false

    /// How long the fade into the app takes.
    static let fadeDuration: Double = 0.35

    init(isActive: Bool) {
        self.isActive = isActive
        // Correct on the very first frame, before `onChange` has run.
        _isMounted = State(initialValue: isActive)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isMounted {
                    LaunchSplashView()
                        .opacity(isFading ? 0 : 1)
                        // Never intercepts a tap. During startup there is nothing
                        // underneath to tap; during the fade, the destination
                        // is responsive from its first frame.
                        .allowsHitTesting(false)
                        .accessibilityHidden(isFading)
                }
            }
            .onChange(of: isActive) { _, active in
                guard !active, isMounted, !isFading else { return }
                withAnimation(.easeOut(duration: Self.fadeDuration)) {
                    isFading = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(Self.fadeDuration))
                    isMounted = false
                }
            }
    }
}

extension View {
    /// Covers the view with the launch splash while `isActive`, then fades it
    /// out once. Startup happens once per launch, so the splash never comes
    /// back after it has faded.
    func launchSplashOverlay(isActive: Bool) -> some View {
        modifier(LaunchSplashOverlay(isActive: isActive))
    }
}

#Preview {
    LaunchSplashView()
}

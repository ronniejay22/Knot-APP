//
//  SignInView.swift
//  Knot
//
//  Created on February 6, 2026.
//  Redesigned with photo grid + branding split layout.
//

import SwiftUI
import LucideIcons

/// The sign-in screen displayed when no authenticated session exists.
/// Features a two-section layout: a cream-colored photo grid on top (~55%)
/// and a dark-gradient branding section with CTAs on the bottom (~45%).
///
/// Both "Get Started" and "I already have an account" navigate to the
/// multi-provider LoginView (Apple, Google, Email magic link).
struct SignInView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        @Bindable var viewModel = authViewModel

        NavigationStack {
            ZStack {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // MARK: - Top: Photo Grid
                        PhotoGridSection()
                            .frame(height: geometry.size.height * 0.55)

                        // MARK: - Bottom: Branding + Actions
                        BrandingSection(authViewModel: authViewModel)
                            .frame(maxHeight: .infinity)
                    }
                }
                .ignoresSafeArea()

                // MARK: - Loading Overlay
                if authViewModel.isLoading {
                    Theme.overlayDim
                        .ignoresSafeArea()
                    ProgressView("Signing in...")
                        .tint(.white)
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "getStarted":
                    LoginView()
                case "magicLink":
                    MagicLinkView()
                default:
                    EmptyView()
                }
            }
        }
        .alert("Sign In Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authViewModel.signInError ?? "An unknown error occurred.")
        }
    }
}

// MARK: - Photo Grid Section

/// Displays a decorative grid of placeholder photo tiles on a cream background.
/// Tiles are arranged in staggered rows that bleed off-screen for visual interest.
///
/// Performance: this used to run an unconditional `TimelineView(.animation)` at
/// the display's native refresh rate (60-120 Hz), re-evaluating 40 `Image`
/// nodes per frame. On real devices that was enough to peg one main-thread
/// core, which made every other interaction in the app feel sluggish — taps
/// would queue up behind layout work and the keyboard's input recognition
/// would back up. Three changes mitigate this:
///   1. `@State isVisible` + `.onAppear`/`.onDisappear` removes the
///      `TimelineView` subtree the instant the view goes off-screen, so any
///      SwiftUI view-tree retention after navigation no longer keeps the
///      animation running.
///   2. `.periodic(from: .now, by: 1.0 / 30.0)` caps the redraw at 30 fps
///      regardless of display refresh rate (≥2× saving on 60 Hz devices,
///      4× on 120 Hz ProMotion). The scroll cycle is 12 seconds long, so
///      30 fps is visually indistinguishable from native refresh.
///   3. `.drawingGroup()` composes the tile subtree off-screen via Metal,
///      moving the per-frame composite off the main thread to the GPU.
private struct PhotoGridSection: View {
    private let tileImages: [[String]] = [
        ["SignIn/signin-0", "SignIn/signin-1", "SignIn/signin-2", "SignIn/signin-3", "SignIn/signin-4"],
        ["SignIn/signin-5", "SignIn/signin-6", "SignIn/signin-7", "SignIn/signin-8", "SignIn/signin-9"],
        ["SignIn/signin-10", "SignIn/signin-11", "SignIn/signin-12", "SignIn/signin-13", "SignIn/signin-14"],
        ["SignIn/signin-15", "SignIn/signin-16", "SignIn/signin-17", "SignIn/signin-18", "SignIn/signin-19"],
    ]

    private let tileSpacing: CGFloat = 10
    private let tileCornerRadius: CGFloat = 18
    private let cycleDuration: Double = 12

    @State private var isVisible = true

    var body: some View {
        GeometryReader { geometry in
            let tileWidth = max(0, (geometry.size.width - tileSpacing * 3) / 3.5)
            let tileHeight = tileWidth
            let singleSetWidth = 5 * (tileWidth + tileSpacing)

            Group {
                if isVisible {
                    TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                        gridContent(
                            at: timeline.date,
                            singleSetWidth: singleSetWidth,
                            tileWidth: tileWidth,
                            tileHeight: tileHeight
                        )
                    }
                } else {
                    // Static first-frame snapshot — same layout, no animation.
                    // Prevents the SwiftUI view tree from keeping the
                    // `TimelineView` subscription alive after the user
                    // navigates away or backgrounds the app.
                    gridContent(
                        at: .distantPast,
                        singleSetWidth: singleSetWidth,
                        tileWidth: tileWidth,
                        tileHeight: tileHeight
                    )
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    @ViewBuilder
    private func gridContent(
        at date: Date,
        singleSetWidth: CGFloat,
        tileWidth: CGFloat,
        tileHeight: CGFloat
    ) -> some View {
        let elapsed = date.timeIntervalSinceReferenceDate
        let progress = CGFloat(elapsed.truncatingRemainder(dividingBy: cycleDuration)) / CGFloat(cycleDuration)
        let scrollAmount = progress * singleSetWidth

        ZStack {
            Theme.signInCream

            VStack(spacing: tileSpacing) {
                ForEach(0..<4, id: \.self) { row in
                    let scrollsRight = row.isMultiple(of: 2)

                    HStack(spacing: tileSpacing) {
                        ForEach(0..<10, id: \.self) { col in
                            Image(tileImages[row][col % 5])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: tileWidth, height: tileHeight)
                                .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius))
                        }
                    }
                    .offset(x: scrollsRight
                        ? scrollAmount - singleSetWidth
                        : -scrollAmount
                    )
                }
            }
            .drawingGroup()
        }
        .clipped()
    }
}

// MARK: - Branding Section

/// Bottom section with the Knot branding, tagline, and sign-in/get-started buttons.
private struct BrandingSection: View {
    let authViewModel: AuthViewModel

    var body: some View {
        ZStack {
            Theme.backgroundGradient

            VStack(spacing: 0) {
                // MARK: - Heart Icon
                Image(uiImage: Lucide.heart)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                // MARK: - Two-tone App Name
                // Per-`Text` font modifier — `.font(...)` doesn't propagate
                // across `Text + Text` concatenation.
                (
                    Text("Kn")
                        .foregroundStyle(Theme.textPrimary)
                        .knotFont(Theme.Typography.heroDisplay)
                    + Text("ot")
                        .foregroundStyle(Theme.accent)
                        .knotFont(Theme.Typography.heroDisplay)
                )
                    .tracking(-1)
                    .padding(.bottom, 6)

                // MARK: - Tagline (signature italic Fraunces brand moment)
                Text("Connect Deeply")
                    .knotFont(Theme.Typography.italicQuote)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                // MARK: - Get Started Button
                NavigationLink(value: "getStarted") {
                    Text("Get Started")
                        .knotFont(Theme.Typography.cta)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.signInButtonPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.bottom, 20)

                // MARK: - Terms & Privacy
                HStack(spacing: 4) {
                    Text("Terms & Conditions")
                    Text("•")
                    Text("Privacy Policy")
                }
                .knotFont(Theme.Typography.label)
                .foregroundStyle(Theme.accent)

                Spacer()
                    .frame(height: 16)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Preview

#Preview {
    SignInView()
        .environment(AuthViewModel())
}

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
                    Color.black.opacity(0.4)
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

    var body: some View {
        GeometryReader { geometry in
            let tileWidth = max(0, (geometry.size.width - tileSpacing * 3) / 3.5)
            let tileHeight = tileWidth
            let singleSetWidth = 5 * (tileWidth + tileSpacing)

            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
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
                }
                .clipped()
            }
        }
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
                (Text("Kn").foregroundStyle(.white) + Text("ot").foregroundStyle(Theme.accent))
                    .font(.system(size: 42, weight: .bold))
                    .tracking(-1)
                    .padding(.bottom, 6)

                // MARK: - Tagline
                Text("Connect Deeply")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                // MARK: - Get Started Button
                NavigationLink(value: "getStarted") {
                    Text("Get Started")
                        .font(.headline.weight(.semibold))
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
                .font(.caption)
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

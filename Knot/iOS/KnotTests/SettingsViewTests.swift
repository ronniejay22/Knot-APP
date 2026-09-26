//
//  SettingsViewTests.swift
//  KnotTests
//
//  Created on February 16, 2026.
//  Step 11.1: Unit tests for SettingsView and SettingsViewModel.
//  Step 11.2: Account deletion state management and ReauthenticationSheet tests.
//  Profile redesign: hero formatting, partner loading, and legal link tests.
//

import XCTest
import SwiftUI
@testable import Knot

// MARK: - SettingsViewModel Tests

@MainActor
final class SettingsViewModelTests: XCTestCase {

    /// Verify ViewModel initializes with correct default state.
    func testInitialState() {
        let vm = SettingsViewModel()

        XCTAssertEqual(vm.userEmail, "")
        XCTAssertFalse(vm.showDeleteConfirmationSheet)
        XCTAssertFalse(vm.isDeletingAccount)
        XCTAssertNil(vm.deleteAccountError)
        XCTAssertFalse(vm.notificationsEnabled)
        XCTAssertFalse(vm.isUpdatingNotifications)
        XCTAssertNil(vm.partnerSummary)
        XCTAssertFalse(vm.hasResolvedPartner)
        XCTAssertFalse(vm.hasLoadedInitially)
        XCTAssertTrue(vm.showsHeroPlaceholder)
        XCTAssertEqual(vm.heroContent, .placeholder)
    }

    /// Verify showDeleteConfirmationSheet can be toggled.
    func testDeleteConfirmationSheetToggle() {
        let vm = SettingsViewModel()

        vm.showDeleteConfirmationSheet = true
        XCTAssertTrue(vm.showDeleteConfirmationSheet)

        vm.showDeleteConfirmationSheet = false
        XCTAssertFalse(vm.showDeleteConfirmationSheet)
    }

    /// Verify notificationsEnabled can be toggled.
    func testNotificationsEnabledToggle() {
        let vm = SettingsViewModel()

        vm.notificationsEnabled = true
        XCTAssertTrue(vm.notificationsEnabled)

        vm.notificationsEnabled = false
        XCTAssertFalse(vm.notificationsEnabled)
    }

    /// Verify userEmail can be set.
    func testUserEmailCanBeSet() {
        let vm = SettingsViewModel()

        vm.userEmail = "test@example.com"
        XCTAssertEqual(vm.userEmail, "test@example.com")
    }

    // MARK: - Account Deletion State Tests (Step 15.5)

    /// Verify new deletion state properties have correct defaults.
    func testDeletionInitialState() {
        let vm = SettingsViewModel()

        XCTAssertFalse(vm.showDeleteConfirmationSheet)
        XCTAssertFalse(vm.isDeletingAccount)
        XCTAssertNil(vm.deleteAccountError)
    }

    /// Verify requestAccountDeletion presents the typed-confirmation sheet directly.
    func testRequestAccountDeletionShowsConfirmationSheet() {
        let vm = SettingsViewModel()

        vm.requestAccountDeletion()
        XCTAssertTrue(vm.showDeleteConfirmationSheet)
    }

    /// Verify deleteAccountError can be set and cleared.
    func testDeleteAccountErrorCanBeSetAndCleared() {
        let vm = SettingsViewModel()

        vm.deleteAccountError = "Network error"
        XCTAssertEqual(vm.deleteAccountError, "Network error")

        vm.deleteAccountError = nil
        XCTAssertNil(vm.deleteAccountError)
    }

    /// Verify isDeletingAccount can be toggled.
    func testIsDeletingAccountToggle() {
        let vm = SettingsViewModel()

        vm.isDeletingAccount = true
        XCTAssertTrue(vm.isDeletingAccount)

        vm.isDeletingAccount = false
        XCTAssertFalse(vm.isDeletingAccount)
    }
}

// MARK: - SettingsView Rendering Tests

@MainActor
final class SettingsViewRenderingTests: XCTestCase {

    /// Verify the SettingsView renders without crashing.
    func testViewRenders() {
        let view = SettingsView()
            .environment(AuthViewModel())
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "SettingsView should render a valid view")
    }

    /// Verify the SettingsView renders in dark mode.
    func testViewRendersInDarkMode() {
        let view = SettingsView()
            .environment(AuthViewModel())
            .preferredColorScheme(.dark)
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "SettingsView should render in dark mode")
    }

    /// Verify the typed-confirmation sheet renders without crashing.
    func testReauthenticationSheetRenders() {
        let view = ReauthenticationSheet(
            onConfirm: { true },
            onCancel: {}
        )
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view, "ReauthenticationSheet should render a valid view")
    }

    /// Verify the redesigned Profile tab renders with a seeded partner.
    func testSeededTabEmbeddedViewRenders() {
        let vm = SettingsViewModel(vaultFetcher: StubVaultFetcher(.success(makeVault())))
        vm.userEmail = "you@example.com"
        vm.partnerSummary = PartnerProfileSummary(vault: makeVault())
        vm.hasResolvedPartner = true
        vm.hasLoadedInitially = true

        let view = SettingsView(isTabEmbedded: true, viewModel: vm)
            .environment(AuthViewModel())
        let hostingController = UIHostingController(rootView: view)
        XCTAssertNotNil(hostingController.view)
    }

    /// Verify the hero renders loaded, with no partner, and as a placeholder.
    func testProfileHeroCardRendersEveryState() {
        let states: [(ProfileHeroContent, Bool)] = [
            (ProfileHeroContent(summary: PartnerProfileSummary(vault: makeVault())), false),
            (ProfileHeroContent(summary: nil), false),
            (.placeholder, true)
        ]
        for (content, isPlaceholder) in states {
            let view = ProfileHeroCard(content: content, isPlaceholder: isPlaceholder, onEditProfile: {})
            XCTAssertNotNil(UIHostingController(rootView: view).view)
        }
    }

    /// The footer links must keep pointing at the published legal documents,
    /// the same ones the onboarding paywall links to.
    func testLegalLinksPointAtPublishedDocuments() {
        XCTAssertEqual(
            SettingsView.termsURL.absoluteString,
            "https://drive.google.com/file/d/1AeU_SpK1pJ1l8Cl1eLqYXSGEwIiEY7Bc/view"
        )
        XCTAssertEqual(
            SettingsView.privacyURL.absoluteString,
            "https://drive.google.com/file/d/1aBUcFdQoMj14dLWpF72gZkHlJtpbgZKW/view"
        )
    }
}

// MARK: - SettingsViewModel Partner Tests

@MainActor
final class SettingsViewModelPartnerTests: XCTestCase {

    func testLoadPartnerProfileStoresSummary() async {
        let vm = SettingsViewModel(vaultFetcher: StubVaultFetcher(.success(makeVault())))

        await vm.loadPartnerProfile()

        XCTAssertEqual(vm.partnerSummary, PartnerProfileSummary(
            partnerName: "Jas",
            relationshipTenureMonths: 38,
            locationCity: "Austin",
            locationState: "TX"
        ))
        XCTAssertTrue(vm.hasResolvedPartner)
        XCTAssertFalse(vm.showsHeroPlaceholder)
        XCTAssertEqual(vm.heroContent.title, "You & Jas")
    }

    /// A failed first load resolves to the generic hero rather than leaving
    /// the placeholder up forever.
    func testFailedFirstLoadShowsGenericHero() async {
        let vm = SettingsViewModel(vaultFetcher: StubVaultFetcher(.failure(StubError())))

        await vm.loadPartnerProfile()

        XCTAssertNil(vm.partnerSummary)
        XCTAssertTrue(vm.hasResolvedPartner)
        XCTAssertFalse(vm.showsHeroPlaceholder)
        XCTAssertEqual(vm.heroContent, ProfileHeroContent(summary: nil))
        XCTAssertEqual(vm.heroContent.title, "You & your partner")
    }

    /// A failed refresh (e.g. after closing Edit profile offline) keeps the
    /// partner that already loaded.
    func testFailedRefreshKeepsEarlierSummary() async {
        let fetcher = StubVaultFetcher(.success(makeVault()))
        let vm = SettingsViewModel(vaultFetcher: fetcher)
        await vm.loadPartnerProfile()
        let loaded = vm.partnerSummary

        fetcher.result = .failure(StubError())
        await vm.loadPartnerProfile()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(vm.partnerSummary, loaded)
        XCTAssertEqual(fetcher.callCount, 2)
    }

    /// A refresh after an edit replaces the summary.
    func testRefreshReplacesSummary() async {
        let fetcher = StubVaultFetcher(.success(makeVault()))
        let vm = SettingsViewModel(vaultFetcher: fetcher)
        await vm.loadPartnerProfile()

        fetcher.result = .success(makeVault(name: "Sam", tenure: 5, city: nil, state: "CA"))
        await vm.loadPartnerProfile()

        XCTAssertEqual(vm.heroContent.title, "You & Sam")
        XCTAssertEqual(vm.heroContent.subtitle, "Together 5 mos · CA")
    }

    /// When two loads overlap, the newer one wins even if the older one
    /// answers last — the launch fetch must not undo an edit's refresh.
    func testStaleLoadIsDroppedForNewerOne() async {
        let fetcher = ControlledVaultFetcher()
        let vm = SettingsViewModel(vaultFetcher: fetcher)

        let launchLoad = Task { await vm.loadPartnerProfile() }
        await fetcher.waitForPending(1)
        let refreshAfterEdit = Task { await vm.loadPartnerProfile() }
        await fetcher.waitForPending(2)

        fetcher.resume(at: 1, with: makeVault(name: "Sam"))
        await refreshAfterEdit.value
        fetcher.resume(at: 0, with: makeVault(name: "Jas"))
        await launchLoad.value

        XCTAssertEqual(vm.partnerSummary?.partnerName, "Sam")
        XCTAssertTrue(vm.hasResolvedPartner)
    }

    /// A partner that never loaded (launched offline) is retried when the app
    /// returns to the foreground.
    func testForegroundRetriesPartnerThatNeverLoaded() async {
        let fetcher = StubVaultFetcher(.failure(StubError()))
        let vm = SettingsViewModel(vaultFetcher: fetcher)
        vm.hasLoadedInitially = true
        await vm.loadPartnerProfile()
        XCTAssertNil(vm.partnerSummary)

        fetcher.result = .success(makeVault())
        await vm.refreshOnForeground()

        XCTAssertEqual(vm.partnerSummary?.partnerName, "Jas")
        XCTAssertEqual(fetcher.callCount, 2)
    }

    /// A loaded partner isn't refetched on every return to the foreground.
    func testForegroundLeavesLoadedPartnerAlone() async {
        let fetcher = StubVaultFetcher(.success(makeVault()))
        let vm = SettingsViewModel(vaultFetcher: fetcher)
        vm.hasLoadedInitially = true
        await vm.loadPartnerProfile()

        await vm.refreshOnForeground()

        XCTAssertEqual(fetcher.callCount, 1)
    }

    /// A seeded model (screenshot harness, previews) never touches the network.
    func testSeededModelMakesNoFetches() async {
        let fetcher = StubVaultFetcher(.success(makeVault()))
        let vm = SettingsViewModel(vaultFetcher: fetcher)
        vm.hasLoadedInitially = true

        await vm.loadOnAppear()

        XCTAssertEqual(fetcher.callCount, 0)
        XCTAssertNil(vm.partnerSummary)
    }
}

// MARK: - ProfileHeroContent Tests

final class ProfileHeroContentTests: XCTestCase {

    // MARK: Tenure

    func testTenureIsOmittedWhenMissingOrNotPositive() {
        for months in [nil, 0, -1] as [Int?] {
            XCTAssertNil(ProfileHeroContent.tenure(months: months, style: .abbreviated), "\(String(describing: months))")
            XCTAssertNil(ProfileHeroContent.tenure(months: months, style: .spoken), "\(String(describing: months))")
        }
    }

    func testTenureFormatting() {
        let cases: [(months: Int, abbreviated: String, spoken: String)] = [
            (1, "1 mo", "1 month"),
            (8, "8 mos", "8 months"),
            (11, "11 mos", "11 months"),
            (12, "1 yr", "1 year"),
            (23, "1 yr", "1 year"),
            (24, "2 yrs", "2 years"),
            (38, "3 yrs", "3 years")
        ]
        for c in cases {
            XCTAssertEqual(ProfileHeroContent.tenure(months: c.months, style: .abbreviated), c.abbreviated, "\(c.months) months")
            XCTAssertEqual(ProfileHeroContent.tenure(months: c.months, style: .spoken), c.spoken, "\(c.months) months")
        }
    }

    // MARK: Place

    func testPlacePrefersCityThenState() {
        XCTAssertEqual(ProfileHeroContent.place(city: "Austin", state: "TX"), "Austin")
        XCTAssertEqual(ProfileHeroContent.place(city: nil, state: "TX"), "TX")
        XCTAssertEqual(ProfileHeroContent.place(city: "   ", state: "TX"), "TX")
        XCTAssertNil(ProfileHeroContent.place(city: nil, state: nil))
        XCTAssertNil(ProfileHeroContent.place(city: "", state: "  "))
    }

    func testPlaceIsTrimmed() {
        XCTAssertEqual(ProfileHeroContent.place(city: "  Austin \n", state: nil), "Austin")
        XCTAssertEqual(ProfileHeroContent.place(city: nil, state: " TX "), "TX")
    }

    // MARK: Subtitle

    func testDetailPartsDropMissingParts() {
        XCTAssertEqual(ProfileHeroContent.detailParts(tenure: "3 yrs", place: "Austin"), ["Together 3 yrs", "Austin"])
        XCTAssertEqual(ProfileHeroContent.detailParts(tenure: nil, place: "Austin"), ["Austin"])
        XCTAssertEqual(ProfileHeroContent.detailParts(tenure: nil, place: nil), [])
    }

    func testSubtitleJoinsPartsOnOneLine() {
        func content(_ parts: [String]) -> ProfileHeroContent {
            ProfileHeroContent(title: "", subtitleParts: parts, avatarName: "", accessibilityLabel: "")
        }
        XCTAssertEqual(content(["Together 3 yrs", "Austin"]).subtitle, "Together 3 yrs · Austin")
        XCTAssertEqual(content(["Together 3 yrs"]).subtitle, "Together 3 yrs")
        XCTAssertEqual(content(["Austin"]).subtitle, "Austin")
        XCTAssertNil(content([]).subtitle)
    }

    // MARK: Full content

    func testFullSummary() {
        let content = ProfileHeroContent(summary: PartnerProfileSummary(vault: makeVault()))

        XCTAssertEqual(content.title, "You & Jas")
        XCTAssertEqual(content.subtitle, "Together 3 yrs · Austin")
        // What the hero stacks when the one-line subtitle doesn't fit.
        XCTAssertEqual(content.subtitleParts, ["Together 3 yrs", "Austin"])
        XCTAssertEqual(content.avatarName, "Jas")
        XCTAssertEqual(content.accessibilityLabel, "You and Jas. Together 3 years, Austin")
    }

    func testNameIsTrimmed() {
        let content = ProfileHeroContent(summary: PartnerProfileSummary(vault: makeVault(name: "  Jas \n")))

        XCTAssertEqual(content.title, "You & Jas")
        XCTAssertEqual(content.avatarName, "Jas")
    }

    func testBlankNameFallsBack() {
        let content = ProfileHeroContent(summary: PartnerProfileSummary(vault: makeVault(name: "   ")))

        XCTAssertEqual(content.title, "You & your partner")
        XCTAssertEqual(content.avatarName, "")
        XCTAssertEqual(content.accessibilityLabel, "You and your partner. Together 3 years, Austin")
    }

    func testMissingSummaryFallsBack() {
        let content = ProfileHeroContent(summary: nil)

        XCTAssertEqual(content.title, "You & your partner")
        XCTAssertNil(content.subtitle)
        XCTAssertEqual(content.subtitleParts, [])
        XCTAssertEqual(content.avatarName, "")
        XCTAssertEqual(content.accessibilityLabel, "You and your partner")
    }

    func testSpokenLabelWithOnlyAPlace() {
        let content = ProfileHeroContent(summary: PartnerProfileSummary(vault: makeVault(tenure: nil)))

        XCTAssertEqual(content.subtitle, "Austin")
        XCTAssertEqual(content.accessibilityLabel, "You and Jas. Austin")
    }

    func testSpokenLabelWithOnlyATenure() {
        let content = ProfileHeroContent(summary: PartnerProfileSummary(vault: makeVault(tenure: 1, city: nil, state: nil)))

        XCTAssertEqual(content.subtitle, "Together 1 mo")
        XCTAssertEqual(content.accessibilityLabel, "You and Jas. Together 1 month")
    }

    func testPlaceholderAnnouncesLoading() {
        XCTAssertEqual(ProfileHeroContent.placeholder.accessibilityLabel, "Loading profile")
    }

    func testSummaryMapsVaultFields() {
        let summary = PartnerProfileSummary(vault: makeVault(name: "Jas", tenure: 38, city: "Austin", state: "TX"))

        XCTAssertEqual(summary.partnerName, "Jas")
        XCTAssertEqual(summary.relationshipTenureMonths, 38)
        XCTAssertEqual(summary.locationCity, "Austin")
        XCTAssertEqual(summary.locationState, "TX")
    }
}

// MARK: - Test Doubles

@MainActor
private final class StubVaultFetcher: PartnerVaultFetching {
    var result: Result<VaultGetResponse, Error>
    private(set) var callCount = 0

    init(_ result: Result<VaultGetResponse, Error>) {
        self.result = result
    }

    func getVault() async throws -> VaultGetResponse {
        callCount += 1
        return try result.get()
    }
}

/// Holds each `getVault()` call open until the test resumes it, so a test
/// can choose the order overlapping loads answer in.
@MainActor
private final class ControlledVaultFetcher: PartnerVaultFetching {
    private var pending: [CheckedContinuation<VaultGetResponse, Error>] = []

    func getVault() async throws -> VaultGetResponse {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }

    func waitForPending(_ count: Int) async {
        while pending.count < count { await Task.yield() }
    }

    func resume(at index: Int, with vault: VaultGetResponse) {
        pending[index].resume(returning: vault)
    }
}

private struct StubError: Error {}

private func makeVault(
    name: String = "Jas",
    tenure: Int? = 38,
    city: String? = "Austin",
    state: String? = "TX"
) -> VaultGetResponse {
    VaultGetResponse(
        vaultId: "vault-1",
        partnerName: name,
        relationshipTenureMonths: tenure,
        cohabitationStatus: nil,
        locationCity: city,
        locationState: state,
        locationCountry: "US",
        interests: [],
        dislikes: [],
        milestones: [],
        vibes: [],
        budgets: [],
        loveLanguages: []
    )
}

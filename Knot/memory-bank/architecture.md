# Architecture Guide: Project Knot

This document explains the purpose of each file and folder for future developers.

---

## Project Structure Overview

```
Knot/
├── memory-bank/               # Documentation and planning
│   ├── PRD.md                 # Product Requirements Document
│   ├── techstack.md           # Technology stack decisions
│   ├── IMPLEMENTATION_PLAN.md # Step-by-step build instructions
│   ├── progress.md            # Implementation progress log
│   └── architecture.md        # This file
├── iOS/                       # iOS application (Swift/SwiftUI)
└── backend/                   # Python/FastAPI backend
```

---

## iOS Application (`iOS/`)

### Configuration Files

| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen configuration. Defines targets, build settings, and dependencies. Run `xcodegen generate` after modifying. |
| `Knot.xcodeproj/` | Generated Xcode project. **Do not edit directly** — modify `project.yml` instead. |
| `Knot/Info.plist` | iOS app configuration (bundle name, supported orientations, launch screen). |
| `Knot/Knot.entitlements` | App entitlements file. Contains `com.apple.developer.applesignin` for Sign in with Apple and `aps-environment: development` for push notifications (Step 7.4). Referenced by `CODE_SIGN_ENTITLEMENTS` in `project.yml`. Both the entitlements plist and `project.yml` must stay in sync for XcodeGen. |

### Source Code (`iOS/Knot/`)

#### `/App` — Application Entry Point
| File | Purpose |
|------|---------|
| `KnotApp.swift` | Main app entry point. Configures SwiftData ModelContainer and injects it into the app environment. **Step 7.4:** Added `@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate` to bridge UIKit delegate callbacks into the SwiftUI lifecycle. |
| `ContentView.swift` | Root auth state router. Creates `AuthViewModel` as `@State`, injects it into the SwiftUI environment via `.environment()`, and starts the `authStateChanges` listener via `.task`. Routes between three states: loading spinner (`isCheckingSession`), `HomeView` (`isAuthenticated`), or `SignInView` (default). |
| `AppDelegate.swift` | **Active (Step 7.4).** `@MainActor final class` conforming to `UIApplicationDelegate` and `@preconcurrency UNUserNotificationCenterDelegate`. Handles APNs remote notification registration callbacks that SwiftUI cannot access natively. `didFinishLaunchingWithOptions` sets `UNUserNotificationCenter.current().delegate = self` for foreground notification display. `didRegisterForRemoteNotificationsWithDeviceToken` converts raw `Data` to hex string and calls `DeviceTokenService.shared.registerToken()`. `didFailToRegisterForRemoteNotificationsWithError` logs gracefully (expected on Simulator). `userNotificationCenter(_:willPresent:)` returns `[.banner, .sound]` for foreground notification display. Uses `@preconcurrency` on `UNUserNotificationCenterDelegate` to resolve Swift 6 strict concurrency errors with non-Sendable `UNUserNotificationCenter`/`UNNotification` parameters. |

#### `/Features` — Feature Modules
Organized by feature, each containing Views, ViewModels, and feature-specific components.

| Folder | Status | Purpose |
|--------|--------|---------|
| `Auth/` | **Active** | Apple Sign-In flow, session management, auth state |
| `Home/` | **Active** | Full Home screen with header, hint capture, milestone countdown, recent hints, offline banner (Step 4.1). |
| `Onboarding/` | **Active** | Partner Vault creation (9-step wizard). Container + ViewModel at root, step views in `Steps/` subfolder. |
| `Recommendations/` | **Active (Step 6.1)** | Choice-of-Three UI, recommendation cards, refresh flow |
| `HintCapture/` | Planned | Text and voice hint input |
| `Notifications/` | **Active (Step 7.7)** | Notification History screen showing past milestone notifications with recommendation detail. |
| `Settings/` | **Active (Step 3.12)** | Edit Profile screen. Future: full settings (notifications, account, privacy) in Step 11.1. |

##### `Auth/` — Authentication Feature
| File | Purpose |
|------|---------|
| `SignInView.swift` | Sign-in screen with Apple Sign-In button. Displays Knot branding (Lucide heart icon, title, tagline), three value proposition rows, and `SignInWithAppleButton` from `AuthenticationServices`. Delegates auth logic to `AuthViewModel` (shared via `@Environment`). Shows a loading overlay during Supabase sign-in. Contains a private `SignInFeatureRow` component for the value prop list. Uses `@Bindable` wrapper for alert binding. |
| `AuthViewModel.swift` | `@Observable @MainActor` class managing the full auth lifecycle. On launch, listens to `authStateChanges` to restore sessions from Keychain (`initialSession` event). Handles Apple Sign-In → Supabase Auth flow with OIDC nonce security. Provides `signOut()` (Step 2.4) which calls `supabase.auth.signOut()` to invalidate the server session, clear the Keychain, and emit `signedOut` through the listener. Exposes `isCheckingSession` (initial load), `isLoading` (sign-in in progress), `isAuthenticated` (drives root navigation), `signInError`, `showError`. All auth state transitions flow through `listenForAuthChanges()`. **Step 7.4:** Added `requestPushNotificationPermission()` private method that requests `UNUserNotificationCenter` authorization for `.alert`, `.badge`, `.sound` and calls `UIApplication.shared.registerForRemoteNotifications()` if granted. Called after vault check completes in both `.initialSession` and `.signedIn` cases. Non-blocking — denial is logged but doesn't affect app functionality. |

##### `Home/` — Home Feature
| File | Purpose |
|------|---------|
| `HomeView.swift` | **Active (Step 7.7).** Full Home screen with 6 sections: (1) **Offline banner** — red `HStack` with Lucide `wifiOff` icon, animated show/hide via `.transition(.move(edge: .top).combined(with: .opacity))`, driven by `networkMonitor.isConnected`; (2) **Header** — time-of-day greeting (`greetingText` switches on `Calendar.current.component(.hour)`), partner name (32pt bold, `minimumScaleFactor(0.7)` for long names), next milestone countdown badge (circular 64×64, `milestoneCountdownColor()` returns red/orange/yellow/pink by urgency), milestone subtitle with SF Symbol icon, and horizontally scrollable vibe capsule tags (`vibeDisplayName()` converts snake_case → Title Case inline); (3) **Hint Capture** — `TextEditor` with `ZStack` placeholder overlay, `@FocusState` border highlight, character counter (red at 450+, red.opacity(0.8) at limit), Lucide `mic` button (Step 4.3 voice capture placeholder), Lucide `arrowUp` submit button (accent fill when `canSubmitHint`, surface fill when disabled; shows `ProgressView` spinner when `isSubmittingHint`), `submitHint()` calls `viewModel.submitHint(text:)` which sends `POST /api/v1/hints` via `HintService`; on success shows green checkmark + "Hint saved!" overlay with `.scale.combined(with: .opacity)` transition (auto-dismisses after 1.5s via `Task.sleep`), green border stroke on input field during success; `UIImpactFeedbackGenerator(.light)` on tap, `UINotificationFeedbackGenerator` success/error on completion; input clears immediately for responsiveness (async API call in background); error message displayed in red below input (left-aligned); submit disabled when `isSubmittingHint`; (4) **Upcoming Milestones** — `ForEach(viewModel.upcomingMilestones)` renders `milestoneCard()` with SF Symbol type icon, name, `formattedDate`, countdown capsule pill, urgency coloring; loading spinner and dashed-border `emptyMilestoneCard`; (5) **Saved Recommendations (Step 6.6)** — `savedRecommendationsSection` renders `ForEach(viewModel.savedRecommendations)` as compact horizontal cards with type icon (Lucide gift/sparkles/heart), title (1-line), merchant name, formatted price, open-link button (opens `externalURL` via `UIApplication.shared.open`), and delete button (Lucide `x`). Section appears between recommendations button and recent hints; hidden when no saved recommendations. Auto-reloads via `loadSavedRecommendations(modelContext:)` on `.task` and `.onChange(of: showRecommendations)` when returning from recommendations screen; (6) **Recent Hints (Step 4.5)** — `ForEach(viewModel.recentHints)` renders `hintPreviewCard()` with source icon (pen/mic), 2-line text, relative timestamp; **"View All" button opens `HintsListView` via `.sheet(isPresented: $showHintsList)`**; dashed-border `emptyHintsCard` with guidance text. All interactive sections `.disabled(!networkMonitor.isConnected).opacity(0.5)` when offline. Toolbar: Knot branding (heart + "Knot") leading, edit profile (`userPen`) + sign out (`logOut`) trailing. Edit Profile via `.fullScreenCover`, vault and hints refresh on dismiss via `.onChange(of: showEditProfile)`. **Step 4.5:** Added hints list sheet presentation with automatic refresh of recent hints via `.onChange(of: showHintsList)` when user returns from the full list. `.task { await viewModel.loadVault(); await viewModel.loadRecentHints() }` on appear. `.scrollDismissesKeyboard(.interactively)`. Sign-out moves to Settings in Step 11.1. **Step 7.7:** Added `@State private var showNotifications = false` and Lucide `bellRing` toolbar button (before edit profile button) that opens `NotificationsView` via `.sheet(isPresented: $showNotifications)`. |
| `HomeViewModel.swift` | **Active (Step 6.6).** `@Observable @MainActor` class managing Home screen data and hint capture. **Vault data:** `loadVault()` calls `VaultService().getVault()` and stores the `VaultGetResponse` in `vault`. Computed properties: `partnerName` (fallback "Your Partner"), `upcomingMilestones` (parses all milestones via `parseMilestoneDate()`, computes `daysUntilNextOccurrence()` with year rollover, sorts by proximity, returns top 2 as `[UpcomingMilestone]`), `nextMilestone` (first upcoming), `vibes` (vault's vibe tags). **Hint capture (Step 4.2):** `submitHint(text:source:)` calls `HintService().createHint()`, sets `showHintSuccess = true` for checkmark animation, calls `loadRecentHints()` to refresh, auto-dismisses via `Task.sleep(for: .seconds(1.5))`, returns `Bool` success. `loadRecentHints()` calls `HintService().listHints(limit: 3)` and maps `HintItemResponse` to `[HintPreview]` with ISO 8601 date parsing. State: `isSubmittingHint` (loading), `showHintSuccess` (animation), `hintErrorMessage` (error display). **Step 6.6 saved recommendations:** `savedRecommendations: [SavedRecommendation]` array. `loadSavedRecommendations(modelContext:)` fetches up to 5 most recent `SavedRecommendation` objects sorted by `savedAt` descending via `FetchDescriptor`. `deleteSavedRecommendation(_:modelContext:)` deletes from SwiftData and removes from local array. **Helpers:** `parseMilestoneDate(_:)` splits "2000-MM-DD" into (month, day) tuple; `daysUntilNextOccurrence(month:day:from:calendar:)` tries current year first, falls back to next year if date passed; `parseISO8601(_:)` static method handles Supabase timestamps with/without fractional seconds via `ISO8601DateFormatter`. Also defines `UpcomingMilestone` (Identifiable, Sendable — id, name, type, month, day, daysUntil, budgetTier; computed `formattedDate`, `countdownText` with Today!/Tomorrow/in X days, `iconName` SF Symbol per milestone type, `urgencyLevel` enum critical/soon/upcoming/distant) and `HintPreview` (Identifiable, Sendable — id, text, source, createdAt). |
| `HintsListView.swift` | **Active (Step 4.6).** Full-screen hints list accessible via "View All" from Home screen, presented as a `.sheet`. Displays all captured hints in reverse chronological order using a `List` view (`.listStyle(.plain)`, transparent background via `.listRowBackground(Color.clear)`, hidden separators, custom insets). Each row shows: (1) source icon (Lucide `penLine` for text input, Lucide `mic` for voice), (2) hint text (3-line limit), (3) date captured (`.date` style), (4) time captured (`.time` style), (5) green "Used" badge with checkmark if `hint.isUsed`. **Swipe-to-delete:** `.swipeActions(edge: .trailing, allowsFullSwipe: true)` with red destructive button labeled "Delete" + trash icon. On delete, triggers `UINotificationFeedbackGenerator` success haptic and calls `viewModel.deleteHint(id:)` which sends `DELETE /api/v1/hints/{id}` via `HintService`. **Pull-to-refresh:** `.refreshable` reloads via `viewModel.loadHints()`. **Empty state:** `emptyStateView` with Lucide `messageSquarePlus` icon (64x64), "No hints yet" title, guidance text, and "Back to Home" button that dismisses the sheet. **Navigation:** X button (top-left) with Lucide `x` icon dismisses sheet. `.navigationTitle("All Hints")` with `.inline` display mode. **Error handling:** `.alert` for `viewModel.errorMessage`. **Loading state:** `ProgressView` with `Theme.accent` tint during initial load. **Note:** Uses `List` (not `ScrollView` + `LazyVStack`) because `.swipeActions()` only works properly with `List` views in SwiftUI. |
| `HintsListViewModel.swift` | **Active (Step 4.6).** `@Observable @MainActor` class managing hints list state for `HintsListView`. **Data loading:** `loadHints()` calls `HintService.listHints(limit: 100, offset: 0)` and maps `HintItemResponse` DTOs to local `[HintItem]` models with ISO 8601 date parsing (handles both fractional seconds and non-fractional formats via `ISO8601DateFormatter`). State: `isLoading` (loading indicator), `hints: [HintItem]` (display data), `errorMessage: String?` (alert), `isDeletingHintId: String?` (opacity during delete). **Deletion (Step 4.6):** `deleteHint(id:)` calls `HintService.deleteHint(id:)` which sends `DELETE /api/v1/hints/{id}` to the backend. On success, removes the hint from the local `hints` array. On failure, sets `errorMessage` for the alert. **HintItem model:** Local struct (Identifiable, Sendable) with `id`, `text`, `source`, `isUsed`, `createdAt: Date`. Lives in this file (not `/Models/DTOs.swift`) since it's specific to list view display with parsed dates. **ISO 8601 parsing:** `parseISO8601(_:)` static helper tries `.withFractionalSeconds` first, falls back to `.withInternetDateTime` for compatibility with both Supabase timestamp formats. |

##### `Settings/` — Settings & Profile Editing
| File | Purpose |
|------|---------|
| `EditVaultView.swift` | **Active (Step 3.12).** Full-screen Edit Profile screen accessible from HomeView via `.fullScreenCover`. On appear, calls `VaultService.getVault()` to load existing vault data from `GET /api/v1/vault`, then creates a fresh `OnboardingViewModel` and populates all its properties (basic info, interests, dislikes, milestones, vibes, budgets, love languages) from the response. Displays a sectioned list of 7 `editSectionButton` cards (icon + title + subtitle + chevron), each opening the corresponding onboarding step view in a `.sheet(item: $activeSection)`. Uses `EditSection` enum (Identifiable, 7 cases) for sheet routing. Sheet content wraps the step view in `NavigationStack` with a "Done" dismiss button and injects the ViewModel via `.environment(vm)`. "Save" toolbar button calls `vm.buildVaultPayload()` and `VaultService.updateVault(_:)` (`PUT /api/v1/vault`). Handles 4 states: loading (spinner), error (retry button), content (sectioned list), saving (disabled toolbar). Success alert auto-dismisses the view. Private helpers: `parseMilestoneDate()` converts `"2000-MM-DD"` back to (month, day) ints; subtitle functions summarize each section's data. Holiday milestones matched back to `HolidayOption.allHolidays` by month/day comparison. |

##### `Recommendations/` — Choice-of-Three UI
| File | Purpose |
|------|---------|
| `RecommendationCard.swift` | **Active (Step 6.6).** Standalone SwiftUI view displaying a single recommendation card for the Choice-of-Three horizontal scroll. Layout: (1) **Hero section** (200pt tall, clipped) — `AsyncImage` with 3-phase handling (loading: gradient + spinner, success: resizable fill image, failure: gradient fallback). Fallback gradients are type-specific: pink/purple for gifts, blue/indigo for experiences, orange/pink for dates, with a large semi-transparent SF Symbol centered. Bottom gradient overlay (clear→black 40%) for badge readability. (2) **Type badge** — `Capsule` with `.ultraThinMaterial` fill positioned top-left over the hero, Lucide icon (gift/sparkles/heart) + uppercase label ("GIFT"/"EXPERIENCE"/"DATE"). (3) **Details section** (16pt padding) — Title (`.headline.weight(.semibold)`, 2-line limit, `fixedSize` vertical), merchant name (Lucide `store` icon + name in `Theme.textSecondary`, 1-line limit, hidden when nil/empty), description (`.subheadline`, 3-line limit, `Theme.textSecondary`, hidden when nil/empty). (4) **Bottom row** — Price badge (`Capsule` with `Theme.surfaceElevated` fill, 1pt `surfaceBorder` stroke; shows "Price varies" in `Theme.textTertiary` when `priceCents` is nil), "Select →" button (`Capsule` with `Theme.accent` fill, `.buttonStyle(.plain)`). (5) **Save/Share row (Step 6.6)** — HStack with two buttons below the price/Select row. Save button: Lucide `bookmark`/`bookmarkCheck` icon + "Save"/"Saved" label, toggles between default and accent-highlighted states based on `isSaved` property. Share button: Lucide `share2` icon + "Share" label in `Theme.textSecondary`. Both use `.buttonStyle(.plain)` and `Capsule` background with `Theme.surfaceElevated` fill. Properties: `isSaved: Bool`, `onSave: @MainActor @Sendable () -> Void`, `onShare: @MainActor @Sendable () -> Void`. **Price formatting:** `formattedPrice(cents:currency:)` converts integer cents to locale-aware currency strings via `NumberFormatter` with `.currency` style. Omits decimals for whole-dollar amounts (`maximumFractionDigits = 0` when `cents % 100 == 0`). Supports international currencies via `currencyCode`. Method is `internal` (not private) for unit test access. **Concurrency:** All closures typed as `@MainActor @Sendable () -> Void` for Swift 6 strict concurrency compliance. Card corner radius: 18pt (larger than 14pt home cards for premium feel). 6 `#Preview` variants (gift, experience with image URL, date with no price, minimal data, saved state, unsaved state). |
| `RecommendationsView.swift` | **Active (Step 6.6).** Full-screen SwiftUI view for the Choice-of-Three horizontal scroll. Presented as a `NavigationStack` with back button (Lucide `arrowLeft`) and "Recommendations" title. Four states: (1) **Loading** — centered `ProgressView` with "Generating recommendations..." text, shown during initial `generateRecommendations()` call. (2) **Error** — `alertCircle` icon, error message, and "Try Again" button that re-triggers generation. (3) **Empty** — `sparkles` icon with prompt to complete partner vault. (4) **Content** — page indicator dots at top, `TabView(.page(indexDisplayMode: .never))` with horizontal paging across up to 3 `RecommendationCard` components (each wrapped in `ScrollView` for tall cards), and a "Refresh" button at the bottom. Page indicator uses custom dots with scale animation on active page. **Step 6.3:** Added `.sheet(isPresented: $viewModel.showConfirmationSheet)` presenting `SelectionConfirmationSheet` with `.presentationDetents([.medium])`. Wired `onSelect` callback on each `RecommendationCard` to `viewModel.selectRecommendation(item)`. Contains `SelectionConfirmationSheet` struct — bottom sheet with type badge (SF Symbol + label), title, description, merchant + price row, location row, "Open in [Merchant]" confirm button, and "Cancel" button. Uses Lucide icons `store`, `mapPin`, `externalLink`. Helpers: `formattedPrice(cents:currency:)`, `typeIconSystemName`, `typeLabel`, `confirmButtonLabel`. **Step 6.4:** Added card exit/entry animations — `TabView` and page indicator use `.opacity(cardsVisible ? 1 : 0)` and `.scaleEffect(cardsVisible ? 1 : 0.85)` with `.animation(.easeInOut(duration: 0.3))`. Added refresh loading overlay — centered `ProgressView` with "Finding better options..." text shown in a `ZStack` over the `TabView` when `isRefreshing` is true, with `.transition(.opacity)`. Refresh button now calls `viewModel.requestRefresh()` (shows reason sheet) instead of direct refresh; disabled during `isRefreshing` or `!cardsVisible`. Added second `.sheet(isPresented: $viewModel.showRefreshReasonSheet)` presenting `RefreshReasonSheet` with `.presentationDetents([.medium])`. Contains `RefreshReasonSheet` struct — bottom sheet with "Why are you refreshing?" header and 5 rejection reason buttons: "Too expensive" (`arrow.up.circle`), "Too cheap" (`arrow.down.circle`), "Not their style" (`hand.thumbsdown`), "Already have something similar" (`doc.on.doc`), "Just show me different options" (`arrow.triangle.2.circlepath`). Each button is a full-width row with SF Symbol icon, label, and chevron in a `Theme.surface` rounded rectangle. Uses `.buttonStyle(.plain)`. **Step 6.6:** Wires `isSaved`, `onSave`, `onShare` callbacks into each `RecommendationCard` in the `TabView`. Injects `@Environment(\.modelContext)` and passes it to ViewModel via `viewModel.configure(modelContext:)` in `.task`. Four `#Preview` blocks: Loading, Gift confirmation, Experience with location, Refresh Reason Sheet. |
| `RecommendationsViewModel.swift` | **Active (Step 6.6).** `@MainActor @Observable` state container for the recommendations screen. Properties: `recommendations: [RecommendationItemResponse]` (current set of up to 3), `isLoading` (initial generation), `isRefreshing` (refresh in progress), `errorMessage`, `currentPage` (TabView selection). **Step 6.3 selection state:** `selectedRecommendation: RecommendationItemResponse?`, `showConfirmationSheet: Bool`. **Step 6.4 refresh reason state:** `showRefreshReasonSheet: Bool`, `cardsVisible: Bool` (defaults `true`, controls card opacity/scale for enter/exit animations). **Step 6.6 save/share state:** `savedRecommendationIds: Set<String>` (in-memory dedup set hydrated from SwiftData), `modelContext: ModelContext?` (injected via `configure(modelContext:)`). Methods: `generateRecommendations(occasionType:milestoneId:)` calls `RecommendationService.generateRecommendations()` and populates the array; `refreshRecommendations(reason:)` collects current recommendation IDs, calls `RecommendationService.refreshRecommendations()`, and replaces the array. Both methods guard against duplicate calls, reset `currentPage` to 0, and clear `errorMessage` before starting. **Step 6.3 methods:** `selectRecommendation(_:)` stores item and shows sheet; `confirmSelection()` records feedback (fire-and-forget), opens external URL via `UIApplication.shared.open()`, dismisses sheet; `dismissSelection()` clears state. **Step 6.4 methods:** `requestRefresh()` shows the refresh reason sheet, guarded against duplicate calls when `isRefreshing` or `!cardsVisible`; `handleRefreshReason(_ reason:)` orchestrates the full refresh flow — dismiss sheet → medium haptic → 300ms pause → set `cardsVisible = false` (exit animation) → 350ms pause → call `refreshRecommendations(reason:)` → set `cardsVisible = true` (entry animation) → success haptic. Uses `Task.sleep` for timing coordination between SwiftUI animations and state changes. **Step 6.6 methods:** `configure(modelContext:)` sets the context and calls `loadSavedIds()`; `isSaved(_:)` checks `savedRecommendationIds` set; `saveRecommendation(_:)` creates `SavedRecommendation` SwiftData object, inserts via modelContext, updates dedup set, records "saved" feedback to backend; `shareRecommendation(_:)` presents `UIActivityViewController` via root view controller with formatted message (title + merchant + price + URL), records "shared" feedback; `loadSavedIds()` fetches all `SavedRecommendation` objects and populates the dedup set. Dependency-injected `RecommendationService` via init parameter for testability. |

##### `Notifications/` — Notification History Feature
| File | Purpose |
|------|---------|
| `NotificationsView.swift` | **Active (Step 7.7).** Full Notification History screen presented as a `.sheet` from the Home screen's bell icon. `NavigationStack` with `Theme.backgroundGradient`, "Notifications" title, X dismiss button (Lucide `x`). Three states: (1) **Loading** — centered `ProgressView` during initial `loadHistory()`. (2) **Empty** — Lucide `bellRing` icon + "No notifications yet" message + guidance text. (3) **Notifications list** — `List` of `notificationRow()` components (`.listStyle(.plain)`, transparent background, hidden separators). Each row shows: left: milestone type SF Symbol icon in accent-tinted rounded rect (gift.fill/heart.fill/star.fill/calendar.badge.clock); center: milestone name (bold, 1-line) + unviewed accent dot (7pt Circle when `viewedAt == nil && status == "sent"`), days-before label + formatted date (secondary), status capsule badge (`statusBadge()` — green "Delivered" or red "Failed" with checkmark/xmark SF Symbol), recommendation count with Lucide `sparkles` icon; right: Lucide `chevronRight` if has recommendations. Tapping a row with `recommendationsCount > 0` calls `viewModel.selectNotification()`. Pull-to-refresh via `.refreshable`. **Recommendations sheet:** `.sheet` bound to `viewModel.showRecommendationsSheet`. Contains `NavigationStack` with milestone name title, X dismiss button. Four sub-states: loading spinner, error (exclamationmark.triangle + message), empty (Lucide sparkles + "No recommendations"), content (`ScrollView` of `recommendationCard()` components). Each card: type icon (gift.fill/sparkles/heart.fill/star.fill) in accent-tinted rect, title (bold, 2-line), merchant name + formatted price (caption), description (3-line), "View Details" external link button (opens URL via `UIApplication.shared.open()`). `.task { await viewModel.loadHistory() }` on appear. `.alert` for error messages. All colors use Theme constants. |
| `NotificationsViewModel.swift` | **Active (Step 7.7).** `@Observable @MainActor final class` managing notification history state and recommendation detail. **History state:** `isLoading` (initial load), `notifications: [NotificationHistoryItemResponse]` (display data), `errorMessage: String?` (alert). **Detail state:** `selectedNotification: NotificationHistoryItemResponse?`, `isLoadingRecommendations` (spinner in sheet), `milestoneRecommendations: [MilestoneRecommendationItemResponse]` (recommendation cards), `showRecommendationsSheet: Bool`, `recommendationsError: String?`. **Methods:** `loadHistory()` calls `NotificationHistoryService.fetchHistory()` and populates `notifications` array. `selectNotification(_:)` sets selected notification, shows sheet, calls `fetchMilestoneRecommendations(milestoneId:)`, marks notification as viewed (fire-and-forget via `service.markViewed()`), and creates a copy of the notification with `viewedAt` set for immediate UI feedback (removes unviewed dot without reload). `dismissRecommendations()` resets all detail state. **Helpers:** `formattedDate(_:)` parses ISO 8601 (with/without fractional seconds) and returns medium date + short time; `daysBeforeLabel(_:)` returns "X days before"; `milestoneTypeIcon(_:)` maps type to SF Symbol; `formattedPrice(cents:currency:)` converts integer cents to locale-aware currency string via `NumberFormatter`. Dependency-injected `NotificationHistoryService` via init parameter. |

##### `Onboarding/` — Partner Vault Onboarding Flow
| File | Purpose |
|------|---------|
| `OnboardingViewModel.swift` | `@Observable @MainActor` class managing all onboarding state. Also defines `CustomMilestone` struct (Identifiable, Sendable — name, month, day, recurrence) and `HolidayOption` struct (Identifiable, Sendable — id, displayName, month, day, iconName; static `allHolidays` with 5 US holidays). Contains `OnboardingStep` enum (9 cases: welcome through completion) with `title`, `isFirst`, `isLast`, `totalSteps`. Holds `currentStep`, `progress` (0.0–1.0), `canProceed` flag, `validationMessage` (computed, returns user-facing error string or nil), and all data properties for Steps 3.2–3.8 (partnerName, selectedInterests, selectedDislikes, selectedVibes, budget amounts, love languages, milestones incl. `customMilestones: [CustomMilestone]`). Provides `goToNextStep()`, `goToPreviousStep()` navigation methods, `daysInMonth()` / `clampDay()` static date helpers, and `validateCurrentStep()` centralized validation (switch on `currentStep` — `.basicInfo` checks name non-empty, `.interests` checks count == 5, `.dislikes` checks count == 5 AND `isDisjoint(with: selectedInterests)`, `.milestones` checks custom milestones have non-empty names, `.vibes` checks count >= 1, `.budget` checks max >= min for all three tiers, `.loveLanguages` checks both primary and secondary are non-empty, `default` returns `true` for placeholder steps). `validationMessage` mirrors the same switch with step-specific user-facing strings (e.g., "Pick at least 1 vibe to continue."). Navigation methods call `validateCurrentStep()` after every step change. Step views also call it via `.onAppear` / `.onChange` for real-time validation. Created by `OnboardingContainerView` and injected into environment — all step views share the same instance. |
| `OnboardingContainerView.swift` | Navigation shell for the 9-step onboarding flow. Owns `OnboardingViewModel` via `@State` and injects it into the SwiftUI environment. Displays: (1) animated progress bar at top with step title and "Step X of 9" counter, (2) current step view in center via `@ViewBuilder` switch, (3) validation error banner (red, slides up, auto-dismisses after 3s) when user taps Next on an invalid step, (4) Back/Next/Get Started buttons at bottom. All buttons use `.fixedSize(horizontal: true, vertical: false)` to prevent text wrapping, `.subheadline` font, height 44. Next button is always tappable — when `canProceed` is false, it shows the error banner from `viewModel.validationMessage` instead of advancing; tint dims to 40% opacity as a visual hint. Back button hidden on first step; "Get Started" replaces "Next" on last step. Error banner auto-clears on step change. Uses `.id(viewModel.currentStep)` for step identity and `.transition(.asymmetric(...))` for slide animations. Accepts `onComplete` closure called when user finishes onboarding. |

| Step View (in `Steps/`) | Step # | Purpose |
|--------------------------|--------|---------|
| `OnboardingWelcomeView.swift` | 1 | Welcome screen with Knot branding and checklist of vault sections (basics, interests, milestones, budget, love languages). Read-only informational step. |
| `OnboardingBasicInfoView.swift` | 2 | **Active (Step 3.2).** Partner basic info form with 4 sections: (1) Partner name `TextField` with `.givenName` content type, deferred "Required" validation hint via `@State hasInteractedWithName`, and `@FocusState` keyboard chaining (name → city → state → dismiss); (2) Relationship tenure — two `Picker(.menu)` controls for years (0–30) and months (0–11) using `Binding(get:set:)` to decompose/recompose `viewModel.relationshipTenureMonths`; (3) Cohabitation status `Picker(.segmented)` with contextual description text; (4) Location city/state `TextField`s with `.addressCity`/`.addressState` content types (optional). Calls `viewModel.validateCurrentStep()` on `.onAppear` and `.onChange(of: partnerName)`. Uses `@Bindable var vm = viewModel` in `body` for binding syntax, `Binding(get:set:)` in computed properties. `ScrollView` with `.scrollDismissesKeyboard(.interactively)`. |
| `OnboardingInterestsView.swift` | 3 | **Active (Step 3.3).** Dark-themed 3-column grid of visual interest cards with search bar. Each card (`InterestImageCard`, private struct) prefers an asset catalog image (`imageName(for:)` → `"Interests/interest-{slug}"` via `UIImage(named:)` nil check) rendered as a full-bleed `.resizable().aspectRatio(contentMode: .fill)` photo; falls back to a hue-rotated `LinearGradient` background with large semi-transparent SF Symbol icon when no image exists. Interest name at bottom-left with dark gradient overlay for text readability. Selected cards show a pink border + checkmark badge. Shake animation rejects 6th selection. Search bar filters 40 categories in real-time with clear button and empty-state message. Counter shows "X selected (Y more needed)" in pink. Uses `viewModel.selectedInterests` (Set<String>), `toggleInterest()` for add/remove logic, and `triggerShake()` with `DispatchQueue.main.asyncAfter` for animation. Static functions `cardGradient(for:)`, `iconName(for:)`, and `imageName(for:)` generate per-card visuals. `imageName(for:)` is also called by `OnboardingDislikesView` for consistent visuals. All colors use `Theme` constants. |
| `OnboardingDislikesView.swift` | 4 | **Active (Step 3.4).** Dark-themed 3-column card grid matching InterestsView visual style. Displays all 40 interest categories; interests already selected as likes in Step 3.3 appear grayed out with heart badge and `.disabled(true)`. User selects exactly 5 dislikes. Contains `DislikeImageCard` (private struct) with 4 visual states: unselected (photo or gradient), selected/disliked (pink border + checkmark), disabled/liked (flat gray `Color(white: 0.18)`, 50% opacity, heart badge — always gray regardless of image availability), shaking (6th attempt rejection). Prefers asset catalog images via `OnboardingInterestsView.imageName(for:)`, falls back to gradient + SF Symbol via `.cardGradient(for:)` and `.iconName(for:)`. Search bar, selection counter, and shake animation match the Interests screen. Calls `viewModel.validateCurrentStep()` via `.onAppear` and `.onChange(of: selectedDislikes)`. |
| `OnboardingMilestonesView.swift` | 5 | **Active (Step 3.5).** Full milestones input screen with 4 sections: (1) Birthday — required, month/day `Picker(.menu)` controls with `Binding(get:set:)` that auto-clamps day via `OnboardingViewModel.clampDay()` on month change, "Required" capsule badge, human-readable date below; (2) Anniversary — optional `Toggle` that reveals month/day pickers with `.opacity.combined(with: .move(edge: .top))` transition, wrapped in a `Theme.surface.opacity(0.5)` card; (3) Holiday Quick-Add — `VStack` of `HolidayChip` components (private struct) for 5 US holidays (Valentine's Day, Mother's Day, Father's Day, Christmas, New Year's Eve), each with SF Symbol icon, name, date, and `Lucide.circleCheck`/`circle` toggle indicator, selected state uses `Theme.accent.opacity(0.12)` background; (4) Custom Milestones — list of `CustomMilestone` entries with star icon, name, date, recurrence, X delete button, plus "Add Custom Milestone" dashed-border button that opens a `.sheet` with `NavigationStack` containing name `TextField`, month/day pickers, yearly/one-time segmented recurrence `Picker`, Cancel/Save toolbar. Reusable `monthPicker()` and `dayPicker()` private helpers used in both main view and sheet. Sheet uses `@State` local properties (not ViewModel) for temporary state, cleared via `resetCustomSheetState()`. 3 `#Preview` variants. |
| `OnboardingVibesView.swift` | 6 | **Active (Step 3.6).** Dark-themed 2-column grid of 8 visual vibe cards. Each card (`VibeCard`, private struct) has a hand-tuned `LinearGradient` background unique to its vibe aesthetic, a large semi-transparent Lucide icon watermark (offset upper-right), a small opaque Lucide icon above the name, the vibe display name (`.headline.weight(.bold)`), and a short description (`.caption`). Dark overlay gradient ensures text readability. Selected cards show pink border + checkmark badge + 1.02x scale. No maximum limit — all 8 vibes can be selected; minimum 1 required. Static functions `displayName(for:)`, `vibeDescription(for:)`, `vibeIcon(for:)`, and `vibeGradient(for:)` map `snake_case` vibe keys to display data. Lucide icons used: `gem`, `building2`, `trees`, `watch`, `penLine`, `sun`, `heart`, `compass`. Counter shows "X selected" with checkmark or "(pick at least 1)". Calls `viewModel.validateCurrentStep()` via `.onAppear` and `.onChange(of: selectedVibes)`. 3 `#Preview` variants. |
| `OnboardingBudgetView.swift` | 7 | **Active (Step 3.7).** Dark-themed budget tiers screen with 3 tier cards (Just Because, Minor Occasion, Major Milestone). Each card (`BudgetTierCard`, private struct) displays an accent-colored icon badge (`Lucide.coffee` / `Lucide.gift` / `Lucide.sparkles`), title/subtitle, a "Select all" link, and a 2-column `LazyVGrid` of multi-select preset range buttons (`BudgetRangeOption`, fileprivate struct). Users can select multiple ranges per tier — effective min/max is computed as `min(selected mins)` / `max(selected maxes)`. At least one range must stay selected. Each tier has 4 preset options (e.g., $5–$20, $20–$50, $50–$100, $100–$200 for Just Because). Selected state tracked via `viewModel.*Ranges` (`Set<String>` of range IDs like `"2000-5000"`). Dollar formatting via file-level `formatDollars()` function (avoids `@MainActor` isolation issues). `toggle()` helper uses `inout Set<String>`; `syncBudget()` recomputes effective min/max via closures. `.clipShape()` prevents button overflow outside card corners. 3 `#Preview` variants. |
| `OnboardingLoveLanguagesView.swift` | 8 | **Active (Step 3.8).** Dark-themed love language selection with 5 full-width cards in a `ScrollView`. Each card (`LoveLanguageCard`, private struct) displays a unique `LinearGradient` background, circular Lucide icon badge, display name (`.headline.weight(.bold)`), and contextual description (`.caption`). Two-step selection: first tap sets **Primary** (pink border, "PRIMARY" capsule badge, 1.02x scale), second tap on different card sets **Secondary** (muted pink border, "SECONDARY" badge). Badge is a `ZStack(alignment: .topTrailing)` overlay — completely independent of text layout so long names never wrap. `LoveLanguageSelectionState` (private `Equatable` enum: `.unselected`, `.primary`, `.secondary`) drives all visual states via `.animation(.easeInOut, value: selectionState)`. `selectLanguage()` handles 5 branches: tap primary clears both, tap secondary clears it, no primary sets primary, no secondary sets secondary, both set replaces secondary. Dynamic header subtitle guides through selection states. Status bar at bottom shows contextual progress. Personalized title with partner name from Step 3.2. Static functions `displayName(for:)`, `languageDescription(for:)`, `languageIcon(for:)`, `languageGradient(for:)` map `snake_case` keys to display data. Lucide icons: `messageCircle`, `heartHandshake`, `gift`, `clock`, `hand`. Calls `viewModel.validateCurrentStep()` via `.onAppear` and `.onChange(of: primaryLoveLanguage/secondaryLoveLanguage)`. 3 `#Preview` variants. |
| `OnboardingCompletionView.swift` | 9 | **Active (Step 3.9).** Scrollable completion screen with success header and comprehensive partner profile summary. Contains 6 `SummaryCard` sections: Partner Info (name, tenure, cohabitation, location), Interests & Dislikes (`CompactTag` pills in `FlowLayout`), Milestones (birthday, anniversary, holidays, custom — with computed "Next up: X in Y days" indicator using `nextUpcomingMilestone()`), Aesthetic Vibes (accent capsule pills with Lucide icons via `OnboardingVibesView.vibeIcon(for:)`/`.displayName(for:)`), Budget Tiers (3 rows with Lucide `coffee`/`gift`/`sparkles` icons and formatted dollar ranges), Love Languages (Primary/Secondary rows with Lucide icons via `OnboardingLoveLanguagesView.languageIcon(for:)`/`.displayName(for:)` and rank capsule badges). Private structs: `SummaryCard<Content: View>` (generic card container with icon + title header), `CompactTag` (capsule pill with `.accent`/`.muted` styles). File-level `formatDollars()` avoids `@MainActor` isolation. Formatting helpers: `formatTenure()`, `formatCohabitation()`, `formatMonthDay()`. "Get Started" button is in the container's navigation bar. 3 `#Preview` variants (Empty, Full Profile, Minimal Profile). |

#### `/Core` — Shared Utilities
| File | Purpose |
|------|---------|
| `Constants.swift` | App-wide constants: API URLs, Supabase configuration (`projectURL`, `anonKey`), validation rules, predefined categories (40 interests, 8 vibes, 5 love languages). |
| `NetworkMonitor.swift` | **Active (Step 4.1).** `@Observable @MainActor` class monitoring network connectivity via `NWPathMonitor` (from `Network` framework). Publishes `isConnected: Bool` updated on the main actor when the network path changes. Creates a dedicated `DispatchQueue` for the monitor's `pathUpdateHandler`. Starts monitoring immediately on `init()`, cancels on `deinit`. Used by `HomeView` to show the offline banner and disable interactive elements. Created as `@State` in `HomeView` — one instance per Home screen lifecycle. |
| `Theme.swift` | **App-wide design system (Step 3.3).** Centralizes all colors, gradients, and surfaces for the dark purple aesthetic. Contains: `backgroundGradient` (dark purple LinearGradient from `(0.10, 0.05, 0.16)` to `(0.05, 0.02, 0.10)`), `surface` / `surfaceElevated` / `surfaceBorder` (semi-transparent white at 8%/12%/12% opacity), `accent` (Color.pink), `textPrimary` / `textSecondary` / `textTertiary` (white at 100%/60%/35% opacity), and `progressTrack` / `progressFill`. All views MUST use `Theme` constants — never hardcode colors. |

Future files:
- `Extensions.swift` — Swift type extensions

#### `/Services` — Data & API Layer
| File | Status | Purpose |
|------|--------|---------|
| `SupabaseClient.swift` | **Active** | Singleton `SupabaseManager.client` initialized with `Constants.Supabase.projectURL` and `anonKey`. The Supabase Swift SDK automatically handles Keychain session storage and token refresh. Used by `AuthViewModel`, `VaultService`, and future service classes. |
| `VaultService.swift` | **Active (Step 3.12)** | `@MainActor` service for Partner Vault API operations. Four methods: (1) `createVault(_:)` — sends `POST /api/v1/vault` with full onboarding payload; handles 201 success, 401 auth, 409 duplicate, 422 validation, and network errors with typed `VaultServiceError` enum. (2) `getVault()` — sends `GET /api/v1/vault` to retrieve full vault data (all 6 tables); handles 200 success, 401 auth, 404 not found. Returns `VaultGetResponse`. (3) `updateVault(_:)` — sends `PUT /api/v1/vault` with full vault payload (same schema as create); handles 200 success, 401 auth, 404 not found, 422 validation. Returns `VaultUpdateResponse`. (4) `vaultExists()` — queries Supabase PostgREST directly (`partner_vaults?select=id&limit=1`) using the anon client (RLS-scoped); returns `Bool`. All HTTP methods use Bearer token auth via `getAccessToken()`, `URLSession.shared`, `JSONEncoder`/`JSONDecoder`, and differentiate network errors by `URLError.code`. Called by `OnboardingViewModel.submitVault()`, `AuthViewModel.listenForAuthChanges()`, and `EditVaultView`. |
| `APIClient.swift` | Planned | Generic HTTP client for backend API calls (future refactor) |
| `HintService.swift` | **Active (Step 4.6)** | `@MainActor` service for Hint Capture API operations. Three methods: (1) `createHint(text:source:)` — sends `POST /api/v1/hints` with hint text and source ("text_input" or "voice_transcription"); handles 201 success, 401 auth, 404 no vault, 422 validation (empty text, text too long), and network errors with typed `HintServiceError` enum (6 cases mirroring `VaultServiceError` pattern). (2) `listHints(limit:offset:)` — sends `GET /api/v1/hints?limit=N&offset=M` to retrieve hints in reverse chronological order; handles 200 success, 401 auth, 404 no vault. Returns `HintListResponse`. (3) `deleteHint(id:)` — sends `DELETE /api/v1/hints/{id}` to permanently delete a hint; handles 204 success, 401 auth, 404 not found (hint doesn't exist or belongs to another user). Uses Bearer token auth via `getAccessToken()`, `URLSession.shared`, `JSONEncoder`/`JSONDecoder`, `mapURLError()` for typed network error differentiation. Parses both FastAPI error formats (string detail + array detail). Called by `HomeViewModel.submitHint()`, `HomeViewModel.loadRecentHints()`, `HintsListViewModel.loadHints()`, and `HintsListViewModel.deleteHint()`. |
| `RecommendationService.swift` | **Active (Step 6.3)** | `@MainActor` service for Recommendation API operations. Three methods: (1) `generateRecommendations(occasionType:milestoneId:)` — sends `POST /api/v1/recommendations/generate` with occasion type and optional milestone ID; handles 200 success, 401 auth, 404 no vault, 422 validation, and network errors with typed `RecommendationServiceError` enum (6 cases mirroring `HintServiceError` pattern). Returns `RecommendationGenerateResponse`. (2) `refreshRecommendations(rejectedIds:reason:)` — sends `POST /api/v1/recommendations/refresh` with rejected recommendation IDs and rejection reason for exclusion filtering; same error handling. Returns `RecommendationRefreshResponse`. Both methods use 60-second timeout (longer than HintService's 30s) because the LangGraph AI pipeline involves multiple agent nodes. (3) **Step 6.3:** `recordFeedback(recommendationId:action:)` — sends `POST /api/v1/recommendations/feedback`; marked `@discardableResult` for fire-and-forget usage; 15-second timeout; expects 201 status code. Returns `RecommendationFeedbackResponse`. Uses Bearer token auth via `getAccessToken()`, `URLSession.shared`, `JSONEncoder`/`JSONDecoder`, `parseErrorMessage()` for both FastAPI error formats. Called by `RecommendationsViewModel`. |
| `NotificationHistoryService.swift` | **Active (Step 7.7)** | `@MainActor final class: Sendable` service for notification history API operations. Three methods: (1) `fetchHistory(limit:offset:)` — sends `GET /api/v1/notifications/history` with pagination params; handles 200 success, 401 auth, and generic server errors with typed `NotificationHistoryServiceError` enum (4 cases: noAuthSession, networkError, serverError, decodingError). Returns `NotificationHistoryResponse`. (2) `fetchMilestoneRecommendations(milestoneId:)` — sends `GET /api/v1/recommendations/by-milestone/{milestoneId}`; handles 200, 401, 404, server errors. Returns `MilestoneRecommendationsResponse`. (3) `markViewed(notificationId:)` — sends `PATCH /api/v1/notifications/{notificationId}/viewed`; fire-and-forget (catches all errors, logs to console, never throws). Uses Bearer token auth via `getAccessToken()` from `SupabaseManager.client.auth.session`. Follows `RecommendationService.swift` patterns: `mapURLError()` for typed `URLError` differentiation, `parseErrorMessage()` for both FastAPI error formats (string detail + array detail). 15-second timeout for fetch operations, 10-second for mark-viewed. Called by `NotificationsViewModel`. |
| `DeviceTokenService.swift` | **Active (Step 7.4)** | `@MainActor final class: Sendable` singleton for registering APNs device tokens with the backend. Uses `static let shared` because `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken` fires before the SwiftUI view hierarchy exists, making environment injection unavailable. One public method: `registerToken(_ token: String) async` — best-effort, catches all errors and logs them without surfacing to the user. Internally calls `sendToken()` which builds a `POST /api/v1/users/device-token` request with Bearer auth from Supabase session, sends `DeviceTokenPayload` (token + "ios" platform), and checks HTTP 200 response. Follows `HintService.swift` patterns: `getAccessToken()` from `SupabaseManager.client.auth.session`, `mapURLError()` for typed `URLError` differentiation, `parseErrorMessage()` for backend error response parsing. Error enum: `DeviceTokenServiceError` with 3 cases (noAuthSession, networkError, serverError). 30-second timeout. Called by `AppDelegate` on every app launch after successful APNs registration. |

#### `/Models` — Data Models
| File | Purpose |
|------|---------|
| `SyncStatus.swift` | Shared enum (`synced`, `pendingUpload`, `pendingDownload`) tracking local-to-Supabase sync state. Used by all `@Model` classes. Stored as raw `String` in SwiftData with a computed property for type-safe access. |
| `PartnerVaultLocal.swift` | SwiftData `@Model` mirroring `partner_vaults` table. Stores partner profile (name, tenure, cohabitation, location) locally. `remoteID` is nullable (NULL until synced with Supabase). |
| `HintLocal.swift` | SwiftData `@Model` mirroring `hints` table. Stores captured hints (text, source, isUsed). Deliberately excludes `hint_embedding` (vector(768)) — embeddings are server-side only for semantic search. |
| `MilestoneLocal.swift` | SwiftData `@Model` mirroring `partner_milestones` table. Stores milestones (type, name, date, recurrence, budgetTier) for Home screen countdown display. |
| `RecommendationLocal.swift` | SwiftData `@Model` mirroring `recommendations` table. Stores AI-generated recommendations for Choice-of-Three display. `description` renamed to `descriptionText` to avoid Swift protocol conflict. |
| `SavedRecommendation.swift` | **Active (Step 6.6).** SwiftData `@Model` for locally persisted saved recommendations. Stores a snapshot of recommendation data at save time: `recommendationId` (backend ID for deduplication), `recommendationType` (gift/experience/date), `title`, `descriptionText` (nullable), `externalURL`, `priceCents` (nullable, in cents), `currency` (defaults "USD"), `merchantName` (nullable), `imageURL` (nullable), `savedAt` (defaults to `Date()`). Surfaced on Home screen in the "Saved" section. Registered in `KnotApp.swift` model container schema. |
| `DTOs.swift` | **Active (Step 6.3).** Codable data transfer objects for backend API communication. **Vault request payloads:** `VaultCreatePayload` (full onboarding/edit submission with snake_case `CodingKeys` matching backend Pydantic `VaultCreateRequest` — used for both POST and PUT), `MilestonePayload` (milestone_type, name, date as `"2000-MM-DD"`, recurrence, budget_tier nullable), `BudgetPayload` (occasion_type, min/max amounts in cents, currency), `LoveLanguagesPayload` (primary + secondary). **Vault POST response:** `VaultCreateResponse` (vault_id, partner_name, summary counts, love_languages dict). **Vault GET response (Step 3.12):** `VaultGetResponse` (full vault data — all basic info fields, interests/dislikes as `[String]`, milestones as `[MilestoneGetResponse]`, vibes as `[String]`, budgets as `[BudgetGetResponse]`, love_languages as `[LoveLanguageGetResponse]`), `MilestoneGetResponse` (id, type, name, date, recurrence, budget_tier), `BudgetGetResponse` (id, occasion_type, min/max amounts, currency), `LoveLanguageGetResponse` (language, priority). **Vault PUT response (Step 3.12):** `VaultUpdateResponse` (mirrors VaultCreateResponse — vault_id, partner_name, summary counts, love_languages dict). **Hint DTOs (Step 4.2):** `HintCreatePayload` (hint_text, source with snake_case CodingKeys), `HintCreateResponse` (id, hint_text, source, is_used, created_at), `HintListResponse` (hints array + total count), `HintItemResponse` (same fields as HintCreateResponse — single hint in list). **Recommendation DTOs (Step 6.2):** `RecommendationGeneratePayload` (milestoneId nullable, occasionType), `RecommendationRefreshPayload` (rejectedRecommendationIds array, rejectionReason), `RecommendationGenerateResponse` (recommendations array, count, milestoneId nullable, occasionType), `RecommendationRefreshResponse` (recommendations array, count, rejectionReason), `RecommendationItemResponse` (Codable + Sendable + Identifiable — id, recommendationType, title, description nullable, priceCents nullable, currency, externalUrl, imageUrl nullable, merchantName nullable, source, location nullable, interestScore, vibeScore, loveLanguageScore, finalScore), `RecommendationLocationResponse` (city/state/country/address all nullable). **Feedback DTOs (Step 6.3):** `RecommendationFeedbackPayload` (recommendationId, action with snake_case CodingKeys), `RecommendationFeedbackResponse` (id, recommendationId, action, createdAt with snake_case CodingKeys). **Device Token DTO (Step 7.4):** `DeviceTokenPayload` (deviceToken, platform with snake_case CodingKeys — request-only, no response DTO needed since the service only checks HTTP status). **Notification History DTOs (Step 7.7):** `NotificationHistoryResponse` (notifications: array + total: Int), `NotificationHistoryItemResponse` (Identifiable — id, milestoneId, milestoneName, milestoneType, milestoneDate, daysBefore, status, sentAt nullable, viewedAt nullable, createdAt, recommendationsCount; CodingKeys for snake_case), `MilestoneRecommendationsResponse` (recommendations: array + count: Int + milestoneId), `MilestoneRecommendationItemResponse` (Identifiable — id, recommendationType, title, description nullable, externalUrl nullable, priceCents nullable, merchantName nullable, imageUrl nullable, createdAt; CodingKeys for snake_case). All structs conform to `Codable` + `Sendable` with snake_case `CodingKeys`. |

#### `/Components` — Reusable UI Components
Shadcn-inspired, reusable SwiftUI components.

| Component | Status | Purpose |
|-----------|--------|---------|
| `FlowLayout.swift` | **Active** | Custom `Layout` protocol implementation for wrapping flow (CSS `flex-wrap` equivalent). Arranges subviews left-to-right, wrapping to the next row when they exceed available width. Configurable `horizontalSpacing` and `verticalSpacing`. Created in Step 3.3 for chip grids; will be used by DislikesView (Step 3.4) and VibesView (Step 3.6). |
| `ChipView.swift` | Planned | Selectable tag/pill for interests and vibes |
| `CardView.swift` | Planned | Recommendation card with image, title, price |
| `ButtonStyles.swift` | Planned | Primary, secondary, and ghost button styles |
| `InputField.swift` | Planned | Text input with label and validation |
| `LoadingView.swift` | Planned | Loading spinner with optional message |

#### `/Resources` — Assets
| File | Purpose |
|------|---------|
| `Assets.xcassets/` | App icon, accent color, and image assets |
| `Assets.xcassets/Interests/` | **Namespaced folder group** (`provides-namespace: true`) containing 40 image sets for interest card backgrounds. Convention: `interest-{lowercased-hyphenated}` (e.g., `interest-travel`, `interest-board-games`). Each set holds a JPEG (~280x400px). Referenced in code as `"Interests/interest-travel"` via `OnboardingInterestsView.imageName(for:)`. Cards gracefully fall back to gradient + SF Symbol when an image set is empty. |
| `Colors.xcassets/` | Named colors for the design system |

### Test Targets

| Folder | Purpose |
|--------|---------|
| `KnotTests/` | Unit tests for business logic, services, and utilities. Contains `KnotTests.swift` (constants validation), `RecommendationCardTests.swift` (Step 6.1 — 12 tests: rendering with full/minimal/all-type/unknown-type data, price formatting for whole dollar/cents/GBP/zero/large amounts, select callback, long text truncation), and `RecommendationsViewTests.swift` (Steps 6.2–6.4 — 35 tests total: 12 DTO tests for generate/refresh/feedback encoding+decoding, 11 ViewModel tests for initial state + currentPage + selection state management + refresh reason state management (sheet visibility, guards during refresh/animation, cardsVisible toggle), 12 view rendering tests for RecommendationsView + SelectionConfirmationSheet (confirm/cancel callbacks, all types, location data) + RefreshReasonSheet (rendering, reason callback, all 5 reasons, dark scheme)). All test classes are `@MainActor` for Swift 6 concurrency compliance. |
| `KnotUITests/` | UI tests for critical user flows (onboarding, hint capture) |

---

## Backend (`backend/`)

```
backend/
├── app/
│   ├── __init__.py           # App package marker
│   ├── main.py               # FastAPI entry point, app factory, /health endpoint, router registration
│   ├── api/                  # Route handlers (one file per API domain)
│   │   ├── __init__.py
│   │   ├── vault.py          # POST/PUT/GET /api/v1/vault — Partner Vault CRUD
│   │   ├── hints.py          # POST/GET/DELETE /api/v1/hints — Hint capture & retrieval
│   │   ├── recommendations.py # POST /api/v1/recommendations — Generation, refresh, feedback & GET by-milestone (Step 7.7)
│   │   ├── notifications.py  # POST /api/v1/notifications/process + GET /history + PATCH /viewed (Step 7.7)
│   │   └── users.py          # POST/GET/DELETE /api/v1/users — Account management
│   ├── core/                 # Configuration & cross-cutting concerns
│   │   ├── __init__.py
│   │   ├── config.py         # App settings (API prefix, project name, env vars)
│   │   └── security.py       # Auth middleware — validates Supabase JWT Bearer tokens
│   ├── models/               # Pydantic schemas for request/response validation
│   │   ├── __init__.py
│   │   ├── vault.py          # Vault request/response models with validation constants
│   │   ├── hints.py          # Hint request/response models (Step 4.2) — HintCreateRequest (500-char validation), HintCreateResponse, HintListResponse, HintResponse
│   │   ├── recommendations.py # Recommendation models (Steps 5.9–6.3) — GenerateRequest, RefreshRequest, RecommendationFeedbackRequest (action Literal + rating validator), RecommendationFeedbackResponse, response models
│   │   └── users.py          # User models (Step 7.4) — DeviceTokenRequest (stripped, non-empty, max 200, platform validation), DeviceTokenResponse
│   ├── services/             # Business logic layer
│   │   ├── __init__.py
│   │   ├── embedding.py      # Vertex AI text-embedding-004 service (Step 4.4) — generates 768-dim embeddings for hints
│   │   └── integrations/     # External API clients
│   │       ├── __init__.py   # (Yelp, Ticketmaster, Amazon, Shopify, Firecrawl)
│   │       └── yelp.py       # Yelp Fusion API v3 service (Step 8.1) — business search with rate limiting & currency detection
│   ├── agents/               # LangGraph recommendation pipeline
│   │   ├── __init__.py       # Package marker
│   │   ├── state.py          # Recommendation pipeline state schema (Step 5.1) — 8 Pydantic models
│   │   ├── hint_retrieval.py # Semantic hint retrieval node (Step 5.2) — pgvector search + chronological fallback
│   │   ├── aggregation.py    # External API aggregation node (Step 5.3) — stub catalogs for 40 interests + 8 vibes
│   │   ├── filtering.py      # Semantic interest filtering node (Step 5.4) — dislike removal + interest scoring
│   │   ├── matching.py       # Vibe and love language matching node (Step 5.5) — vibe boost + love language scoring
│   │   ├── selection.py      # Diversity selection node (Step 5.6) — greedy 3-pick algorithm across price/type/merchant
│   │   ├── availability.py   # Availability verification node (Step 5.7) — URL checking + replacement from backup pool
│   │   └── pipeline.py       # Full LangGraph pipeline (Step 5.8) — composes all 6 nodes with conditional edges
│   └── db/                   # Database connection and repository pattern classes
│       ├── __init__.py
│       └── supabase_client.py # Lazy-initialized Supabase clients (anon + service role)
├── supabase/                  # Supabase project configuration
│   └── migrations/            # SQL migrations (run via SQL Editor or Supabase CLI)
│       ├── 00001_enable_pgvector.sql  # Enables pgvector extension for vector search
│       ├── 00002_create_users_table.sql  # Users table with RLS, triggers, and grants
│       ├── 00003_create_partner_vaults_table.sql  # Partner vaults with CHECK, UNIQUE, RLS, CASCADE
│       ├── 00004_create_partner_interests_table.sql  # Partner interests (likes/dislikes) with CHECK, UNIQUE, RLS, CASCADE
│       ├── 00005_create_partner_milestones_table.sql # Partner milestones with CHECK, trigger-based budget defaults, RLS, CASCADE
│       ├── 00006_create_partner_vibes_table.sql     # Partner aesthetic vibes with CHECK (8 values), UNIQUE, RLS, CASCADE
│       ├── 00007_create_partner_budgets_table.sql   # Partner budgets with CHECK (occasion_type, max>=min, min>=0), UNIQUE, RLS, CASCADE
│       ├── 00008_create_partner_love_languages_table.sql # Partner love languages with CHECK (language, priority), dual UNIQUE, RLS, CASCADE
│       ├── 00009_create_hints_table.sql                  # Hints with vector(768) embedding, HNSW index, match_hints() RPC, RLS, CASCADE
│       ├── 00010_create_recommendations_table.sql        # Recommendations with CHECK (type), price_cents >= 0, milestone FK SET NULL, RLS, CASCADE
│       ├── 00011_create_recommendation_feedback_table.sql # Recommendation feedback with CHECK (action, rating 1-5), dual FK (recommendation + user), direct RLS, CASCADE
│       ├── 00012_create_notification_queue_table.sql      # Notification queue with CHECK (days_before 14/7/3, status), DEFAULT pending, partial index, direct RLS, CASCADE
│       ├── 00013_add_device_token_to_users.sql           # Adds device_token TEXT + device_platform TEXT CHECK ('ios','android') to users, partial index on non-NULL tokens (Step 7.4)
│       ├── 00014_add_quiet_hours_to_users.sql           # Adds quiet_hours_start INT DEFAULT 22, quiet_hours_end INT DEFAULT 8 (CHECK 0-23), timezone TEXT nullable to users (Step 7.6)
│       └── 00015_add_viewed_at_to_notification_queue.sql # Adds viewed_at TIMESTAMPTZ nullable to notification_queue for tracking when user views recommendations (Step 7.7)
├── tests/                    # Backend test suite (pytest)
│   ├── __init__.py
│   ├── test_imports.py       # Verifies all dependencies are importable (11 tests)
│   ├── test_supabase_connection.py  # Verifies Supabase connectivity and pgvector (11 tests)
│   ├── test_supabase_auth.py # Verifies auth service and Apple Sign-In config (6 tests)
│   ├── test_auth_middleware.py # Verifies backend auth middleware — valid/invalid/missing tokens, malformed headers, health unprotected (14 tests)
│   ├── test_users_table.py   # Verifies users table schema, RLS, and triggers (10 tests)
│   ├── test_partner_vaults_table.py  # Verifies partner_vaults schema, constraints, RLS, cascades (15 tests)
│   ├── test_partner_interests_table.py  # Verifies partner_interests schema, CHECK/UNIQUE constraints, RLS, cascades (22 tests)
│   ├── test_partner_milestones_table.py # Verifies partner_milestones schema, budget tier trigger, RLS, cascades (28 tests)
│   ├── test_partner_vibes_table.py      # Verifies partner_vibes schema, CHECK/UNIQUE constraints, RLS, cascades (19 tests)
│   ├── test_partner_budgets_table.py    # Verifies partner_budgets schema, CHECK constraints (occasion_type, max>=min, min>=0), UNIQUE, RLS, cascades (27 tests)
│   ├── test_partner_love_languages_table.py # Verifies partner_love_languages schema, CHECK (language, priority), dual UNIQUE, RLS, update semantics, cascades (28 tests)
│   ├── test_hints_table.py               # Verifies hints schema, CHECK (source), vector(768) embedding, HNSW index, match_hints() RPC similarity search, RLS, cascades (30 tests)
│   ├── test_recommendations_table.py     # Verifies recommendations schema, CHECK (type, price>=0), milestone FK SET NULL, RLS, data integrity, cascades (31 tests)
│   ├── test_recommendation_feedback_table.py # Verifies recommendation_feedback schema, CHECK (action, rating 1-5), dual FK CASCADE, direct RLS, data integrity, cascades (27 tests)
│   ├── test_notification_queue_table.py  # Verifies notification_queue schema, CHECK (days_before, status), DEFAULT pending, status transitions, partial index, direct RLS, cascades (26 tests)
│   ├── test_vault_api.py       # Verifies POST /api/v1/vault — valid/minimal payloads, data in all 6 tables, Pydantic validation, auth required, duplicate 409 (40 tests)
│   ├── test_step_3_11_ios_integration.py  # Verifies iOS → backend flow: exact DTO payload, all 6 tables, PostgREST vault existence check, error handling (409/401), returning user session persistence (9 tests)
│   ├── test_vault_edit_api.py  # Verifies GET + PUT /api/v1/vault — full vault retrieval (all 6 tables, all fields), update persistence (each data type verified via GET after PUT), vault_id preserved, validation (same as POST), auth required, 404 handling, multiple sequential updates (32 tests)
│   ├── test_hint_submission_api.py  # Step 4.4: Verifies POST /api/v1/hints with embedding — valid submissions (201, DB storage), Vertex AI embedding generation (768-dim, conditional), graceful degradation (mocked), validation (422), auth (401), no vault (404), mocked embedding integration, utility unit tests, GET compatibility (35 tests: 31 pass + 4 skip without GCP)
│   ├── test_hint_deletion_api.py   # Step 4.6: Verifies DELETE /api/v1/hints/{hint_id} — successful deletion (204, DB removal, list exclusion), cross-user deletion blocked (404, hint persists), non-existent hint (404), double-delete (404), auth required (401), no vault (404) (12 tests)
│   ├── test_recommendation_state.py # Step 5.1: Verifies recommendation pipeline state schema — all 8 Pydantic models (BudgetRange, VaultBudget, VaultData, RelevantHint, MilestoneContext, LocationData, CandidateRecommendation, RecommendationState), instantiation, typing, defaults, Literal validation, JSON serialization, round-trip serialization, model_dump dict output (37 tests)
│   ├── test_hint_retrieval_node.py  # Step 5.2: Verifies hint retrieval LangGraph node — query text construction (milestone/no-milestone, all 3 occasion types, interest truncation), semantic search (similarity ordering, RelevantHint typing, max_count/threshold params, NULL embedding filtering, empty/nonexistent vault), chronological fallback (reverse ordering, max_count, field mapping, empty vault), full node (semantic path with mocked embedding, fallback path, empty vault, state update dict shape, query text verification), edge cases (anniversary/custom/holiday milestones, model round-trip) (29 tests)
│   ├── test_aggregation_node.py    # Step 5.3: Verifies external API aggregation LangGraph node — stub catalog coverage (all 40 interests + 8 vibes have entries, valid source/type values, positive prices), candidate construction (gift/experience builders, unique IDs, metadata provenance, location handling), gift fetch (known interests, budget filtering, unknown interests, multi-interest combination, source validation), experience fetch (known vibes, budget filtering, location attachment, null location, source validation), full node (candidate_recommendations key, CandidateRecommendation typing, required fields, budget range enforcement, gift+experience mix, interest/vibe matching, location propagation, missing location, unique IDs, reasonable count, cap at 20, state update compatibility, no error on normal run, error on empty results, source correctness, valid URLs, descriptions, scoring defaults), edge cases (just_because budget, single interest+vibe, currency passthrough, all 8 vibes, JSON round-trip) (54 tests)
│   ├── test_filtering_node.py     # Step 5.4: Verifies semantic filtering LangGraph node — normalize helper (lowercase, whitespace, idempotent), category matching (metadata matched_interest, title keyword, description keyword, case-insensitive, no-match, None description, partial word, vibe metadata ignored) (10 tests), scoring (dislike=-1, interest=+1, metadata bonus=+0.5, no match=0, multi-match accumulation, dislike priority over interest, experience neutral, title-only no bonus) (8 tests), dislike removal (metadata match, title match, multiple dislikes, experience description) (4 tests), interest ranking (interest > neutral, multi > single, score populated) (3 tests), top 9 limit (caps at 9, fewer survive, highest kept) (3 tests), full node (key present, typing, state update compatible, field preservation, mixed types, no error, unique IDs) (7 tests), edge cases (empty input, all filtered → error, neutral kept, single survivor, description-only dislike, deterministic ordering, constant=9) (7 tests), aggregation integration (realistic mix, title boost, JSON round-trip) (3 tests) (48 tests)
│   ├── test_selection_node.py    # Step 5.6: Verifies diversity selection LangGraph node — price tier classification (low/mid/high, boundaries, None, zero range, narrow range) (10 tests), diversity scoring (empty selected, all different=3, same everything=0, single-dimension differences, multi-selected, None merchant, case-insensitive) (9 tests), full node (exact count=3, first=highest score, type/merchant/price diversity, input immutability, return key) (7 tests), spec tests (price span, gift+experience, unique merchants) (3 tests), edge cases (empty/1/2/3 candidates, all-same type/merchant/price, None prices, tiebreaker) (9 tests), state compatibility (update, key isolation, pool preservation) (3 tests) (41 tests)
│   ├── test_availability_node.py # Step 5.7: Verifies availability verification LangGraph node — URL checking (200/301/404/500, 405→GET fallback, timeout, connection error, HTTP error) (9 tests), backup candidates (exclusion, sorting, all excluded, empty pool) (4 tests), full node (pass-through, replacement, cascading replacement, ID reuse prevention, max attempts, return key) (6 tests), spec tests (invalid URL replaced, all URLs verified) (2 tests), edge cases (empty input, all unavailable, single candidate, partial results, empty pool, immutability) (6 tests), state compatibility (update, filtered preservation, field integrity) (3 tests), constants (timeout, attempts, status range) (5 tests) (35 tests)
│   ├── test_pipeline.py        # Step 5.8: Verifies full LangGraph recommendation pipeline — graph structure (6 nodes, compilable, cached) (5 tests), conditional edges (aggregation/filtering check routing) (4 tests), full pipeline (returns 3, no error, intermediate state, required fields, interest/vibe matching, budget adherence, browsing mode, vault preservation, scoring) (9 tests), error handling (aggregation empty, filtering empty, availability partial) (3 tests), convenience runner (dict return, final_three, error state) (3 tests), spec requirements (5 tests), node ordering (4 tests), diversity/scoring (merchant diversity, type validity, score monotonicity) (3 tests), state compatibility (all keys, reconstruction, error reconstruction) (3 tests) (39 tests)
│   ├── test_recommendations_api.py  # Step 5.9: Verifies POST /api/v1/recommendations/generate — model validation (request/response Pydantic schemas, occasion_type Literal, optional fields) (6 tests), budget range helper (matching budget, fallback defaults, currency preservation) (5 tests), generate endpoint (200 response, 3 recommendations, required fields, scoring, occasion/milestone echo, browsing mode, DB storage, vault_id, DB IDs, location) (11 tests), auth & validation (401 no token, 401 invalid, 404 no vault, 422 invalid/missing occasion, 404 milestone not found) (6 tests), pipeline errors (exception → 500, error state → 500, empty → 500, partial → 200) (4 tests), pipeline state verification (vault_data, interests, vibes, love_languages, budget_range, milestone_context, browsing, location) (8 tests), occasion types (all 3 types produce valid responses) (3 tests) (43 tests)
│   ├── test_refresh_api.py          # Step 5.10: Verifies POST /api/v1/recommendations/refresh — model validation (RecommendationRefreshRequest/Response Pydantic schemas, rejection_reason Literal, non-empty list validator) (5 tests), exclusion filters (price tier classification low/mid/high, show_different title exclusion, too_expensive/too_cheap price tier filtering, not_their_style vibe metadata exclusion, already_have_similar merchant+type exclusion) (6 tests), refresh endpoint (200 response, 3 recommendations, required fields, rejection_reason echo, DB storage, feedback storage with action='refreshed') (6 tests), auth & validation (401 no token, 401 invalid token, 404 no vault, 404 no recommendations found, 422 empty rejected list, 422 invalid rejection reason) (6 tests), pipeline errors (exception → 500, error state → 500) (2 tests), all rejection reasons (parametrized — all 5 reasons produce valid responses) (5 tests) (30 tests)
│   ├── test_device_token_api.py     # Step 7.4: Verifies POST /api/v1/users/device-token — valid registration (200, default platform "ios", explicit "android") (3 tests), token update ("updated" status on second registration) (1 test), database storage (token in DB, second replaces first, initial NULL) (3 tests), validation errors (empty token, whitespace-only, invalid platform, missing field, too long — all 422) (5 tests), auth required (no header 401, invalid token 401) (2 tests), module imports (models, router, app registration, request validation, default platform, response model) (6 tests) (20 tests)
│   ├── test_dnd_quiet_hours.py      # Step 7.6: Verifies DND quiet hours logic — is_in_quiet_hours (11pm quiet, 9am not, 10pm boundary quiet, 8am boundary not, 3am quiet, noon not, same-day range, same-day outside, disabled) (9 tests), delivery time (11pm→8am next day, 3am→8am same day, UTC output) (3 tests), timezone inference (TX→Chicago, CA→LA, NY→NY, HI→Honolulu, non-US fallback, None state, case-insensitive, None country) (8 tests), get_user_timezone (explicit priority, vault inference, fallback, invalid falls back) (4 tests), check_quiet_hours DB integration (user in quiet hours, user not found, vault tz inference) (3 tests), webhook DND integration (rescheduled during quiet hours, delivered outside, DND failure graceful degradation, QStash publish params, stays pending) (5 tests), module imports (dnd exports, rescheduled status, constants) (3 tests) (35 tests)
│   └── test_notification_history.py # Step 7.7: Verifies notification history endpoints — TestNotificationHistoryEndpoint (empty history 200, sent notifications with milestone metadata, deleted milestone handling, auth required) (4 tests), TestMarkViewedEndpoint (sets viewed_at timestamp, 404 for non-existent, auth required) (3 tests), TestMilestoneRecommendationsEndpoint (returns stored recommendations, empty for no recommendations, 404 for no vault, auth required) (4 tests), TestNotificationHistoryIntegration (full history flow with real Supabase, milestone recommendations, mark viewed, pagination) (4 tests), TestModuleImports (model imports, router endpoint registration for history/viewed/by-milestone, response defaults) (6 tests) (21 tests)
├── venv/                     # Python 3.13 virtual environment (gitignored)
├── requirements.txt          # Python dependencies (all packages for MVP)
├── pyproject.toml            # Pytest configuration (asyncio mode, warning filters)
├── .env.example              # Template for environment variables (safe to commit)
├── .env                      # Actual secrets (gitignored, NEVER commit)
└── .gitignore                # Excludes .env, __pycache__, venv, IDE files
```

### Entry Point (`app/main.py`)

| Symbol | Purpose |
|--------|---------|
| `app` | The FastAPI application instance. Title: "Knot API", version: "0.1.0". |
| `vault_router` | Imported from `app.api.vault` and registered via `app.include_router(vault_router)`. Provides `POST /api/v1/vault`, `GET /api/v1/vault`, `PUT /api/v1/vault`. |
| `hints_router` | **Added in Step 4.2, updated Step 4.6.** Imported from `app.api.hints` and registered via `app.include_router(hints_router)`. Provides `POST /api/v1/hints`, `GET /api/v1/hints`, `DELETE /api/v1/hints/{hint_id}`. |
| `recommendations_router` | **Added in Step 5.9, updated Step 5.10.** Imported from `app.api.recommendations` and registered via `app.include_router(recommendations_router)`. Provides `POST /api/v1/recommendations/generate`, `POST /api/v1/recommendations/refresh`. |
| `users_router` | **Added in Step 7.4.** Imported from `app.api.users` and registered via `app.include_router(users_router)`. Provides `POST /api/v1/users/device-token`. |
| `health_check()` | `GET /health` — Returns `{"status": "ok"}`. Unprotected. Used by deployment platforms for uptime monitoring. |
| `get_current_user()` | `GET /api/v1/me` — **Protected** endpoint that returns `{"user_id": "<uuid>"}`. Uses `Depends(get_current_user_id)` to validate the Bearer token. Serves as a "who am I" endpoint and auth middleware verification route. Added in Step 2.5. |

API routers from `app/api/` are registered here via `app.include_router()`. Currently registered: `vault_router`, `hints_router`, `recommendations_router`, `notifications_router`, `users_router`.

### Route Handlers (`app/api/`)

Each file defines an `APIRouter` with a URL prefix and tag.

| File | Prefix | Status | Responsibility |
|------|--------|--------|----------------|
| `vault.py` | `/api/v1/vault` | **Active (Step 3.12)** | Three endpoints: (1) `POST` — Accepts full onboarding payload, validates with Pydantic, inserts into 6 tables. Returns 201/409/422. (2) `GET` — Loads user's vault from all 6 tables, separates interests into likes/dislikes, returns milestones/budgets with DB `id`s, love languages with priority. Returns 200/404. (3) `PUT` — Accepts same payload as POST, uses "replace all" strategy (update vault row, delete + re-insert all child rows), preserves vault_id. Returns 200/404/422. All endpoints use `get_service_client()` (bypasses RLS) with user identity validated by auth middleware. Private helper `_cleanup_vault()` handles partial failure cleanup for POST. |
| `hints.py` | `/api/v1/hints` | **Active (Step 4.6)** | Three endpoints: (1) `POST` — Validates hint text (non-empty, ≤500 chars via Pydantic `@field_validator`), looks up user's vault_id from `partner_vaults`, generates 768-dim embedding via `generate_embedding()` from `app.services.embedding` (Vertex AI `text-embedding-004`, async via `asyncio.to_thread()`), formats via `format_embedding_for_pgvector()`, inserts into `hints` table. If embedding generation fails or Vertex AI is unconfigured, hint is still saved with `hint_embedding = NULL` (graceful degradation). Logs embedding status via `logging.getLogger`. Returns 201/404/422/500. (2) `GET` — Lists hints in reverse chronological order (`ORDER BY created_at DESC`), selects display columns only (excludes `hint_embedding`), supports `limit`/`offset` pagination via Query params, returns total count via `count="exact"`. Returns 200/404. (3) `DELETE /{hint_id}` — Validates the hint exists and belongs to the authenticated user's vault (vault_id ownership check), then hard-deletes the hint from the database. Returns 404 (not 403) for unauthorized access to prevent information leakage. Returns 204/404/500. All endpoints use `get_service_client()` with auth via `get_current_user_id`. |
| `recommendations.py` | `/api/v1/recommendations` | **Active (Step 5.10, 7.7)** | Three endpoints: (1) `POST /generate` — Accepts `RecommendationGenerateRequest` (occasion_type + optional milestone_id), loads the user's vault from all 6 tables (interests split into likes/dislikes, vibes, budgets mapped to `VaultBudget`, love languages parsed into primary/secondary), determines budget range via `_find_budget_range()` (matches occasion_type or falls back to defaults: just_because $20–50, minor_occasion $50–150, major_milestone $100–500), optionally loads milestone context (validates vault ownership), builds `RecommendationState`, runs `run_recommendation_pipeline()` from Step 5.8, stores 3 results in `recommendations` table (non-fatal on failure), returns `RecommendationGenerateResponse` with DB-generated UUIDs, scoring metadata, and optional location data. Returns 200/401/404/422/500. (2) `POST /refresh` — Accepts `RecommendationRefreshRequest` (rejected_recommendation_ids + rejection_reason enum), loads rejected recommendations from DB, stores feedback with `action='refreshed'` in `recommendation_feedback` table, re-runs the full pipeline, applies exclusion filters based on rejection reason (`too_expensive`: exclude candidates at/above rejected price tier; `too_cheap`: exclude at/below; `not_their_style`: exclude matching vibe metadata; `already_have_similar`: exclude same merchant+type combos; `show_different`: exclude by title match only), stores new results, returns `RecommendationRefreshResponse`. Returns 200/401/404/422/500. **Shared helpers:** `_build_response_items(candidates, db_result)` builds response items with DB-generated UUIDs (used by both endpoints), `_classify_price_tier(price_cents, budget_range)` splits budget into low/mid/high thirds, `_apply_exclusion_filters(candidates, rejected_recs, rejection_reason, budget_range)` applies reason-specific filtering with title-based exclusion as the baseline for all reasons. Uses `get_service_client()` with auth via `get_current_user_id`. **Step 7.7:** `GET /by-milestone/{milestone_id}` — authenticated via `Depends(get_current_user_id)`, looks up user's vault_id, queries `recommendations` WHERE vault_id AND milestone_id, returns up to 10 pre-generated recommendations (read-only, no pipeline execution). Returns `MilestoneRecommendationsResponse`. Returns 200/401/404. |
| `notifications.py` | `/api/v1/notifications` | **Active (Step 7.1, 7.3, 7.5, 7.6, 7.7)** | QStash webhook endpoint for processing scheduled notifications plus user-facing history endpoints. Three endpoints: `POST /process` — receives webhook calls from Upstash QStash, reads raw request body for signature verification, validates `Upstash-Signature` JWT header via `verify_qstash_signature()` (returns 401 on failure), parses `NotificationProcessRequest` payload (notification_id, user_id, milestone_id, days_before), looks up the `notification_queue` entry via service client, skips already-processed notifications (returns `status: "skipped"` for sent/failed/cancelled). Step 7.3: generates recommendations via `run_recommendation_pipeline()` and stores in DB. Step 7.6: calls `check_quiet_hours(user_id)` — if quiet, republishes to QStash with `not_before` = next delivery time and returns `status: "rescheduled"` (notification stays `pending`). Step 7.5: delivers APNs push via `deliver_push_notification()`. Updates pending notifications to `status: "sent"` with `sent_at` timestamp. Does NOT use `get_current_user_id` auth dependency — authentication is via QStash signature, not user Bearer tokens. Returns `NotificationProcessResponse` (status, notification_id, message, recommendations_generated, push_delivered). Returns 200/401/404/422/500. **Step 7.7:** `GET /history` — authenticated via `Depends(get_current_user_id)`, queries `notification_queue` WHERE user_id AND status IN ('sent', 'failed'), joins milestone metadata from `partner_milestones` (graceful "Deleted Milestone" fallback), counts recommendations per milestone from `recommendations` table, supports `limit`/`offset` pagination (defaults 50/0), returns `NotificationHistoryResponse`. `PATCH /{notification_id}/viewed` — authenticated, validates user ownership via user_id filter, sets `viewed_at` timestamp, returns 200/404. |
| `users.py` | `/api/v1/users` | **Active (Step 7.4)** | One endpoint: `POST /device-token` — Accepts `DeviceTokenRequest` (device_token string, platform "ios"/"android"), validates the authenticated user exists in the `users` table via `get_service_client()`, upserts `device_token` and `device_platform` columns. Returns `DeviceTokenResponse` with `status` of "registered" (first time, previous token was NULL) or "updated" (token changed). Uses `get_current_user_id` dependency for Bearer token auth. Returns 200/401/404/422/500. Future: data export (GDPR) and account deletion. |

### Configuration (`app/core/`)

| File | Purpose |
|------|---------|
| `config.py` | Loads environment variables from `.env` via `python-dotenv`. Exposes `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS`, and future API keys. **QStash vars (Step 7.1):** `UPSTASH_QSTASH_TOKEN`, `UPSTASH_QSTASH_URL` (defaults to `https://qstash.upstash.io`), `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY`. **APNs vars (Step 7.5):** `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY_PATH` (filesystem path to .p8 key), `APNS_BUNDLE_ID` (app bundle identifier for apns-topic header), `APNS_USE_SANDBOX` (bool, defaults to `true`). Provides `validate_supabase_config()` to check required Supabase vars, `validate_vertex_ai_config()` / `is_vertex_ai_configured()` for Vertex AI, `validate_qstash_config()` / `is_qstash_configured()` for QStash, and `validate_apns_config()` / `is_apns_configured()` for APNs (all non-fatal, return `bool`). |
| `security.py` | **Auth middleware (Step 2.5).** Exports `get_current_user_id` — a FastAPI dependency that extracts the Bearer token from the `Authorization` header via `HTTPBearer(auto_error=False)`, validates it against Supabase Auth's `/auth/v1/user` endpoint using `httpx.AsyncClient`, and returns the authenticated user's UUID string. Raises `HTTPException(401)` with `WWW-Authenticate: Bearer` header for all failure cases: missing token, invalid/expired token, network errors, and malformed responses. Uses a private `_get_apikey()` helper with lazy import of `SUPABASE_ANON_KEY` to avoid circular dependencies. Usage: `async def route(user_id: str = Depends(get_current_user_id))`. |

### Data Layer (`app/models/`, `app/db/`)

| Folder/File | Purpose |
|-------------|---------|
| `models/` | Pydantic models for API request/response validation. Ensures strict schema adherence (e.g., exactly 5 interests, valid vibe tags, ≤500 char hints). |
| `models/vault.py` | **Active (Step 3.12).** Vault request/response schemas. **Constants:** `VALID_INTEREST_CATEGORIES` (40), `VALID_VIBE_TAGS` (8), `VALID_LOVE_LANGUAGES` (5) — `set[str]` mirroring DB CHECK constraints. **Request sub-models:** `MilestoneCreate` (`@model_validator` requiring budget_tier for custom), `BudgetCreate` (`@model_validator` enforcing max >= min >= 0), `LoveLanguagesCreate` (`@model_validator` enforcing different primary/secondary). **Main request:** `VaultCreateRequest` — used for both POST and PUT — field validators for counts (5/5/3, ≥1), predefined list membership, uniqueness, birthday requirement, cross-field `@model_validator` preventing interest/dislike overlap. **POST response:** `VaultCreateResponse` (vault_id, summary counts). **GET response (Step 3.12):** `VaultGetResponse` (full vault data from all 6 tables), `MilestoneResponse` (id, type, name, date, recurrence, budget_tier), `BudgetResponse` (id, occasion_type, min/max, currency), `LoveLanguageResponse` (language, priority). **PUT response (Step 3.12):** `VaultUpdateResponse` (mirrors VaultCreateResponse). |
| `models/hints.py` | **Active (Step 4.2).** Hint request/response schemas. **Constants:** `MAX_HINT_LENGTH = 500`. **Request:** `HintCreateRequest` — `hint_text` (str, `@field_validator` strips whitespace, rejects empty, enforces ≤500 chars), `source` (str, default `"text_input"`). **Responses:** `HintResponse` (id, hint_text, source, is_used, created_at), `HintCreateResponse` (same fields — returned on successful creation), `HintListResponse` (hints: list[HintResponse], total: int — for paginated list endpoint). |
| `models/recommendations.py` | **Active (Step 5.10).** Recommendation request/response schemas. **Generate request:** `RecommendationGenerateRequest` — `milestone_id` (optional str), `occasion_type` (Literal `just_because\|minor_occasion\|major_milestone`). **Refresh request:** `RecommendationRefreshRequest` — `rejected_recommendation_ids` (list[str], `@field_validator` enforces non-empty), `rejection_reason` (Literal `too_expensive\|too_cheap\|not_their_style\|already_have_similar\|show_different`). **Shared responses:** `LocationResponse` (optional city/state/country/address for experience/date recs), `RecommendationItemResponse` (id, recommendation_type Literal `gift\|experience\|date`, title, optional description/price_cents/image_url/merchant_name, currency default "USD", external_url, source, optional LocationResponse, 4 scoring floats: interest_score/vibe_score/love_language_score/final_score all default 0.0). **Generate response:** `RecommendationGenerateResponse` (recommendations: list[RecommendationItemResponse], count: int, optional milestone_id, occasion_type). **Refresh response:** `RecommendationRefreshResponse` (recommendations: list[RecommendationItemResponse], count: int, rejection_reason: str). |
| `models/notifications.py` | **Active (Step 7.1, updated 7.3, 7.5, 7.7).** Notification webhook request/response schemas plus notification history models. **Request:** `NotificationProcessRequest` — `notification_id` (str, UUID of notification_queue entry), `user_id` (str), `milestone_id` (str), `days_before` (int, 14/7/3). **Response:** `NotificationProcessResponse` — `status` (str: 'processed'/'skipped'/'failed'), `notification_id` (str), `message` (str, human-readable description), `recommendations_generated` (int, default 0 — Step 7.3), `push_delivered` (bool, default False — Step 7.5, True when APNs push was successfully accepted). **Step 7.7 history models:** `NotificationHistoryItem` (id, milestone_id, milestone_name, milestone_type, milestone_date, days_before, status, sent_at nullable, viewed_at nullable, created_at, recommendations_count default 0), `NotificationHistoryResponse` (notifications: list[NotificationHistoryItem], total: int default 0), `MilestoneRecommendationItem` (id, recommendation_type, title, description nullable, external_url nullable, price_cents nullable, merchant_name nullable, image_url nullable, created_at), `MilestoneRecommendationsResponse` (recommendations: list[MilestoneRecommendationItem], count: int default 0, milestone_id). |
| `models/users.py` | **Active (Step 7.4).** Device token request/response schemas. **Request:** `DeviceTokenRequest` — `device_token` (str, `@field_validator` strips whitespace, rejects empty, enforces ≤200 chars), `platform` (str, default `"ios"`, `@field_validator` validates "ios"/"android"). **Response:** `DeviceTokenResponse` — `status` (str: "registered"/"updated"), `device_token` (str), `platform` (str). |
| `db/` | Database connection and repository pattern classes. |
| `db/supabase_client.py` | Provides two lazy-initialized Supabase clients: `get_supabase_client()` uses the anon key (respects RLS for user-scoped queries) and `get_service_client()` uses the service_role key (bypasses RLS for admin/background operations). Also provides `test_connection()` to verify database connectivity. |

### Supabase Migrations (`supabase/migrations/`)

SQL migration files to be run in the Supabase SQL Editor or via `supabase db push`.

| File | Purpose |
|------|---------|
| `00001_enable_pgvector.sql` | Enables the `vector` extension (pgvector) required for hint embedding storage and similarity search. Must be run before creating any tables with `vector(768)` columns. |
| `00002_create_users_table.sql` | Creates `public.users` table (id, email, created_at, updated_at) linked to `auth.users` via FK with CASCADE delete. Enables RLS with SELECT/UPDATE/INSERT policies enforcing `auth.uid() = id`. Creates two trigger functions: `handle_updated_at()` (reusable, auto-updates timestamp on row changes) and `handle_new_user()` (SECURITY DEFINER, auto-creates profile on auth signup). Grants permissions to `authenticated` and `anon` roles. |
| `00003_create_partner_vaults_table.sql` | Creates `public.partner_vaults` table (id, user_id, partner_name, relationship_tenure_months, cohabitation_status, location_city, location_state, location_country, created_at, updated_at). `user_id` is UNIQUE (one vault per user) with FK CASCADE to `public.users`. CHECK constraint on `cohabitation_status` for 3 valid enum values. `location_country` defaults to `'US'`. Reuses `handle_updated_at()` trigger from migration 00002. RLS policies enforce `auth.uid() = user_id` for all 4 operations (SELECT, INSERT, UPDATE, DELETE). |
| `00004_create_partner_interests_table.sql` | Creates `public.partner_interests` table (id, vault_id, interest_type, interest_category, created_at). Two CHECK constraints: `interest_type` for 'like'/'dislike', `interest_category` for 40 predefined categories. `UNIQUE(vault_id, interest_category)` prevents duplicate categories and blocks same interest as both like and dislike. FK CASCADE to `partner_vaults`. RLS policies use subquery to `partner_vaults` to check ownership via `auth.uid() = user_id`. Index on `vault_id` for fast lookups. "Exactly 5 likes + 5 dislikes" enforced at application layer, not database. |
| `00005_create_partner_milestones_table.sql` | Creates `public.partner_milestones` table (id, vault_id, milestone_type, milestone_name, milestone_date, recurrence, budget_tier, created_at). Three CHECK constraints: `milestone_type` for 4 types (birthday/anniversary/holiday/custom), `recurrence` for yearly/one_time, `budget_tier` for 3 tiers. Creates `handle_milestone_budget_tier()` BEFORE INSERT trigger that auto-sets budget_tier when not provided: birthday/anniversary → major_milestone, holiday → minor_occasion, custom → must be explicit (NULL rejected by NOT NULL). No UNIQUE constraint on (vault_id, milestone_type) — multiple milestones of same type allowed (e.g., multiple holidays). FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. |
| `00006_create_partner_vibes_table.sql` | Creates `public.partner_vibes` table (id, vault_id, vibe_tag, created_at). CHECK constraint on `vibe_tag` for 8 valid aesthetic values: quiet_luxury, street_urban, outdoorsy, vintage, minimalist, bohemian, romantic, adventurous. `UNIQUE(vault_id, vibe_tag)` prevents duplicate vibes per vault (same deduplication pattern as `partner_interests`). No trigger functions needed — vibes are simple tag storage with no computed defaults. "Minimum 1, maximum 4 vibes per vault" enforced at API layer, not database. FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. |
| `00007_create_partner_budgets_table.sql` | Creates `public.partner_budgets` table (id, vault_id, occasion_type, min_amount, max_amount, currency, created_at). CHECK constraint on `occasion_type` for 3 budget tiers: just_because, minor_occasion, major_milestone. Two cross-column CHECK constraints: `max_amount >= min_amount` (prevents invalid ranges) and `min_amount >= 0` (prevents negative amounts). Amounts stored as **integers in cents** (e.g., 2000 = $20.00) to avoid floating-point precision issues. `UNIQUE(vault_id, occasion_type)` ensures one budget per occasion type per vault. `currency` defaults to `'USD'` — international users can override. No trigger functions needed — budgets are direct value storage. "Exactly 3 tiers per vault" enforced at API layer, not database. FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. |
| `00008_create_partner_love_languages_table.sql` | Creates `public.partner_love_languages` table (id, vault_id, language, priority, created_at). CHECK constraint on `language` for 5 valid values: words_of_affirmation, acts_of_service, receiving_gifts, quality_time, physical_touch. CHECK constraint on `priority` for values 1 (primary) and 2 (secondary) only. **Dual UNIQUE constraint strategy:** `UNIQUE(vault_id, priority)` prevents duplicate priorities per vault (at most one primary, one secondary), and `UNIQUE(vault_id, language)` prevents the same language from being both primary and secondary. Combined with the priority CHECK constraint, the maximum is exactly 2 rows per vault — a third row is impossible because no valid priority slot remains. No trigger functions needed. "Both primary and secondary must exist" minimum cardinality enforced at API layer, not database. FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. |
| `00009_create_hints_table.sql` | Creates `public.hints` table (id, vault_id, hint_text, hint_embedding, source, created_at, is_used). **First table with a pgvector column:** `hint_embedding vector(768)` stores embeddings from Vertex AI `text-embedding-004`. Column is **nullable** for resilience (hints can be stored even if embedding generation fails). CHECK constraint on `source` for 2 values: text_input, voice_transcription. `is_used` defaults to false (tracks whether hint was used in a recommendation). **HNSW index** on `hint_embedding` using `vector_cosine_ops` for fast cosine similarity nearest-neighbor search. Creates **`match_hints()` RPC function** for semantic similarity queries via PostgREST (returns hints ordered by cosine similarity with a computed similarity score). No UNIQUE constraints — unlimited hints per vault. FK CASCADE to `partner_vaults`. RLS uses subquery pattern. Index on `vault_id`. EXECUTE granted on `match_hints()` to authenticated and anon roles. |
| `00010_create_recommendations_table.sql` | Creates `public.recommendations` table (id, vault_id, milestone_id, recommendation_type, title, description, external_url, price_cents, merchant_name, image_url, created_at). Stores AI-generated gift, experience, and date recommendations from the LangGraph pipeline. CHECK constraint on `recommendation_type` for 3 values: gift, experience, date. CHECK constraint on `price_cents >= 0` (stored in cents, nullable when price unknown). `title` is NOT NULL; `description`, `external_url`, `merchant_name`, `image_url` are nullable for resilience against partial external API data. **First table with ON DELETE SET NULL:** `milestone_id` FK to `partner_milestones` uses SET NULL (not CASCADE) — recommendations persist as history even when the milestone they were generated for is deleted. `vault_id` FK still uses CASCADE (deleting vault removes all recommendations). Two indexes: `vault_id` for vault queries, `milestone_id` for milestone queries. No UNIQUE constraints — unlimited recommendations per vault (generated in batches of 3). RLS uses subquery pattern through `partner_vaults`. |
| `00011_create_recommendation_feedback_table.sql` | Creates `public.recommendation_feedback` table (id, recommendation_id, user_id, action, rating, feedback_text, created_at). Stores user feedback on AI-generated recommendations — tracks selections, refreshes, saves, shares, and star ratings. CHECK constraint on `action` for 5 values: selected, refreshed, saved, shared, rated. CHECK constraint on `rating` for 1-5 range (nullable — only required for 'rated' action). `feedback_text` is nullable for optional text feedback. **First table with dual FK CASCADE:** `recommendation_id` FK to `recommendations` (CASCADE) and `user_id` FK to `users` (CASCADE) — feedback is deleted when either the recommendation or user is removed. **First table with direct RLS** (not vault subquery): policies use `user_id = auth.uid()` directly since the table has its own `user_id` column. Two indexes: `recommendation_id` for querying by recommendation, `user_id` for querying by user. No UNIQUE constraints — multiple feedback entries per recommendation allowed (e.g., selected then rated). |
| `00012_create_notification_queue_table.sql` | Creates `public.notification_queue` table (id, user_id, milestone_id, scheduled_for, days_before, status, sent_at, created_at). Schedules proactive push notifications for upcoming milestones at 14, 7, and 3 days before. CHECK constraint on `days_before` for 3 discrete values: 14, 7, 3. CHECK constraint on `status` for 4 values: pending, sent, failed, cancelled. `status` defaults to `'pending'` via DEFAULT clause. `sent_at` is nullable (NULL until notification is actually sent). `user_id` FK to `users` (CASCADE) and `milestone_id` FK to `partner_milestones` (CASCADE) — notifications are cleaned up when either the user or milestone is deleted. Uses direct RLS (`user_id = auth.uid()`). **First table with a partial composite index:** `(status, scheduled_for) WHERE status = 'pending'` — optimized for the notification processing job's "find all pending notifications due now" query. Also has standard indexes on `user_id` and `milestone_id`. |
| `00013_add_device_token_to_users.sql` | Adds two nullable columns to `public.users`: `device_token TEXT` (hex-encoded APNs device token, NULL until user grants notification permission) and `device_platform TEXT CHECK (device_platform IN ('ios', 'android'))`. Creates a partial index `idx_users_device_token ON public.users (device_token) WHERE device_token IS NOT NULL` for efficient push delivery lookups in Step 7.5. **ALTER TABLE, not CREATE TABLE** — modifies the existing `users` table from migration 00002. Uses `IF NOT EXISTS` on both columns and index for idempotency. One device per user for MVP — a separate `device_tokens` table can replace this if multi-device support is needed later. No RLS changes needed — the existing `users_update_own` policy covers self-updates, and the backend uses service role client. |
| `00014_add_quiet_hours_to_users.sql` | Adds three columns to `public.users`: `quiet_hours_start INTEGER NOT NULL DEFAULT 22 CHECK (0-23)`, `quiet_hours_end INTEGER NOT NULL DEFAULT 8 CHECK (0-23)`, `timezone TEXT` nullable. Integers (0-23) for simplicity — quiet hours granularity is whole hours. `timezone` is nullable; when NULL, inferred from vault location by `dnd.py`. Uses `IF NOT EXISTS` for idempotency. |
| `00015_add_viewed_at_to_notification_queue.sql` | **Step 7.7.** Adds `viewed_at TIMESTAMPTZ` nullable column to `notification_queue`. Remains NULL until user taps a notification in the history screen to view its recommendations, then set via `PATCH /viewed` endpoint. Simple `ALTER TABLE ADD COLUMN` — no DEFAULT, no index (read infrequently). |

### Business Logic (`app/services/`)

| File/Folder | Status | Purpose |
|-------------|--------|---------|
| `services/` | | Core business logic (vault operations, hint processing, notification scheduling). |
| `services/embedding.py` | **Active (Step 4.4)** | Vertex AI `text-embedding-004` embedding service. **Constants:** `EMBEDDING_MODEL_NAME = "text-embedding-004"`, `EMBEDDING_DIMENSION = 768`, `VERTEX_AI_LOCATION = "us-central1"`. **Lazy initialization:** `_get_model()` initializes `vertexai` and loads `TextEmbeddingModel.from_pretrained()` on first call; caches result (model or `None`) via module-level `_initialized` flag — never retries after first attempt. Returns `None` silently when `GOOGLE_CLOUD_PROJECT` is empty or initialization fails (logs warning). **Main function:** `generate_embedding(text: str) -> Optional[list[float]]` — async, calls `model.get_embeddings([text])` via `asyncio.to_thread()` to avoid blocking the event loop. Validates the result is exactly 768 dimensions. Returns `None` on any failure (API error, wrong dimensions, unconfigured). **Helper:** `format_embedding_for_pgvector(embedding: list[float]) -> str` — converts to `"[0.1,0.2,...,0.768]"` string for PostgREST. **Test helper:** `_reset_model()` — clears cached state for test re-initialization. Called by `app.api.hints.create_hint()`. |
| `services/qstash.py` | **Active (Step 7.1, updated 7.2)** | Upstash QStash integration service for scheduled notification webhooks. **Signature verification:** `verify_qstash_signature(signature, body, url) -> dict` — validates the `Upstash-Signature` JWT header using HMAC-SHA256. Tries `QSTASH_CURRENT_SIGNING_KEY` first, falls back to `QSTASH_NEXT_SIGNING_KEY` for key rotation. Verifies 7 required JWT claims (`iss`, `sub`, `exp`, `nbf`, `iat`, `jti`, `body`), checks issuer is "Upstash", validates SHA-256 body hash matches the `body` claim, and confirms the destination URL matches the `sub` claim. Returns decoded JWT claims dict on success; raises `ValueError` on any verification failure. **Message publishing:** `publish_to_qstash(destination_url, body, *, delay_seconds, not_before, deduplication_id, retries) -> dict` — async function that publishes a JSON message to QStash via `POST /v2/publish/{destination_url}`. Sets `Authorization: Bearer {token}`, `Upstash-Retries`, optional `Upstash-Delay` (in seconds), optional `Upstash-Not-Before` (Unix timestamp for scheduled delivery with no duration limit — added in Step 7.2), and optional `Upstash-Deduplication-Id` headers. `not_before` and `delay_seconds` are mutually exclusive; `not_before` is preferred for notification scheduling because `Upstash-Delay` is capped at 7 days. Returns QStash response containing `messageId`. Raises `RuntimeError` if `UPSTASH_QSTASH_TOKEN` is not configured. Uses `httpx.AsyncClient` with 10s timeout. |
| `services/notification_scheduler.py` | **Active (Step 7.2)** | Notification scheduling service that computes milestone dates and populates the notification queue. **Constants:** `NOTIFICATION_DAYS_BEFORE = [14, 7, 3]`. **Floating holiday helpers:** `_mothers_day(year) -> date` computes 2nd Sunday of May; `_fathers_day(year) -> date` computes 3rd Sunday of June; `_is_floating_holiday(milestone_name) -> str | None` detects "mother"/"father" substrings (case-insensitive), returns `"mothers_day"`, `"fathers_day"`, or `None`. **Date computation:** `compute_next_occurrence(milestone_date, milestone_name, recurrence) -> date | None` — resolves a milestone to its next future date. For yearly recurrence: floating holidays use calendar computation, fixed dates replace the year-2000 placeholder with current/next year, Feb 29 clamps to Feb 28 in non-leap years. For one-time: returns the date if future, `None` if past. Today's date is never returned (always next year for yearly). **Scheduling:** `schedule_milestone_notifications(milestone_id, user_id, milestone_date, milestone_name, recurrence) -> list[dict]` — async function that calls `compute_next_occurrence()`, then for each interval in [14, 7, 3]: computes `scheduled_for` as midnight UTC of `(next_occurrence - interval)`, skips if in the past, inserts into `notification_queue` via service client, publishes to QStash with `not_before` Unix timestamp and deduplication_id `"{milestone_id}-{days_before}"` (only if `is_qstash_configured()`). **Batch wrapper:** `schedule_notifications_for_milestones(milestones, user_id) -> list[dict]` — iterates milestone rows (handles string→date parsing) and calls `schedule_milestone_notifications()` for each. Called from vault POST and PUT endpoints as a best-effort, fire-and-forget operation. |
| `services/vault_loader.py` | **Active (Step 7.3)** | Reusable vault data loading service, extracted from the duplicated logic in `recommendations.py`. **`load_vault_data(user_id: str) -> tuple[VaultData, str]`** — async function that queries `partner_vaults` by `user_id`, then loads `partner_interests`, `partner_vibes`, `partner_budgets`, and `partner_love_languages` by `vault_id`. Parses interests into likes/dislikes lists by `interest_type`, extracts primary/secondary love languages by `priority` (1=primary, 2=secondary), and builds `VaultBudget` objects from budget rows. Returns `(VaultData, vault_id)` tuple. Raises `ValueError` if no vault found. **`load_milestone_context(milestone_id: str, vault_id: str) -> MilestoneContext | None`** — async function that queries `partner_milestones` by `id` + `vault_id` (ownership verification). Returns `MilestoneContext` with `id`, `milestone_type`, `milestone_name`, `milestone_date`, `recurrence`, `budget_tier` fields, or `None` if not found. **`find_budget_range(budgets: list[VaultBudget], occasion_type: str) -> BudgetRange`** — sync function that searches the user's budget list for a matching `occasion_type`. Falls back to hardcoded defaults in cents: `just_because` ($20-$50), `minor_occasion` ($50-$150), `major_milestone` ($100-$500), unknown ($20-$100). Used by `generate_recommendations`, `refresh_recommendations`, and `process_notification`. |
| `services/apns.py` | **Active (Step 7.5)** | Apple Push Notification service (APNs) integration for sending push notifications to registered iOS devices. **Constants:** `APNS_PRODUCTION_URL = "https://api.push.apple.com"`, `APNS_SANDBOX_URL = "https://api.sandbox.push.apple.com"`, `TOKEN_REFRESH_INTERVAL = 3000` (50 minutes in seconds — APNs tokens valid for 60). Module-level cache: `_cached_token` and `_token_generated_at` for JWT reuse. **Auth key loading:** `_load_auth_key() -> str` — reads the `.p8` ES256 private key from disk at `APNS_AUTH_KEY_PATH`. Raises `RuntimeError` if path not configured, `FileNotFoundError` if file missing. **JWT generation:** `_generate_apns_token() -> str` — generates ES256-signed JWT with `iss=APNS_TEAM_ID`, `iat=now`, `kid=APNS_KEY_ID` header. Cached for 50 minutes; regenerated when stale. Uses `PyJWT` with `cryptography` backend for ES256. **Payload builder:** `build_notification_payload(*, partner_name, milestone_name, days_before, vibes, recommendations_count, notification_id, milestone_id) -> dict` — pure function building APNs-formatted payload. Title: `"{partner}'s {milestone} is in {days} days"`. Body: `"I've found {N} {Vibe} options based on their interests. Tap to see them."` (first vibe capitalized, underscores→spaces, empty vibes→"curated"). Category: `"MILESTONE_REMINDER"`. Custom data: `notification_id`, `milestone_id` for deep-linking. **HTTP delivery:** `send_push_notification(device_token, payload) -> dict` — async function that creates `httpx.AsyncClient(http2=True)`, POSTs to APNs `/3/device/{token}` with bearer JWT, `apns-topic` (bundle ID), `apns-push-type: alert`, `apns-priority: 10`. Returns `{"success": bool, "apns_id": str|None, "status_code": int, "reason": str|None}`. Raises `RuntimeError` if credentials missing. **High-level delivery:** `deliver_push_notification(*, user_id, notification_id, milestone_id, partner_name, milestone_name, days_before, vibes, recommendations_count) -> dict` — async entry point called from webhook. Looks up `device_token` from `users` table via `get_service_client()`. Returns `{"reason": "no_device_token"}` when NULL. Returns `{"reason": "device_token_lookup_failed: ..."}` on DB error. Otherwise builds payload and calls `send_push_notification()`. Uses late import of `get_service_client` to avoid circular dependencies. |
| `services/dnd.py` | **Active (Step 7.6)** | DND (Do Not Disturb) quiet hours enforcement service. **Constants:** `DEFAULT_QUIET_HOURS_START = 22` (10pm), `DEFAULT_QUIET_HOURS_END = 8` (8am), `DEFAULT_TIMEZONE = "America/New_York"`. **`_US_STATE_TIMEZONES`** — dict mapping all 50 US states + DC to their predominant IANA timezone (e.g., `"TX"→"America/Chicago"`, `"CA"→"America/Los_Angeles"`, `"HI"→"Pacific/Honolulu"`). **Timezone inference:** `infer_timezone_from_location(state, country) -> str` — maps US state abbreviation (case-insensitive) to IANA timezone; non-US or unknown falls back to `DEFAULT_TIMEZONE`. `get_user_timezone(user_timezone, vault_state, vault_country) -> ZoneInfo` — priority: explicit user timezone > vault location inference > fallback; catches invalid timezone strings and falls back. **Core check (pure function):** `is_in_quiet_hours(quiet_hours_start, quiet_hours_end, user_tz, now_utc=None) -> tuple[bool, datetime | None]` — converts `now_utc` to user local time, checks if current hour falls within quiet hours. Handles midnight-spanning ranges (22-8: `hour >= start OR hour < end`), same-day ranges (1-6: `start <= hour < end`), and disabled case (`start == end → False`). Returns `(is_quiet, next_delivery_utc)` where `next_delivery_utc` is computed by `_compute_next_delivery_time()`. Injectable `now_utc` parameter enables deterministic testing. **`_compute_next_delivery_time(quiet_hours_end, now_local, user_tz) -> datetime`** — calculates the next occurrence of `quiet_hours_end` in user's local timezone; if already passed today, uses tomorrow. Converts result to UTC for QStash scheduling. **High-level DB integration:** `check_quiet_hours(user_id) -> tuple[bool, datetime | None]` — async function that loads `quiet_hours_start`, `quiet_hours_end`, `timezone` from `users` table; if no explicit timezone, queries `partner_vaults` for `location_state` and `location_country` to infer timezone. Returns `(False, None)` when user not found (allows delivery). Uses `get_service_client()` for service-role access. Called from the notification webhook (step 6.5) before push delivery. |
| `services/integrations/` | **Active (Step 8.1)** | External API clients. Each integration gets its own service class returning normalized `CandidateRecommendation`-compatible dicts. |
| `services/integrations/yelp.py` | **Active (Step 8.1)** | `YelpService` — async Yelp Fusion API v3 client. Searches businesses by location, categories, and price range. Supports 30+ countries with automatic currency detection. Rate limiting with exponential backoff on HTTP 429. Normalizes Yelp business JSON to `CandidateRecommendation` schema. Exports: `YelpService`, `VIBE_TO_YELP_CATEGORIES`, `COUNTRY_CURRENCY_MAP`, `YELP_PRICE_TO_CENTS`. |
| `services/integrations/ticketmaster.py` | **Active (Step 8.2)** | `TicketmasterService` — async Ticketmaster Discovery API v2 client. Searches events by location, genre, date range, and price range. Maps 8 interest categories to Ticketmaster genre IDs via `INTEREST_TO_TM_GENRE`. Filters to only onsale events via `_is_onsale()`. Normalizes event JSON to `CandidateRecommendation` schema with `type="experience"`. Price extraction uses dollar-to-cents midpoint conversion. Image selection prefers 16:9 ratio ≥640px via `_select_best_image()`. Reuses `COUNTRY_CURRENCY_MAP` from `yelp.py` (no duplication). Auth via query param `apikey` (not header). Exports: `TicketmasterService`, `INTEREST_TO_TM_GENRE`, `VALID_ONSALE_STATUSES`, `_select_best_image`. |

### AI Pipeline (`app/agents/`)

| File | Status | Purpose |
|------|--------|---------|
| `agents/__init__.py` | Package marker | Package marker with pipeline description comment. |
| `agents/state.py` | **Active (Step 5.1)** | Recommendation pipeline state schema — 8 Pydantic models defining the complete LangGraph state. **Sub-models:** `BudgetRange` (min/max cents + currency for active occasion), `VaultBudget` (extends BudgetRange with `occasion_type` Literal), `VaultData` (full partner profile — basic info, interests/dislikes as `list[str]`, vibes as `list[str]`, `primary_love_language`/`secondary_love_language` strings, budgets as `list[VaultBudget]`), `RelevantHint` (pgvector search result with `similarity_score: float`, source Literal, `is_used`, `created_at`), `MilestoneContext` (milestone being planned for — type/name/date/recurrence/budget_tier Literals, optional `days_until: int`), `LocationData` (all-optional city/state/country/address for experience/date recs), `CandidateRecommendation` (external API result with source Literal `yelp\|ticketmaster\|amazon\|shopify\|firecrawl`, type Literal `gift\|experience\|date`, title, optional description/price_cents/image_url/merchant_name/location, `metadata: dict[str, Any]`, and 4 scoring floats: `interest_score`, `vibe_score`, `love_language_score`, `final_score` — all default 0.0). **Main state:** `RecommendationState` — `vault_data: VaultData`, `occasion_type` Literal, optional `milestone_context: MilestoneContext`, `budget_range: BudgetRange`, and 4 list fields populated by graph nodes: `relevant_hints`, `candidate_recommendations`, `filtered_recommendations`, `final_three` (all `Field(default_factory=list)`), plus optional `error: str` for pipeline error tracking. |
| `agents/hint_retrieval.py` | **Active (Step 5.2)** | LangGraph node for semantic hint retrieval. **Constants:** `MAX_HINTS = 10`, `DEFAULT_SIMILARITY_THRESHOLD = 0.0`. **Helper:** `_build_query_text(state) -> str` — constructs a natural-language query from milestone context (name + type), occasion type (mapped to human-readable labels via `occasion_labels` dict), and top 3 partner interests. **Main node:** `retrieve_relevant_hints(state: RecommendationState) -> dict[str, Any]` — async LangGraph node that generates a query embedding via `generate_embedding()`, then calls `_semantic_search()` to query pgvector's `match_hints()` RPC for the top 10 cosine-similar hints. Returns `{"relevant_hints": list[RelevantHint]}`. **Semantic path:** `_semantic_search(vault_id, query_embedding, max_count, threshold)` — calls `match_hints()` RPC with `format_embedding_for_pgvector()` formatted vector; maps rows to `RelevantHint` objects ordered by similarity DESC. **Fallback path:** `_chronological_fallback(vault_id, max_count)` — queries `hints` table directly ordered by `created_at DESC` when Vertex AI is unavailable; sets `similarity_score=0.0` for all results. Both paths return empty list on error (logged, not raised). Uses `get_service_client()` (bypasses RLS) since this runs server-side in the pipeline. |
| `agents/aggregation.py` | **Active (Step 5.3)** | LangGraph node for external API aggregation. **Constants:** `TARGET_CANDIDATE_COUNT = 20`, `MAX_GIFTS_PER_INTEREST = 3`, `MAX_EXPERIENCES_PER_VIBE = 3`. **Stub catalogs:** `_INTEREST_GIFTS` maps all 40 interest categories to 2-3 gift tuples each (title, description, price_cents, merchant, source); `_VIBE_EXPERIENCES` maps all 8 vibes to 3 experience/date tuples each (adds rec_type field). In Phase 8, these are replaced by real API services. **Candidate builders:** `_build_gift_candidate(interest, entry)` creates `CandidateRecommendation` with `type="gift"`, `location=None`, `metadata={"matched_interest": interest}`; `_build_experience_candidate(vibe, entry, location)` creates candidate with `type="experience"\|"date"`, attaches vault location, `metadata={"matched_vibe": vibe}`. **Fetch functions:** `_fetch_gift_candidates(interests, budget_min, budget_max)` and `_fetch_experience_candidates(vibes, budget_min, budget_max, location)` are async functions that look up catalog entries, build candidates, and filter by budget range. **Main node:** `aggregate_external_data(state: RecommendationState) -> dict[str, Any]` — extracts interests/vibes/budget/location from vault data (location guard checks city, state, or country), runs both fetch functions in parallel via `asyncio.gather(return_exceptions=True)`, handles partial failures (one source failing doesn't block the other), interleaves gifts and experiences before capping at 20 candidates (prevents type bias during truncation), returns `{"candidate_recommendations": list[CandidateRecommendation]}`. Sets `{"error": "No candidates found matching budget and criteria"}` when zero candidates survive budget filtering. All logger calls use lazy `%s`/`%d` formatting. No external dependencies — runs entirely from in-memory stub data. |
| `agents/filtering.py` | **Active (Step 5.4)** | LangGraph node for semantic interest filtering. **Constants:** `MAX_FILTERED_CANDIDATES = 9`. **Helpers:** `_normalize(text)` — lowercases and strips for comparison; `_matches_category(candidate, category)` — checks 3 signals in order: (1) metadata `matched_interest` exact match (strongest — from stub catalogs), (2) title keyword substring match (case-insensitive), (3) description keyword substring match (case-insensitive). Ignores `matched_vibe` metadata. `_score_candidate(candidate, interests, dislikes)` — checks dislikes first (any match → `-1.0`, removed), then scores interest matches (`+1.0` per match, `+0.5` bonus for metadata-tagged interest), returns `0.0` for neutral candidates (no interest/dislike match). **Main node:** `filter_by_interests(state: RecommendationState) -> dict[str, Any]` — async LangGraph node that takes `candidate_recommendations` from state, scores each against vault's 5 interests and 5 dislikes, removes dislike matches (score < 0), uses `model_copy(update={"interest_score": score})` for immutable updates, sorts by `(-score, title)` for deterministic ordering, returns top 9 as `{"filtered_recommendations": list[CandidateRecommendation]}`. Sets `{"error": "All candidates filtered out — try adjusting your preferences"}` when zero survive. Handles empty input gracefully. Currently uses keyword/metadata matching; Gemini 1.5 Pro semantic scoring will be added in Phase 8 when real API data (without pre-tagged metadata) flows through. No external dependencies — runs entirely from in-memory candidate data. |
| `agents/matching.py` | **Active (Step 5.5)** | LangGraph node for vibe and love language matching. **Constants:** `VIBE_MATCH_BOOST = 0.30` (+30% per matching vibe). **Vibe keywords:** `_VIBE_KEYWORDS` maps all 8 vibes to keyword lists for text-based matching (supplements metadata tags). **Love language boosts:** `_LOVE_LANGUAGE_BOOSTS` dict with (primary, secondary) tuples — `receiving_gifts`/`quality_time` get (0.40, 0.20), `acts_of_service`/`words_of_affirmation`/`physical_touch` get (0.20, 0.10). **Love language keyword lists:** `_ACTS_OF_SERVICE_KEYWORDS` (tool, kit, repair, practical, organizer, useful, home, cleaning, service), `_WORDS_OF_AFFIRMATION_KEYWORDS` (personalized, custom, portrait, engraved, sentimental, monogram, letter, journal, poem, song), `_PHYSICAL_TOUCH_KEYWORDS` (couples, massage, spa, dance class, together, two people, for two). **Helpers:** `_normalize(text)` — lowercases and strips; `_candidate_matches_vibe(candidate, vibe)` — checks (1) metadata `matched_vibe` exact match, (2) title/description keyword match; `_compute_vibe_boost(candidate, vault_vibes)` — stacks +0.30 per matching vibe; `_candidate_matches_love_language(candidate, love_language)` — type-based for `receiving_gifts` (gift type) and `quality_time` (experience/date type), keyword-based for the other three; `_compute_love_language_boost(candidate, primary, secondary)` — applies primary boost if primary matches + secondary boost if secondary matches, stacking both. **Main node:** `match_vibes_and_love_languages(state: RecommendationState) -> dict[str, Any]` — async LangGraph node that takes `filtered_recommendations`, computes vibe_boost and love_language_boost for each candidate, calculates `final_score = max(interest_score, 1.0) × (1 + vibe_boost) × (1 + love_language_boost)` (the `max(1.0)` floor ensures experience candidates with 0.0 interest_score still benefit from vibe/ll matching), uses `model_copy(update={...})` for immutable score updates (`vibe_score`, `love_language_score`, `final_score`), sorts by `(-final_score, title)` for deterministic ordering, returns `{"filtered_recommendations": list[CandidateRecommendation]}`. Handles empty input gracefully. Currently uses metadata/keyword matching; Gemini 1.5 Pro will classify candidate vibes semantically in Phase 8. No external dependencies. |
| `agents/selection.py` | **Active (Step 5.6)** | LangGraph node for diversity-optimized selection of 3 final recommendations. **Constants:** `TARGET_COUNT = 3`. **Price tier helper:** `_classify_price_tier(price_cents, budget_min, budget_max) -> str` — splits the budget range into three equal bands and returns `"low"`, `"mid"`, or `"high"`; `None` price or zero-width range defaults to `"mid"`. **Diversity scorer:** `_diversity_score(candidate, already_selected, budget_min, budget_max) -> int` — awards 0–3 points for how many dimensions (price tier, type, merchant) differ from ALL already-selected items; merchant comparison is case-insensitive and None-safe. **Main node:** `select_diverse_three(state: RecommendationState) -> dict[str, Any]` — async LangGraph node that reads `filtered_recommendations` (already ranked by `final_score` DESC from the matching node) and uses a greedy algorithm: (1) pick the highest-scored candidate first, (2) for each subsequent pick, select the candidate maximizing diversity score, breaking ties by `final_score` (higher wins) then alphabetical title. Returns `{"final_three": list[CandidateRecommendation]}` — writes to `final_three` (not `filtered_recommendations`) to preserve the full ranked pool for potential re-roll in Step 5.10. Returns fewer than 3 if the pool is smaller. Logs a diversity summary (tiers, types, merchants) for debugging. No external dependencies. |
| `agents/availability.py` | **Active (Step 5.7)** | LangGraph node for verifying that selected recommendations have valid, reachable external URLs. **Constants:** `REQUEST_TIMEOUT = 5.0` (seconds per URL check), `MAX_REPLACEMENT_ATTEMPTS = 3` (max retries per unavailable slot), `VALID_STATUS_RANGE = range(200, 400)` (2xx and 3xx are valid). **URL checker:** `_check_url(url, client) -> bool` — async helper that sends HEAD request via `httpx.AsyncClient`; falls back to GET if HEAD returns 405 (Method Not Allowed); returns `True` for any 2xx/3xx status; catches `TimeoutException`, `ConnectError`, and `HTTPError` gracefully (returns `False`, logs warning). **Backup selector:** `_get_backup_candidates(filtered, excluded_ids) -> list[CandidateRecommendation]` — returns candidates from `filtered_recommendations` not in the excluded ID set, sorted by `final_score` descending (best replacement first). **Main node:** `verify_availability(state: RecommendationState) -> dict[str, Any]` — async LangGraph node that iterates over `final_three`, checks each candidate's `external_url` via `_check_url`. If unavailable, attempts up to `MAX_REPLACEMENT_ATTEMPTS` replacements from the filtered pool (each replacement is also URL-checked). Tracks all used/tried IDs in `used_ids` set to prevent duplicates. Returns `{"final_three": list[CandidateRecommendation]}` — may return fewer than 3 if no valid replacements are found (partial results with warning log). Uses `httpx.AsyncClient` context manager with `REQUEST_TIMEOUT`. Sequential URL checks (not parallel) to simplify replacement logic. All HTTP calls are mocked in tests via `unittest.mock.patch`. |
| `agents/pipeline.py` | **Active (Step 5.8)** | Full LangGraph recommendation pipeline composing all 6 nodes into an executable graph. **Graph structure:** `START → retrieve_hints → aggregate_data → [conditional] → filter_interests → [conditional] → match_vibes_ll → select_diverse → verify_urls → END`. **Conditional edge functions:** `_check_after_aggregation(state)` — returns `"error"` (routes to END) if `candidate_recommendations` is empty, `"continue"` otherwise; `_check_after_filtering(state)` — returns `"error"` if `filtered_recommendations` is empty, `"continue"` otherwise. Both rely on the upstream node having already set `state.error` with a descriptive message. **Graph builder:** `build_recommendation_graph() -> StateGraph` — constructs the uncompiled graph with 6 nodes (`retrieve_hints`, `aggregate_data`, `filter_interests`, `match_vibes_ll`, `select_diverse`, `verify_urls`), 2 unconditional edges (START→retrieve_hints, retrieve_hints→aggregate_data), 2 conditional edges (after aggregation, after filtering), and 3 unconditional edges (match→select→verify→END). **Pre-compiled graph:** `recommendation_graph = build_recommendation_graph().compile()` — module-level `CompiledStateGraph` created at import time, reusable across requests. **Convenience runner:** `run_recommendation_pipeline(state: RecommendationState) -> dict[str, Any]` — async entry point that wraps `recommendation_graph.ainvoke(state)` with structured logging (vault_id, occasion_type, recommendation count, errors). Returns the raw result dict from LangGraph (not a Pydantic model). This is the main entry point for Step 5.9's API endpoint. |

### Environment Variables (`backend/.env.example`)

All required env vars are templated in `.env.example`:
- **Supabase:** `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
- **Vertex AI:** `GOOGLE_CLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS`
- **External APIs:** `YELP_API_KEY` (Step 8.1), `TICKETMASTER_API_KEY` (Step 8.2), Amazon/Shopify/Firecrawl keys (future steps)
- **Upstash QStash:** `UPSTASH_QSTASH_TOKEN`, `UPSTASH_QSTASH_URL`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY` — token for publishing, signing keys for webhook verification
- **APNs:** `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY_PATH`, `APNS_BUNDLE_ID`, `APNS_USE_SANDBOX` — credentials and configuration for Apple Push Notification delivery

---

## Key Architectural Decisions

### 0. App-Wide Dark Theme & Design System
The entire app uses a dark purple aesthetic, enforced at the app level:
- **`KnotApp.swift`** applies `.preferredColorScheme(.dark)` on the root `ContentView`, so ALL views render in dark mode. Individual views should never set this modifier.
- **`Theme.swift`** centralizes all colors. Views reference `Theme.accent`, `Theme.surface`, `Theme.backgroundGradient`, etc. — never hardcode color values.
- **Background gradient** is applied by each major container (`SignInView`, `OnboardingContainerView`, `HomeView`) with `.ignoresSafeArea()`. Step views inside the onboarding container are transparent and inherit the container background.
- **SwiftUI semantic colors** (`.primary`, `.secondary`, `.tertiary`) resolve correctly in dark mode. Use `Theme.textSecondary` / `.textTertiary` only when the exact reference-design opacity is needed.

### 1. Feature-Based Organization
Code is organized by feature (Auth, Onboarding, Home) rather than by type (Views, Models, Controllers). This keeps related code together and makes features self-contained.

### 2. SwiftData for Local Storage
SwiftData (iOS 17+) provides:
- Automatic persistence
- Swift-native syntax with `@Model` macro
- Integration with SwiftUI via `@Query`

### 3. XcodeGen for Project Configuration
The Xcode project is generated from `project.yml`. Benefits:
- Human-readable, diffable project configuration
- No merge conflicts on `.xcodeproj` files
- Easy to modify build settings

### 4. Strict Concurrency (Swift 6)
Enabled to catch thread-safety issues at compile time. All async code must be properly annotated with `@MainActor` or `Sendable`.

### 5. Environment-Based Configuration
Sensitive values (API keys, Supabase URL) are stored in environment variables, not in code. Use `.env` files locally and configure in deployment platform.

### 6. Layered Backend Architecture
The backend follows a clean separation of concerns:
- **API layer** (`app/api/`) — HTTP request/response handling, input validation via Pydantic
- **Service layer** (`app/services/`) — Business logic, orchestration, external API calls
- **Data layer** (`app/db/`) — Database queries, repository pattern
- **Agent layer** (`app/agents/`) — LangGraph pipeline for AI recommendation generation

Each layer only depends on the layer below it. Route handlers never call the database directly.

### 7. Python Virtual Environment
The backend uses a local `venv/` (gitignored) with Python 3.13. This avoids polluting the system Python and ensures reproducible builds. Activate with `source backend/venv/bin/activate`.

### 8. Dependency Management Strategy
All dependencies are declared in `requirements.txt` without pinned versions to allow flexibility during early development. Key dependency groups:
- **Web:** FastAPI + Uvicorn (ASGI server with hot reload)
- **AI:** LangGraph (graph-based orchestration) + Google Cloud AI Platform (Gemini 1.5 Pro via Vertex AI) + Pydantic AI (structured AI output validation)
- **Database:** Supabase client (PostgreSQL via PostgREST) + pgvector (vector type encoding for embeddings)
- **HTTP:** httpx (async client for external API integrations)
- **Testing:** pytest + pytest-asyncio

Note: `pgvector` is used via its base `Vector` type, not the SQLAlchemy integration, since database access goes through the Supabase client (PostgREST). The SQLAlchemy backend is not installed.

### 9. Dual Supabase Client Pattern
The backend maintains two Supabase clients, both lazy-initialized (created on first use, not at import time):
- **Anon client** (`get_supabase_client()`) — Uses the `anon` (public) key. Respects Row Level Security (RLS). Used for all user-facing operations where the user's JWT enforces access controls.
- **Service client** (`get_service_client()`) — Uses the `service_role` key. **Bypasses RLS entirely.** Only used for admin operations: background jobs, notification processing, migrations, and cross-user queries.

This pattern ensures user data isolation by default while allowing privileged operations when explicitly needed.

### 10. SQL Migrations Strategy
Database schema changes are stored as numbered SQL files in `backend/supabase/migrations/` (e.g., `00001_enable_pgvector.sql`). These can be run manually via the Supabase SQL Editor or via the Supabase CLI (`supabase db push`). Migrations are sequential and should never be modified after being applied — always create a new migration file for changes.

### 11. Test Configuration (`pyproject.toml`)
Pytest is configured with:
- `asyncio_mode = "auto"` — async test functions are detected and run automatically without `@pytest.mark.asyncio`
- `filterwarnings` — suppresses known deprecation warnings from `pyiceberg` (a transitive dependency of `supabase`). Only third-party warnings are suppressed; warnings from our code still surface.

### 12. Test Organization
Tests are organized by scope in `backend/tests/`:
- `test_imports.py` — Smoke tests verifying all dependencies are importable (Step 0.5)
- `test_supabase_connection.py` — Integration tests verifying Supabase connectivity and pgvector (Step 0.6). Uses `@pytest.mark.skipif` to gracefully skip connection tests when credentials aren't configured, while pure library tests (pgvector) always run.
- `test_supabase_auth.py` — Integration tests verifying Supabase Auth service reachability and Apple Sign-In provider configuration (Step 0.7). Checks GoTrue settings/health endpoints and confirms Apple is enabled for native iOS auth.
- `test_auth_middleware.py` — Integration tests verifying the FastAPI auth middleware (Step 2.5). 14 tests across 5 classes: valid token (200 response, correct user_id, JSON structure), invalid token (garbage token, fake JWT, empty bearer — all 401), no token (missing header returns 401 with descriptive message and WWW-Authenticate header per RFC 7235), malformed headers (Basic auth and raw token without Bearer prefix — both 401), and health endpoint unprotected (200 with and without auth). Tests create real Supabase auth users via the Admin API, sign them in to get valid JWTs, and clean up automatically. Introduces `test_auth_user_with_token` fixture (creates user, signs in, yields user info + access_token, deletes on teardown) and `client` fixture (FastAPI TestClient from `app.main`).
- `test_users_table.py` — Integration tests verifying the `public.users` table schema, RLS enforcement, and trigger behavior (Step 1.1). Tests create real auth users via the Supabase Admin API, verify the `handle_new_user` trigger auto-creates profile rows, confirm RLS blocks anonymous access, and validate CASCADE delete behavior. Each test uses a `test_auth_user` fixture that creates and cleans up auth users automatically.
- `test_partner_vaults_table.py` — Integration tests verifying the `public.partner_vaults` table schema, constraints, RLS enforcement, and trigger/CASCADE behavior (Step 1.2). 15 tests across 4 classes: table existence, schema verification (columns, NOT NULL, CHECK constraint, UNIQUE, defaults), RLS (anon blocked, service bypasses, user isolation), and triggers/cascades (updated_at auto-updates, cascade delete through auth→users→vaults, FK enforcement). Introduces `test_auth_user_pair` fixture for two-user isolation tests and `test_vault` fixture for vault-dependent tests.
- `test_partner_interests_table.py` — Integration tests verifying the `public.partner_interests` table schema, CHECK constraints (interest_type + interest_category), UNIQUE constraint (prevents duplicates and like+dislike conflicts), RLS enforcement via subquery, data integrity (5 likes + 5 dislikes), and CASCADE behavior (Step 1.3). 22 tests across 5 classes: table existence, schema (columns, CHECK constraints, UNIQUE, NOT NULL), RLS (anon blocked, service bypasses, user isolation), data integrity (insert/retrieve 5+5, no overlap, predefined list), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_interests` fixture (vault pre-populated with 5 likes + 5 dislikes) and `_insert_interest_raw` helper for testing failure responses.
- `test_partner_milestones_table.py` — Integration tests verifying the `public.partner_milestones` table schema, CHECK constraints (milestone_type + recurrence + budget_tier), budget tier auto-default trigger, RLS enforcement via subquery, data integrity (multiple milestones per vault, field verification), and CASCADE behavior (Step 1.4). 28 tests across 6 classes: table existence, schema (columns, 3 CHECK constraints, NOT NULL, date storage), budget tier defaults (birthday/anniversary auto-major, holiday auto-minor, holiday override, custom user-provided, custom without tier rejected), RLS (anon blocked, service bypasses, user isolation), data integrity (multiple milestones, field verification, duplicate types allowed), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_milestones` fixture (vault pre-populated with 4 milestones: birthday, anniversary, Valentine's Day, custom) and `_insert_milestone_raw` helper for testing failure responses.
- `test_partner_vibes_table.py` — Integration tests verifying the `public.partner_vibes` table schema, CHECK constraint (vibe_tag for 8 values), UNIQUE constraint (prevents duplicate vibes per vault), RLS enforcement via subquery, data integrity (multiple vibes, single vibe, max 4 vibes), and CASCADE behavior (Step 1.5). 19 tests across 5 classes: table existence, schema (columns, CHECK constraint, NOT NULL, UNIQUE prevents duplicates, same vibe allowed across vaults), RLS (anon blocked, service bypasses, user isolation), data integrity (multiple vibes, field values, max 4, single vibe), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_vibes` fixture (vault pre-populated with 3 vibes: quiet_luxury, minimalist, romantic) and `_insert_vibe_raw` helper for testing failure responses.
- `test_partner_budgets_table.py` — Integration tests verifying the `public.partner_budgets` table schema, CHECK constraints (occasion_type for 3 values, max_amount >= min_amount, min_amount >= 0), UNIQUE constraint (prevents duplicate occasion types per vault), RLS enforcement via subquery, data integrity (all 3 tiers stored, amounts correct in cents, currency defaults, integer storage, zero min allowed), and CASCADE behavior (Step 1.6). 27 tests across 5 classes: table existence, schema (columns, 3 CHECK constraints, NOT NULL for all required fields, UNIQUE prevents duplicate occasion types, same type allowed across vaults, currency default/override), RLS (anon blocked, service bypasses, user isolation), data integrity (3 tiers stored and verified, amounts in cents, field values, zero min), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_budgets` fixture (vault pre-populated with 3 budget tiers: just_because $20-$50, minor_occasion $50-$150, major_milestone $100-$500) and `_insert_budget_raw` helper for testing failure responses.
- `test_partner_love_languages_table.py` — Integration tests verifying the `public.partner_love_languages` table schema, CHECK constraints (language for 5 values, priority for 1/2 only), dual UNIQUE constraints (vault_id+priority prevents duplicate priorities, vault_id+language prevents same language at both priorities), RLS enforcement via subquery, data integrity (primary/secondary stored, field values, update primary succeeds, update to conflicting language fails), and CASCADE behavior (Step 1.7). 28 tests across 5 classes: table existence, schema (columns, 2 CHECK constraints, NOT NULL, 2 UNIQUE constraints, third language rejection, same language across vaults allowed, priority 0 rejected), RLS (anon blocked, service bypasses, user isolation), data integrity (primary+secondary stored, field values, primary correct, secondary correct, update primary succeeds, update to same-as-secondary fails), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_love_languages` fixture (vault pre-populated with primary=quality_time, secondary=receiving_gifts), `_insert_love_language_raw` helper for testing failure responses, and `_update_love_language` helper for testing update semantics.
- `test_hints_table.py` — Integration tests verifying the `public.hints` table schema, CHECK constraint (source for 2 values), vector(768) embedding column (nullable, accepts 768-dim vectors), HNSW index, `match_hints()` RPC function for cosine similarity search, RLS enforcement via subquery, data integrity (multiple hints, mixed sources, is_used default and update, with/without embeddings), vector similarity search (ordering verification with crafted vectors, threshold filtering, match_count limiting, vault scoping, NULL embedding skipping), and CASCADE behavior (Step 1.8). 30 tests across 6 classes: table existence, schema (columns, CHECK constraint, NOT NULL, is_used default, embedding nullable, embedding accepts 768-dim), RLS (anon blocked, service bypasses, user isolation), data integrity (multiple hints, field values, mixed sources, is_used update, with/without embedding), vector search (returns results, ordered by similarity, threshold filters, match_count limits, scoped to vault, skips NULL embeddings), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_hints` fixture (vault with 3 hints without embeddings), `test_vault_with_embedded_hints` fixture (vault with 3 hints with crafted 768-dim vectors for similarity testing), `_insert_hint_raw` helper for testing failure responses, and `_make_vector` helper for creating padded 768-dim vector strings.
- `test_recommendations_table.py` — Integration tests verifying the `public.recommendations` table schema, CHECK constraints (recommendation_type for 3 values, price_cents >= 0), nullable columns (milestone_id, description, external_url, price_cents, merchant_name, image_url), milestone FK SET NULL behavior, RLS enforcement via subquery, data integrity (3 recommendations per vault/"Choice of Three", all fields populated, all 3 types stored, with/without milestone, prices in cents, external URLs, merchant names), milestone FK behavior (SET NULL on milestone delete preserves recommendation history, FK enforcement rejects invalid milestone_id), and CASCADE behavior (Step 1.9). 31 tests across 6 classes: table existence, schema (columns, CHECK constraints, NOT NULL for title/type, nullable for description/url/price/merchant/image/milestone_id, price accepts zero, price rejects negative), RLS (anon blocked, service bypasses, user isolation), data integrity (3 recs stored, all fields verified, types stored, milestone linked, without milestone, prices in cents, URLs, merchants), milestone FK (SET NULL on delete, FK enforcement), and cascades (vault deletion, full auth chain, FK enforcement). Introduces `test_vault_with_milestone` fixture (vault with birthday milestone), `test_vault_with_recommendations` fixture (vault with 3 recommendations: gift/experience/date linked to milestone), `_insert_recommendation_raw` helper for testing failure responses, and sample recommendation constants (`SAMPLE_GIFT_REC`, `SAMPLE_EXPERIENCE_REC`, `SAMPLE_DATE_REC`).
- `test_recommendation_feedback_table.py` — Integration tests verifying the `public.recommendation_feedback` table schema, CHECK constraints (action for 5 values, rating for 1-5 range), dual FK CASCADE (recommendation_id + user_id), direct RLS enforcement (`user_id = auth.uid()`), data integrity (selected action, rated with text, multiple feedback per recommendation), and CASCADE behavior (Step 1.10). 27 tests across 5 classes: table existence, schema (columns, action CHECK with all 5 values tested, rating range CHECK rejects 0 and 6, rating accepts 1-5, rating nullable, feedback_text nullable/stores value, action NOT NULL), RLS (anon blocked, service bypasses, user isolation), data integrity (selected action queried by recommendation_id, rated with text stored, multiple entries per recommendation), and cascades (recommendation deletion, full auth chain, recommendation_id FK enforcement, user_id FK enforcement). Introduces `test_vault_with_recommendation` fixture (vault with a gift recommendation), `test_feedback_selected` fixture (feedback with action='selected'), `_insert_feedback_raw` helper for testing failure responses, and `_delete_feedback` helper.
- `test_notification_queue_table.py` — Integration tests verifying the `public.notification_queue` table schema, CHECK constraints (days_before for 14/7/3, status for 4 values), DEFAULT status to 'pending', status transition semantics, direct RLS enforcement (`user_id = auth.uid()`), data integrity (pending stored, 3 per milestone ordered, field values, status update to sent with sent_at, status update to cancelled), and CASCADE behavior (Step 1.11). 26 tests across 5 classes: table existence, schema (columns, days_before CHECK rejects invalid/accepts 14/7/3, status CHECK rejects invalid/accepts all 4, status defaults to pending, sent_at nullable, scheduled_for NOT NULL, days_before NOT NULL), RLS (anon blocked, service bypasses, user isolation), data integrity (pending queryable, 3 per milestone at 14/7/3, field values verified, update to sent with sent_at, update to cancelled), and cascades (milestone deletion, full auth chain, milestone_id FK enforcement, user_id FK enforcement). Introduces `test_vault_with_milestone` fixture (vault with birthday milestone), `test_notification_pending` fixture (single pending at 14 days), `test_three_notifications` fixture (14/7/3 set), `_insert_notification_raw` helper, `_update_notification` helper, and `_future_timestamp` helper for generating ISO 8601 timestamps.
- `test_vault_api.py` — Integration tests verifying the `POST /api/v1/vault` API endpoint (Step 3.10). 40 tests across 10 classes: valid payload (full and minimal → 201 with vault_id, partner_name, and correct summary counts), data integrity (6 separate tests verifying each database table — partner_vaults basic info, partner_interests 5 likes + 5 dislikes with correct categories, partner_milestones with budget tier auto-defaults from DB trigger, partner_vibes tags, partner_budgets amounts in cents, partner_love_languages primary/secondary priorities), interest validation (4 interests rejected, 6 rejected, invalid category "Golf" rejected, duplicate rejected, 4 dislikes rejected, interest/dislike overlap rejected — all 422), vibe validation (0 vibes rejected, invalid "fancy" rejected, 9 vibes rejected, duplicate rejected — all 422), budget validation (2 tiers rejected, max < min rejected, negative min rejected, duplicate occasion types rejected — all 422), love language validation (same primary/secondary rejected, invalid language rejected, missing secondary rejected — all 422), milestone validation (0 milestones rejected, no birthday rejected, custom without budget_tier rejected, empty name rejected — all 422), missing required fields (partner_name, interests, love_languages, vibes, budgets — all 422), auth required (no token 401, invalid token 401), and duplicate vault (second POST → 409 "already exists"). Uses FastAPI `TestClient`, real Supabase auth users via `test_auth_user_with_token` fixture, `_valid_vault_payload()` helper (complete payload that can be modified per test), `_query_table()` helper (service-role PostgREST queries to verify DB state), and `_auth_headers()` helper.

### 13. Native iOS Auth Strategy
Knot uses **native Sign in with Apple** rather than the web OAuth redirect flow. This means:
- The iOS app presents `SignInWithAppleButton` (AuthenticationServices framework)
- Apple returns an identity token directly to the app
- The app sends this token to Supabase via `signInWithIdToken(provider: .apple, idToken: token)`
- Supabase validates the token with Apple and creates/returns a user session

This approach does NOT require an OAuth Secret Key or Callback URL in the Supabase dashboard. Those are only needed for web-based Sign in with Apple. The Client ID in Supabase must match the iOS app's bundle identifier (`com.ronniejay.knot`).

### 14. Supabase Swift SDK (iOS)
The iOS project depends on three products from `supabase-swift` (v2.41.0):
- **Auth** — Authentication client (sign in, sign out, session management, token refresh)
- **PostgREST** — Type-safe database query builder for Supabase tables
- **Supabase** — Umbrella module that bundles all Supabase services

These are declared in `iOS/project.yml` under `packages` and `dependencies`, and resolved via SPM.

### 15. Reusable vs Table-Specific Trigger Functions
Database trigger functions fall into two categories:

**Reusable (shared across tables):**
- **`handle_updated_at()`** — Generic `BEFORE UPDATE` trigger that sets `NEW.updated_at = now()`. Any table with an `updated_at` column can attach this trigger. Created in migration `00002` and reused by `partner_vaults`, `hints`, etc.
- **`handle_new_user()`** — `AFTER INSERT` trigger on `auth.users` that auto-creates a `public.users` row. Uses `SECURITY DEFINER` to bypass RLS (runs as the function creator, not the calling user).

**Table-specific (logic tied to one table):**
- **`handle_milestone_budget_tier()`** — `BEFORE INSERT` trigger on `partner_milestones` that auto-sets `budget_tier` based on `milestone_type` when the caller does not provide one. Uses a `CASE` statement: birthday/anniversary → `major_milestone`, holiday → `minor_occasion`, custom → no default (NOT NULL rejects). Only fires when `budget_tier IS NULL` — explicit values are never overridden. This allows the app layer to send `major_milestone` for major holidays (Valentine's/Christmas) while the database provides safe defaults for simpler inserts.

### 16. RLS + GRANT Layered Defense
Tables use a two-layer access control strategy:
- **GRANT** — Controls which PostgreSQL roles can perform which operations on the table (e.g., `authenticated` gets SELECT/INSERT/UPDATE, `anon` gets SELECT only)
- **RLS Policies** — Controls which rows each user can see/modify (e.g., `auth.uid() = id` ensures users only access their own data)

Both layers must pass for a query to succeed. The `anon` role has SELECT GRANT but RLS returns empty results (since `auth.uid()` is NULL for anonymous requests). The `service_role` key bypasses RLS entirely.

### 17. Database Test Pattern with Auth Users
Tests that need database rows in RLS-protected tables use the Supabase Admin API (`/auth/v1/admin/users`) to create real auth users. The `test_auth_user` pytest fixture:
1. Creates an auth user with a unique email via the Admin API
2. Waits for the `handle_new_user` trigger to auto-create the `public.users` row
3. Yields the user info (id, email) to the test
4. Cleans up by deleting the auth user (CASCADE removes the `public.users` row)

This pattern will be reused for all future table tests that depend on RLS.

### 18. Partner Vault as Central Data Hub
The `partner_vaults` table is the central entity that all partner-related data hangs off of. Future tables (`partner_interests`, `partner_milestones`, `partner_vibes`, `partner_budgets`, `partner_love_languages`, `hints`, `recommendations`) will all reference `partner_vaults.id` via foreign keys with CASCADE delete. This means deleting a vault cleans up all child data automatically. The CASCADE chain is three levels deep: `auth.users` → `public.users` → `partner_vaults` → (child tables).

### 19. Auto-Generated vs Mirrored Primary Keys
Two patterns are used for primary keys:
- **Mirrored:** `public.users.id` directly mirrors `auth.users.id` (same UUID). This makes it easy to join auth data with profile data.
- **Auto-generated:** `partner_vaults.id` uses `gen_random_uuid()` to create its own identity. The `user_id` column is the FK link. This is used for child entities where the primary key doesn't need to match any external system.

Future tables (interests, milestones, vibes, etc.) will follow the auto-generated pattern with FK references to their parent.

### 20. CHECK Constraints vs Application-Layer Validation
PostgreSQL CHECK constraints are used for simple enum validation (e.g., `cohabitation_status IN ('living_together', 'separate', 'long_distance')`). This provides database-level enforcement that can't be bypassed, even by service-role queries. For complex validation (e.g., "exactly 5 interests per vault"), enforcement will be at the application/API layer (Pydantic models in FastAPI) since PostgreSQL CHECK constraints can't span multiple rows.

### 21. Test Fixture Composition Pattern
Test files use composable pytest fixtures that build on each other:
- `test_auth_user` → creates an auth user (trigger creates `public.users` row)
- `test_vault(test_auth_user)` → creates a vault for that user
- `test_vault_with_interests(test_vault)` → adds 5 likes + 5 dislikes to the vault
- `test_vault_with_milestones(test_vault)` → adds 4 milestones (birthday, anniversary, Valentine's Day, custom "First Date")

Each fixture yields data and relies on CASCADE deletes for automatic cleanup (deleting the auth user cascades through all child data). This avoids manual cleanup logic and ensures tests are isolated.

### 22. PostgREST Error Code Patterns
When testing constraint violations via the PostgREST API:
- **HTTP 400** — NOT NULL violations, CHECK constraint violations
- **HTTP 409** — UNIQUE constraint violations, foreign key violations
- **HTTP 200 with empty array** — RLS blocking (query succeeds but returns no rows)

Tests check for these specific codes to verify the correct constraint is being enforced.

### 23. Supabase SQL Editor Transaction Behavior
The Supabase SQL Editor runs multi-statement SQL as a **single transaction**. If any statement fails (e.g., a typo in a role name), the entire batch is rolled back — including earlier statements that appeared to succeed. When running migrations manually, run in smaller batches to isolate failures. Numbered migration files should be run in order, one at a time.

### 24. RLS Subquery Pattern for Child Tables
Tables that don't have a direct `user_id` column (like `partner_interests`, which only has `vault_id`) use a **subquery pattern** for RLS policies:
```sql
CREATE POLICY "interests_select_own"
    ON public.partner_interests FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_interests.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));
```
This checks ownership by joining through the parent table (`partner_vaults`) to find the `user_id`. All future child tables hanging off `partner_vaults` (milestones, vibes, budgets, love languages, hints) will use this same pattern. The subquery is efficient because PostgreSQL optimizes `EXISTS` with a semi-join.

### 25. UNIQUE Composite Constraint for Mutual Exclusion
The `UNIQUE(vault_id, interest_category)` constraint on `partner_interests` serves a dual purpose:
1. **Prevents duplicates** — The same category cannot appear twice for a vault (even with the same `interest_type`)
2. **Enforces mutual exclusion** — A category cannot be both a "like" and a "dislike" for the same vault, since the UNIQUE constraint is on `(vault_id, interest_category)` regardless of `interest_type`

This is more efficient than using a database trigger or complex CHECK constraint, and provides atomic enforcement at the database level. The trade-off is that changing an interest from "like" to "dislike" requires deleting the old row and inserting a new one (rather than updating `interest_type` in place), since the UNIQUE constraint prevents having both simultaneously.

### 26. Database-Level vs Application-Level Validation Split
Step 1.3 establishes the pattern for splitting validation between database and application layers:
- **Database-level** (CHECK, UNIQUE, FK): `interest_type` enum, `interest_category` enum, no duplicate categories per vault, referential integrity
- **Application-level** (Pydantic in FastAPI): "Exactly 5 likes and 5 dislikes per vault" — this requires counting rows across the table, which PostgreSQL CHECK constraints cannot do (they only operate on single rows)

This split will be consistent for future tables. Simple per-row enum/value constraints go in the database. Cross-row cardinality rules go in the API layer.

### 27. Trigger-Based Defaults for Context-Dependent Values
The `partner_milestones` table introduces a new pattern: using a `BEFORE INSERT` trigger to set column defaults that depend on the value of another column in the same row. PostgreSQL's `DEFAULT` clause only supports constant expressions, so it cannot express "if milestone_type is 'birthday', default budget_tier to 'major_milestone'." The `handle_milestone_budget_tier()` trigger solves this by inspecting `NEW.milestone_type` and setting `NEW.budget_tier` when it's NULL. The trigger is designed to be non-destructive — it only modifies NULL values, never overrides explicit ones. This allows the application layer to send explicit values (e.g., `major_milestone` for Valentine's Day holidays) while the database provides safe defaults for simpler inserts (e.g., birthday auto-gets `major_milestone`).

### 28. Year-2000 Placeholder for Yearly Recurring Dates
Milestones with `recurrence = 'yearly'` store their date using year 2000 as a placeholder (e.g., `2000-03-15` for March 15 birthdays). This convention:
- Uses a real `DATE` type (not separate month/day columns), enabling standard date operations
- Avoids ambiguity about which year is "current" at the database level
- Keeps the application logic for "next occurrence" simple: replace year 2000 with the current (or next) year, then check if the date has passed this year
- Was chosen over alternatives like storing month/day separately (harder to query) or storing the actual birth year (privacy concern, and irrelevant for notification scheduling)

One-time milestones (e.g., a specific trip or event) store the actual date with the real year.

### 29. No UNIQUE Constraint on Milestones (Unlike Interests)
The `partner_milestones` table deliberately has NO unique constraint on `(vault_id, milestone_type)` or `(vault_id, milestone_name)`. This is different from `partner_interests`, which uses `UNIQUE(vault_id, interest_category)` to prevent duplicates. The reasoning:
- A vault needs multiple holidays (Christmas, Valentine's Day, New Year's Eve — all type `holiday`)
- A vault might have multiple custom milestones (First Date, Engagement Party — all type `custom`)
- Even milestone names could theoretically repeat (unlikely but not worth constraining)

The only constraint is the FK to `partner_vaults` — every milestone must belong to a valid vault.

### 30. Budget Tier Strategy: Database Defaults + Application Overrides
The budget tier for milestones uses a two-layer strategy:
1. **Database trigger** provides safe defaults: birthday/anniversary → `major_milestone`, holiday → `minor_occasion`
2. **Application layer** overrides for specific cases: Valentine's Day and Christmas holidays get `major_milestone` (the app explicitly sends this value)
3. **User choice** for custom milestones: the app must collect a budget tier during custom milestone creation

This avoids encoding holiday-name-specific logic in the database (which would be brittle and hard to maintain) while still providing sensible defaults that reduce the burden on the API layer for common cases.

### 31. Vibes Table as the Simplest Child Table Pattern
The `partner_vibes` table is the simplest child table in the schema — it serves as a clean reference implementation for the "tag storage" pattern. Unlike `partner_interests` (which has dual-purpose UNIQUE for deduplication + mutual exclusion) and `partner_milestones` (which has a trigger for computed defaults), vibes are a pure many-to-one tag table: each row is just a vault_id + vibe_tag pair with a CHECK constraint. The `UNIQUE(vault_id, vibe_tag)` constraint exists solely for deduplication (no dual-purpose like interests). This pattern will be reused for any future simple tag/enum association tables.

### 32. Consistent Child Table Schema Pattern
By Step 1.5, a clear pattern has emerged for child tables hanging off `partner_vaults`:
- **Primary key:** `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- **Parent FK:** `vault_id UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE`
- **Timestamp:** `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- **RLS:** 4 policies (SELECT, INSERT, UPDATE, DELETE) using the subquery pattern to check `auth.uid()` through `partner_vaults.user_id`
- **GRANTs:** Full CRUD for `authenticated`, read-only for `anon`
- **Index:** Single-column index on `vault_id` for fast lookups
- **Cardinality rules:** Enforced at the API layer, not the database (e.g., "1-4 vibes", "exactly 5 likes")

Future child tables (`partner_love_languages`, `hints`, `recommendations`) should follow this same pattern unless they have a specific reason to deviate.

### 33. Monetary Amounts in Cents (Integer Pattern)
The `partner_budgets` table stores monetary amounts as **integers representing cents** (e.g., `2000` = $20.00, `15000` = $150.00). This is a standard financial data pattern that avoids floating-point precision issues (e.g., `0.1 + 0.2 ≠ 0.3` in IEEE 754). Key implications:
- **Database:** `min_amount` and `max_amount` are `INTEGER NOT NULL` — no `NUMERIC` or `DECIMAL` type needed for cents
- **API layer:** Pydantic models accept/return integers in cents
- **iOS UI:** Must convert between cents (API) and dollars (display): `amount_cents / 100` for display, `dollars * 100` for submission
- **Cross-column CHECK:** `CHECK (max_amount >= min_amount)` validates the range at the database level — this is a PostgreSQL feature that operates on multiple columns within the same row (unlike cross-row validation which requires triggers or application logic)

### 34. UNIQUE Constraint for One-Per-Occasion Budget Pattern
The `UNIQUE(vault_id, occasion_type)` constraint on `partner_budgets` ensures each vault has **exactly one budget configuration per occasion type**. This is semantically different from the UNIQUE constraints on other child tables:
- `partner_interests`: `UNIQUE(vault_id, interest_category)` — deduplication + mutual exclusion (like/dislike)
- `partner_vibes`: `UNIQUE(vault_id, vibe_tag)` — pure deduplication
- `partner_budgets`: `UNIQUE(vault_id, occasion_type)` — enforces one-to-one mapping between vault and each occasion type
- `partner_love_languages`: `UNIQUE(vault_id, priority)` + `UNIQUE(vault_id, language)` — dual constraint for priority uniqueness + language mutual exclusion (see §35)

This means updating a budget tier requires an `UPDATE` on the existing row (not `DELETE` + `INSERT`). The API layer should use upsert semantics when the user adjusts their budget sliders.

### 35. Dual UNIQUE Constraint Strategy for Love Languages
The `partner_love_languages` table introduces a new pattern: using **two UNIQUE constraints** together to enforce both priority uniqueness and language mutual exclusion:
- `UNIQUE(vault_id, priority)` — ensures at most one primary (1) and one secondary (2) per vault
- `UNIQUE(vault_id, language)` — ensures the same language cannot appear at both priorities for a vault

Combined with `CHECK(priority IN (1, 2))`, these constraints create a hard maximum of 2 rows per vault. A third insert is impossible because:
1. Priority 1 is taken → `UNIQUE(vault_id, priority)` blocks another priority=1
2. Priority 2 is taken → `UNIQUE(vault_id, priority)` blocks another priority=2
3. Priority 3+ → `CHECK(priority IN (1, 2))` blocks it

This is more restrictive than other child tables:
- `partner_interests`: single UNIQUE, unlimited rows within constraint
- `partner_vibes`: single UNIQUE, up to 8 rows (one per valid vibe)
- `partner_budgets`: single UNIQUE, up to 3 rows (one per occasion type)
- `partner_love_languages`: dual UNIQUE + CHECK, **exactly 0-2 rows** (hard database limit)

Updating a love language (e.g., changing primary from `quality_time` to `physical_touch`) works via a standard PATCH. However, swapping primary and secondary requires a multi-step process (delete one, update the other, re-insert) because the UNIQUE constraints prevent intermediate states where both rows have the same language or priority. The API layer should handle swap operations as a transaction.

### 36. Currency as Flexible Text Column
The `currency` column on `partner_budgets` uses `TEXT NOT NULL DEFAULT 'USD'` rather than a CHECK constraint with a fixed list of ISO 4217 codes. This design choice:
- **Supports international users** without database migrations when adding new currencies
- **Delegates validation** to the API layer (Pydantic model can validate against a known list of ISO 4217 codes)
- **Avoids maintenance burden** of updating a CHECK constraint every time a new currency is needed
- **Mirrors the pattern** used by external APIs (Yelp, Ticketmaster) which return currency codes as strings

### 37. pgvector Column Strategy: Nullable Embeddings
The `hint_embedding` column on `hints` is `vector(768)` with **no NOT NULL constraint** (nullable). This deliberate design choice provides resilience:
- The normal flow (Step 4.4) generates the embedding synchronously via Vertex AI `text-embedding-004` before storing the hint
- If the Vertex AI API is temporarily unavailable, the hint text can still be stored immediately and the embedding backfilled later via a background job
- The `match_hints()` RPC function includes `WHERE h.hint_embedding IS NOT NULL` to exclude unembedded hints from similarity search, ensuring partial data doesn't corrupt search results
- This pattern of "store first, enrich later" is common in systems that depend on external ML APIs for data augmentation

### 38. HNSW vs IVFFlat Index Choice
The `hints` table uses an **HNSW (Hierarchical Navigable Small World)** index instead of IVFFlat for the vector similarity search. Key differences:
- **HNSW:** No pre-build step required (works on empty tables), better recall (accuracy) at the cost of slightly more memory, incrementally updated as data is inserted
- **IVFFlat:** Requires data in the table before building the index (`CREATE INDEX` should happen after initial data load), faster index creation for large batches, slightly less accurate
- For Knot's use case (hints trickle in one-at-a-time via user input), HNSW is the clear winner because it handles incremental inserts naturally
- The `vector_cosine_ops` operator class was chosen because cosine similarity is standard for text embeddings (it measures directional similarity regardless of vector magnitude)

### 39. RPC Functions for pgvector Operations
PostgREST (Supabase's REST API layer) does not natively support pgvector operators like `<=>` (cosine distance), `<->` (L2 distance), or `<#>` (inner product). To perform similarity search via the API, a **PostgreSQL function** must be created and called via the `/rest/v1/rpc/{function_name}` endpoint. The `match_hints()` function:
- Accepts a query vector, vault_id, similarity threshold, and result count
- Uses `1 - (hint_embedding <=> query_embedding)` to compute cosine similarity (the `<=>` operator returns cosine *distance*, which is `1 - similarity`)
- Orders by `hint_embedding <=> query_embedding` ASC (smallest distance = most similar)
- Filters by `hint_embedding IS NOT NULL` (skips unembedded hints) and `similarity >= match_threshold`
- Returns a `similarity` column (1.0 = identical direction, 0.0 = orthogonal)
- Uses `SECURITY INVOKER` (default) — when called by the service client, RLS is bypassed; when called by an authenticated user, RLS ensures they only see their own vault's hints

This RPC pattern will be reused by the LangGraph hint retrieval node (Step 5.2) when performing semantic search to find relevant hints for recommendation generation.

### 40. Hints as an Unbounded Collection
Unlike other child tables that have explicit cardinality limits (5 likes, 5 dislikes, 1-4 vibes, 3 budget tiers, 2 love languages), the `hints` table has **no UNIQUE constraints and no cardinality limits** at the database level. A vault can accumulate unlimited hints over time. This is intentional:
- Hints are the primary input for the "Second Brain" feature — the more hints captured, the better the recommendation quality
- Duplicate hint text is allowed (the user might re-mention something, which is a signal of importance)
- The `is_used` boolean tracks which hints have been incorporated into recommendations, enabling the system to prioritize fresh/unused hints
- Cleanup of old/stale hints can be implemented as a background job in the future

### 41. ON DELETE SET NULL for Recommendation-Milestone Relationship
The `recommendations` table introduces a **new FK delete behavior**: `ON DELETE SET NULL` for `milestone_id`. All previous FK relationships in the schema use `ON DELETE CASCADE`. The reasoning:
- Recommendations are **historical records** — they represent suggestions the AI generated and potentially the user acted on (selected, saved, shared). Deleting a milestone (e.g., removing an anniversary) should not erase the gift recommendations that were generated for it.
- When a milestone is deleted, `milestone_id` becomes NULL, effectively making the recommendation a "just because" historical entry. All other fields (title, price, merchant, URL) remain intact.
- The `vault_id` FK still uses CASCADE because deleting a vault means the user is removing all partner data — recommendations have no meaning without the vault.
- Future tables that reference `recommendations` (like `recommendation_feedback` in Step 1.10) will use CASCADE, since feedback is meaningless without the recommendation it refers to.

This creates a **mixed FK strategy** in the schema:
| Parent Table | Child Table | Delete Behavior | Reason |
|-------------|-------------|----------------|--------|
| `partner_vaults` | `recommendations` | CASCADE | Vault deletion = remove all partner data |
| `partner_milestones` | `recommendations` | SET NULL | Milestone deletion should preserve history |

### 42. Dual Index Pattern for Multi-Access Queries
The `recommendations` table is the **first child table with two indexes** (beyond the primary key):
- `idx_recommendations_vault_id` — for queries like "get all recommendations for this vault" (the standard child-table index)
- `idx_recommendations_milestone_id` — for queries like "get recommendations generated for this specific milestone"

Previous child tables only needed a single `vault_id` index because they were only queried via their parent vault. Recommendations have a second access pattern: when a milestone notification fires (Step 7.3), the system needs to check if recommendations already exist for that milestone. The milestone index enables this lookup without a full table scan.

### 43. Nullable Columns for External API Resilience
The `recommendations` table makes `description`, `external_url`, `price_cents`, `merchant_name`, and `image_url` all nullable, unlike `title` and `recommendation_type` which are NOT NULL. This is a deliberate design for **external API resilience**:
- External APIs (Yelp, Ticketmaster, Amazon, Shopify) may return partial data — a restaurant might have a name and URL but no image, or an event might not have a fixed price
- The LangGraph pipeline (Steps 5.1–5.8) aggregates data from multiple sources, and not all sources provide every field
- Making these columns nullable allows the pipeline to store partial recommendations rather than failing entirely when one field is missing
- The iOS UI (Step 6.1) should handle NULL fields gracefully — showing placeholder images, "Price unavailable" text, etc.

This differs from `partner_budgets` where `min_amount` and `max_amount` are NOT NULL because those are user-provided values that must always be present.

### 44. Recommendations as an Unbounded Append-Only Collection
Like `hints`, the `recommendations` table has **no UNIQUE constraints and no cardinality limits**. Recommendations are generated in batches of 3 (the "Choice of Three") and simply appended to the table. Key implications:
- Multiple batches of 3 can exist for the same vault and milestone (e.g., initial batch + refreshed batch)
- The same recommendation could theoretically be regenerated (e.g., if the user refreshes and the API returns the same item)
- Historical recommendations are never deleted by the system — only by vault CASCADE or explicit user action
- The `recommendation_feedback` table (Step 1.10) links to specific recommendation IDs to track which ones were selected, refreshed, saved, or shared

### 45. Direct RLS vs Vault Subquery RLS
Two RLS patterns are now used in the schema:

**Vault Subquery Pattern** (used by child tables of `partner_vaults`):
```sql
USING (EXISTS (
    SELECT 1 FROM public.partner_vaults
    WHERE partner_vaults.id = child_table.vault_id
    AND partner_vaults.user_id = auth.uid()
))
```
Used by: `partner_interests`, `partner_milestones`, `partner_vibes`, `partner_budgets`, `partner_love_languages`, `hints`, `recommendations`

**Direct User ID Pattern** (used by tables with their own `user_id` column):
```sql
USING (user_id = auth.uid())
```
Used by: `users`, `recommendation_feedback`, `notification_queue`

The direct pattern is simpler and more performant (no subquery/join needed). It's used when the table has a direct relationship to the user, not mediated through the partner vault. The `recommendation_feedback` and `notification_queue` tables have their own `user_id` because they model user actions and system events rather than partner profile data.

### 46. Dual FK CASCADE on Feedback Table
The `recommendation_feedback` table is the **first table with foreign keys to two different parent tables** that both use CASCADE:
- `recommendation_id → recommendations ON DELETE CASCADE`
- `user_id → users ON DELETE CASCADE`

This means a feedback row can be deleted from two independent paths:
1. When the recommendation is deleted (e.g., vault deletion cascading through `vaults → recommendations → feedback`)
2. When the user account is deleted (e.g., `auth.users → users → feedback`)

This is safe because feedback is meaningless without either the recommendation it refers to or the user who provided it. Both CASCADE paths lead to correct cleanup.

### 47. Partial Composite Index for Job Processing
The `notification_queue` table introduces a **partial index** — the first in the schema:
```sql
CREATE INDEX idx_notification_queue_status_scheduled
    ON public.notification_queue (status, scheduled_for)
    WHERE status = 'pending';
```

This index only includes rows where `status = 'pending'`, making it highly efficient for the notification processing job's primary query pattern: "find all pending notifications scheduled before NOW." Key benefits:
- The index is much smaller than a full index (excludes sent/failed/cancelled rows that accumulate over time)
- As notifications are processed and marked 'sent', they automatically leave the index
- The composite `(status, scheduled_for)` allows PostgreSQL to satisfy both the filter and the sort in a single index scan

This pattern is recommended for any "job queue" table where the processing query always filters by a specific status value.

### 48. Notification Queue as CASCADE (Not SET NULL)
The `notification_queue.milestone_id` uses `ON DELETE CASCADE` (not SET NULL like `recommendations.milestone_id`). The reasoning:
- **Notifications are prospective** — they represent future actions to be taken. If the milestone is deleted, the notifications are meaningless and should be cleaned up.
- **Recommendations are retrospective** — they represent past suggestions that the user may have acted on. Preserving them as historical records (with `milestone_id` set to NULL) is valuable for the feedback/learning loop.

This creates a clear pattern: **forward-looking references CASCADE, backward-looking references SET NULL.**

### 49. SwiftData Model Design Decisions
The SwiftData models (Step 1.12) follow several deliberate design choices:

**Raw String for Enum Storage:**
SwiftData has limitations with persisting custom enums directly. `SyncStatus` is stored as `syncStatusRaw: String` with a computed `syncStatus` property for type-safe access. This pattern should be used for all future SwiftData enums.

**Nullable `remoteID` for Offline-First:**
All models use `remoteID: UUID?` (nullable) rather than a required ID. When a record is created locally (e.g., capturing a hint while offline), it won't have a Supabase UUID until it's synced. The nullable pattern enables offline-first creation without dummy IDs.

**No SwiftData `@Relationship` Links:**
The models do NOT define SwiftData `@Relationship` between them (e.g., vault → hints). Relationships are managed via UUID foreign keys, matching the Supabase schema pattern. This avoids SwiftData's complex relationship lifecycle management and keeps the models as simple data containers. SwiftData relationships can be added later if local query performance demands it.

**Excluded Server-Only Columns:**
`HintLocal` excludes `hint_embedding` (768-float vector). This column is only used server-side for semantic search via the `match_hints()` RPC function. Storing it on-device would waste ~3KB per hint with no local utility.

### 51. SignInView Architecture (Step 2.1)
The `SignInView` is the first feature view in the app and establishes patterns for future feature views:

**View-Only Pattern (No ViewModel Yet):**
Step 2.1 uses a simple `@State`-based view without a separate ViewModel. The sign-in result handler is a private method on the view struct. This is intentional for the MVP — the view is simple enough that a ViewModel would be over-engineering. A ViewModel (`AuthViewModel`) will be introduced in Step 2.2 when Supabase session management adds complexity.

**Private Sub-Components:**
The `SignInFeatureRow` component is `private` within `SignInView.swift` rather than being placed in `/Components/`. This is because it's a presentational component specific to the sign-in screen with no reuse potential. Components that ARE reusable across features (like `ChipView`, `CardView`) should go in `/Components/`.

**Error Handling Strategy:**
The view distinguishes between user-initiated cancellation (`ASAuthorizationError.canceled`) and system errors. Cancellation is silently ignored (standard iOS behavior — the user knowingly dismissed the sheet). All other errors surface as alerts. This two-tier error handling pattern should be followed for all user-facing flows.

**Credential Extraction Pattern:**
The Apple credential provides three key pieces: `user` (stable Apple user ID), `email` (only on first sign-in, nil on subsequent), and `identityToken` (JWT for server validation). The identity token is the critical piece for Step 2.2 — it's sent to Supabase Auth via `signInWithIdToken(provider: .apple, idToken: token)`.

### 52. Entitlements File Strategy
The `Knot.entitlements` file is the central location for all iOS app capabilities. Currently contains only Sign in with Apple. Future additions will include:
- `aps-environment` — Push notification entitlement (Step 7.4)
- `com.apple.developer.associated-domains` — Universal links for deep linking (Step 9.1)

The entitlements file is referenced in two places in `project.yml`:
1. `entitlements.path` — XcodeGen uses this to set up the Xcode project correctly
2. `CODE_SIGN_ENTITLEMENTS` — The build setting that tells the code signing process which entitlements to embed

### 53. ContentView as Auth State Router (Step 2.3)
`ContentView` is the root auth state router with three states:
1. **`isCheckingSession = true`** → Shows a loading spinner while the Supabase SDK checks the Keychain for a stored session
2. **`isAuthenticated = true`** → Shows `HomeView()`
3. **`isAuthenticated = false`** → Shows `SignInView()`

```swift
struct ContentView: View {
    @State private var authViewModel = AuthViewModel()
    var body: some View {
        Group {
            if authViewModel.isCheckingSession { ProgressView() }
            else if authViewModel.isAuthenticated { HomeView() }
            else { SignInView() }
        }
        .environment(authViewModel)
        .task { await authViewModel.listenForAuthChanges() }
    }
}
```

The `AuthViewModel` is created here and injected into the SwiftUI environment. All child views share the same auth state instance. The `.task` modifier starts the `authStateChanges` listener, which runs for the lifetime of the root view.

### 54. Apple Developer Program Requirement
Sign in with Apple requires the **paid Apple Developer Program** ($99/year) for full functionality. Without it:
- Error 1000 (`ASAuthorizationError.unknown`) occurs when tapping the sign-in button
- App IDs cannot be registered with the Sign in with Apple capability
- The Apple Sign-In sheet will not appear on the Simulator or device

The free Apple Developer account allows building and running on the Simulator but cannot access Certificates, Identifiers & Profiles. This is a prerequisite for Steps 2.1–2.4 to be fully testable end-to-end. The code implementation is correct regardless of enrollment status.

**Critical: Team Selection in Xcode**
After enrolling in the paid program, Xcode may still default to the **"Personal Team"** (the free tier). The Team dropdown in Signing & Capabilities will show two entries with the same name -- select the one that is NOT labeled "(Personal Team)". Using the Personal Team will produce: *"Cannot create a iOS App Development provisioning profile... Personal development teams do not support the Sign In with Apple capability."* The correct paid team ID for this project is `VN5G3R8J23`.

### 55. Sign in with Apple — Simulator Testing Checklist
Validated end-to-end on iPhone 17 Pro Simulator (iOS 26.2). Three prerequisites for the Apple Sign-In sheet to appear:
1. **Paid Apple Developer Program** enrolled and active
2. **Correct team selected** in Xcode Signing & Capabilities (not "Personal Team")
3. **Apple ID signed in** on the Simulator (Settings > Apple Account)

The sign-in flow returns three pieces of data:
- `credential.user` — Stable Apple user ID (e.g., `000817.ddb36fbe43e549ce802859bbb818cfc2.0307`). This never changes for the same Apple ID + app combination.
- `credential.email` — Only returned on **first** sign-in. Subsequent sign-ins return `nil`. The app must persist this on first login.
- `credential.identityToken` — JWT for server-side validation. This is sent to Supabase Auth in Step 2.2.

### 56. AuthViewModel — OIDC Nonce Flow (Step 2.2)
The `AuthViewModel` implements the OpenID Connect (OIDC) nonce pattern to prevent replay attacks:

1. **Generate nonce:** `randomNonceString()` creates a 32-character cryptographically random string using `SecRandomCopyBytes`. This is the "raw nonce."
2. **Hash for Apple:** `sha256()` hashes the raw nonce using `CryptoKit.SHA256`. The hash is set on `ASAuthorizationAppleIDRequest.nonce`. Apple embeds this hash in the identity token JWT.
3. **Send raw to Supabase:** The *unhashed* nonce is sent to Supabase via `OpenIDConnectCredentials(nonce:)`. Supabase hashes it server-side and compares against the hash embedded in the JWT — if they match, the token is valid and hasn't been replayed.

**Why `nonisolated`?** The `configureRequest()` method is `nonisolated` because `SignInWithAppleButton`'s `request` closure may run off the main actor. It uses `MainActor.assumeIsolated` to safely write `currentNonce` to the actor-isolated property. The utility methods (`randomNonceString`, `sha256`) are `nonisolated static` because they're pure functions.

### 57. SupabaseManager Singleton Pattern (Step 2.2)
`SupabaseManager` is an `enum` (not a `class` or `struct`) to prevent accidental instantiation. It exposes a single `static let client` — the `SupabaseClient` instance used throughout the app.

**Keychain session storage** is handled automatically by the Supabase Swift SDK. When `signInWithIdToken` succeeds, the SDK stores the access token, refresh token, and user metadata in the iOS Keychain. On subsequent app launches, the SDK retrieves the stored session — Step 2.3 will use this to determine if the user is already authenticated.

**Thread safety:** The `SupabaseClient` is designed to be called from any thread. The `AuthViewModel` ensures UI state updates happen on `@MainActor`, but the Supabase network calls are standard `async/await`.

### 58. XcodeGen Entitlements Regeneration Gotcha (Step 2.2)
Running `xcodegen generate` can overwrite the `Knot.entitlements` file to an empty `<dict/>` if the `entitlements` section in `project.yml` doesn't include `properties`. The fix is to declare capabilities in two places:

```yaml
# project.yml
entitlements:
  path: Knot/Knot.entitlements
  properties:                              # <-- THIS prevents overwriting
    com.apple.developer.applesignin:
      - Default
```

Without the `properties` key, XcodeGen creates a blank entitlements file. With it, the file is generated with the correct content. This is critical when adding future entitlements (push notifications, associated domains).

### 59. Supabase Anon Key Safety (Step 2.2)
The `Constants.Supabase.anonKey` is a **publishable** key — it is safe to embed in the app binary. It grants only the permissions defined by Row Level Security (RLS) policies on each table. The actual data access is controlled by the JWT (obtained after `signInWithIdToken`) which encodes the user's `auth.uid()`. All Supabase tables use RLS policies that check `auth.uid()` against the row's `user_id` column.

### 60. Session Persistence via authStateChanges (Step 2.3)
The Supabase Swift SDK provides an `AsyncSequence` called `authStateChanges` that emits `(AuthChangeEvent, Session?)` tuples. The event lifecycle:

1. **`initialSession`** — Always the first event. Contains the session restored from iOS Keychain, or `nil` if no session exists. This is the mechanism for session persistence — no manual Keychain code is needed.
2. **`signedIn`** — Emitted after a successful `signInWithIdToken` call. The `isAuthenticated` flag is set here (not in the sign-in method itself).
3. **`signedOut`** — Emitted after `signOut()`. Clears `isAuthenticated`.
4. **`tokenRefreshed`** — Emitted when the SDK silently refreshes an expired access token using the stored refresh token.
5. **`userUpdated`** — Emitted when user metadata changes.

All auth state transitions flow through this single listener (`listenForAuthChanges()` in `AuthViewModel`). This creates a **single source of truth** for auth state — no manual `isAuthenticated` assignments outside the listener.

### 61. Environment-Based ViewModel Sharing (Step 2.3)
The `AuthViewModel` is shared across the view hierarchy using SwiftUI's `@Observable` + `@Environment` pattern:

```
ContentView (@State authViewModel) ──.environment(authViewModel)──▶ SignInView (@Environment)
                                                                  ▶ HomeView (@Environment)
```

This replaces the older `@EnvironmentObject` pattern. Key implications:
- `ContentView` owns the `AuthViewModel` via `@State` (keeps it alive)
- Child views access it via `@Environment(AuthViewModel.self)` (read-only reference)
- For `$`-binding (e.g., `.alert(isPresented:)`), child views create a local `@Bindable var viewModel = authViewModel`
- All views react to the same `isAuthenticated` state — when the listener flips it, `ContentView` automatically swaps between `SignInView` and `HomeView`

### 62. isCheckingSession Anti-Flash Pattern (Step 2.3)
Without `isCheckingSession`, the app would show a flash of the Sign-In screen on every launch:
1. App starts → `isAuthenticated = false` (default) → `SignInView` renders
2. ~100ms later → Keychain check completes → `isAuthenticated = true` → `HomeView` renders

The `isCheckingSession = true` default introduces a third state (loading spinner) that absorbs this delay, preventing the jarring flash. The transition is: loading → Home (if session exists) or loading → Sign-In (if not).

### 63. HomeView Placeholder (Step 2.3 → Step 4.1)
`Features/Home/HomeView.swift` is a minimal placeholder created in Step 2.3 solely to verify session persistence navigation works. Updated in Step 2.4 to add sign-out functionality. It shows:
- Knot branding (Lucide heart icon)
- "Welcome to Knot" message
- "Session restored from Keychain" status indicator (Lucide `circleCheck` icon)
- Sign Out button (red bordered, full-width) and toolbar icon (Step 2.4)

The full Home screen (hint capture, milestone cards, network monitoring) will replace this in Step 4.1. The sign-out button will move to the Settings screen in Step 11.1.

### 64. Sign-Out Flow — Listener-Driven State (Step 2.4)
The `signOut()` method in `AuthViewModel` deliberately does NOT set `isAuthenticated = false` directly. Instead, it calls `SupabaseManager.client.auth.signOut()` and relies on the `authStateChanges` listener to handle the `signedOut` event:

```
signOut() → Supabase SDK → server invalidation + Keychain clear → emits signedOut → listener sets isAuthenticated = false → ContentView swaps to SignInView
```

This is the same pattern used for sign-in (Step 2.3): `signInWithIdToken()` does not set `isAuthenticated = true` — the `signedIn` event does. Maintaining this pattern ensures a **single source of truth** for auth state. If any future code needs to check auth state, `isAuthenticated` is always driven by the Supabase SDK's event stream, never by manual assignment.

The sign-out also invalidates the session server-side (revokes the refresh token), so even if the local Keychain were somehow restored, the session would be rejected by Supabase Auth on the next API call.

### 65. Dual Sign-Out UI Affordances (Step 2.4)
`HomeView` provides two ways to sign out:
1. **Body button** — A prominent red bordered `Button(role: .destructive)` with Lucide `logOut` icon and "Sign Out" text. Full-width, 48pt height, `.buttonStyle(.bordered)` with `.tint(.red)`. Visible and discoverable for testing.
2. **Toolbar button** — A navigation bar `ToolbarItem(placement: .topBarTrailing)` with just the `logOut` icon. Tinted `.primary` to blend with the navigation bar.

Both call `authViewModel.signOut()` inside a `Task { }` block (since `signOut()` is `async`). Both are temporary — the permanent sign-out UI will live in the Settings screen (Step 11.1). The body button will be removed when the full Home screen is built (Step 4.1).

### 66. Onboarding Navigation Architecture (Step 3.1)
The onboarding flow uses a **container + step views** pattern:

```
ContentView (auth router)
  └── OnboardingContainerView (@State OnboardingViewModel)
        ├── Progress Bar (GeometryReader + animated fill)
        ├── Step Content (@ViewBuilder switch on currentStep)
        │     ├── OnboardingWelcomeView (@Environment OnboardingViewModel)
        │     ├── OnboardingBasicInfoView (@Environment OnboardingViewModel)
        │     ├── ... (7 more step views)
        │     └── OnboardingCompletionView (@Environment OnboardingViewModel)
        └── Navigation Buttons (Back / Next / Get Started)
```

Key design decisions:
- **Single ViewModel for all steps:** Unlike the Auth flow (where `AuthViewModel` handles one concern), the `OnboardingViewModel` holds ALL onboarding data across 9 steps. This is intentional — the data is interdependent (e.g., dislikes must exclude likes, budget tiers map to milestone types) and needs to persist across back/forward navigation.
- **Container owns the ViewModel:** `OnboardingContainerView` creates `OnboardingViewModel` via `@State` and injects it into the environment. This mirrors the `ContentView` → `AuthViewModel` ownership pattern.
- **Step views are stateless readers:** Each step view reads the shared `OnboardingViewModel` from `@Environment` and writes to its data properties. No step view creates its own `@State` data — everything lives in the ViewModel.
- **`.id()` for transition animations:** The step content uses `.id(viewModel.currentStep)` to force SwiftUI to treat each step as a new view identity. Without this, SwiftUI would try to diff the views in-place and the slide transition animation wouldn't fire.

### 67. ContentView Four-State Auth Router (Step 3.1)
`ContentView` now routes between four states (up from three in Step 2.3):

1. **`isCheckingSession = true`** → Loading spinner (checking Keychain)
2. **`isAuthenticated = true && hasCompletedOnboarding = true`** → `HomeView()`
3. **`isAuthenticated = true && hasCompletedOnboarding = false`** → `OnboardingContainerView`
4. **`isAuthenticated = false`** → `SignInView()`

The `hasCompletedOnboarding` flag is currently in-memory only (resets on app relaunch). Step 3.11 will check for an existing vault on session restore to persist this across launches.

### 68. OnboardingStep Enum Design
The `OnboardingStep` enum uses `Int` raw values (0–8) for two purposes:
1. **Progress calculation:** `progress = Double(step.rawValue) / Double(totalSteps - 1)` gives 0.0–1.0
2. **Navigation:** `OnboardingStep(rawValue: current + 1)` safely advances; returns `nil` at bounds

Computed properties (`title`, `isFirst`, `isLast`) keep the container view clean — no switch statements needed for basic step metadata.

### 69. Centralized Step Validation Pattern (Step 3.2)
The `OnboardingViewModel.validateCurrentStep()` method centralizes all step-level validation in a single switch statement:

```swift
func validateCurrentStep() {
    switch currentStep {
    case .basicInfo:
        canProceed = !partnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    // Future: case .interests: canProceed = selectedInterests.count == 5
    default:
        canProceed = true
    }
}
```

This replaces the previous pattern of resetting `canProceed = true` in `goToNextStep()`/`goToPreviousStep()`. The method is called from three places:
1. **`goToNextStep()`** — validates the new step after advancing
2. **`goToPreviousStep()`** — validates the previous step when going back
3. **Step views** — via `.onAppear` (initial validation) and `.onChange(of: property)` (real-time validation as user types)

This dual-trigger approach (ViewModel-level + view-level) ensures validation is always up-to-date regardless of how the step is reached.

### 70. @Bindable Scoping and Custom Binding Strategy (Step 3.2)
`OnboardingBasicInfoView` introduces a pattern for handling bindings in views with `@Environment` `@Observable` objects:

- **Inside `body`:** `@Bindable var vm = viewModel` provides `$vm.partnerName` syntax for `TextField` and `Picker` controls. Bindings are passed as parameters to private methods (e.g., `nameSection(name: $vm.partnerName)`).
- **Inside computed properties:** `Binding(get:set:)` is used directly with the `@Environment` property (e.g., in `tenureSection`), since `@Bindable` is scoped to `body` and not accessible in other properties/methods.

This split is necessary because SwiftUI's `@Bindable` property wrapper can only be declared as a local variable inside `body`. Future step views should follow the same pattern: `@Bindable` for simple bindings in body, `Binding(get:set:)` for derived/computed bindings in extracted sub-views.

### 71. Deferred Validation Hint UX Pattern (Step 3.2)
The "Name is required to continue" hint uses a `@State private var hasInteractedWithName` flag to defer display:
- **On first load:** hint is hidden (user hasn't typed yet, showing an error would be jarring)
- **After first keystroke:** `hasInteractedWithName = true` (set via `.onChange(of: partnerName)`)
- **After clearing:** hint appears (user had text and deleted it — this is a meaningful validation failure)
- **After navigating away and back:** `hasInteractedWithName` resets to `false` (view is recreated via `.id()`) — hint is hidden again because the user must have had a valid name to leave the step

This pattern should be reused for any required field that starts empty. It decouples the validation error UX (when to show the message) from the `canProceed` validation logic (which always runs, even on first load).

### 72. Keyboard Submit Chaining Pattern (Step 3.2)
`OnboardingBasicInfoView` uses `@FocusState` with a `Field` enum to chain keyboard submit actions:
```
Name → (submit) → City → (submit) → State → (submit) → Dismiss keyboard
```
Each `TextField` uses `.focused($focusedField, equals: .fieldCase)` and `.onSubmit { focusedField = .nextField }`. The last field sets `focusedField = nil` to dismiss the keyboard. Combined with `.scrollDismissesKeyboard(.interactively)` on the `ScrollView`, this provides a smooth keyboard experience.

### 73. Tenure Decomposition Pattern (Step 3.2)
The ViewModel stores relationship tenure as a single integer (`relationshipTenureMonths: Int`). The UI decomposes this into two pickers (years 0–30 and months 0–11) using custom `Binding(get:set:)`:
- **get:** `viewModel.relationshipTenureMonths / 12` for years, `% 12` for months
- **set:** Recomposes as `newYears * 12 + remainingMonths` or `currentYears * 12 + newMonths`

This keeps the ViewModel data model simple (matches the database `relationship_tenure_months` integer column in `partner_vaults`) while providing an intuitive UI. The summary line (`"2 years, 6 months"`) is a computed property on the view that reads the ViewModel value.

### 74. Backend Auth Middleware — Server-Side Token Validation (Step 2.5)
The `get_current_user_id` FastAPI dependency validates tokens by calling Supabase's GoTrue API (`GET /auth/v1/user`) rather than decoding JWTs locally. Key design decisions:
- **Server-side validation over local JWT decode:** Ensures tokens are validated against the live session state — revoked sessions, expired tokens, and tampered JWTs are all properly rejected. The tradeoff is a network round-trip to Supabase on every authenticated request (~50-100ms), which is acceptable for MVP volume.
- **`HTTPBearer(auto_error=False)`:** By default, FastAPI's `HTTPBearer` returns 403 when the Authorization header is missing. Setting `auto_error=False` gives us control to return 401 with a descriptive message and `WWW-Authenticate: Bearer` header (RFC 7235 compliance).
- **`apikey` header required by Supabase:** Supabase's API gateway (Kong) requires the `apikey` header on every request, even authenticated ones. The anon key is used here — it's safe because actual access control is enforced by the Bearer token (JWT) and RLS policies, not the apikey.
- **Lazy `_get_apikey()` import:** The helper uses `from app.core.config import SUPABASE_ANON_KEY` inside the function body to avoid circular imports when `security.py` is imported at module level by `main.py`.
- **All failure paths return 401:** Missing token, invalid token, expired token, network errors, and malformed responses all raise `HTTPException(401)` with descriptive detail messages. This ensures the client always knows the issue is authentication-related.
- **Usage pattern:** All protected route handlers use `user_id: str = Depends(get_current_user_id)` to inject the authenticated user's UUID. The vault, hints, and recommendations endpoints will all follow this pattern.

### 75. Auth Middleware Test Strategy (Step 2.5)
The `test_auth_middleware.py` tests use a different approach from database table tests:
- **FastAPI TestClient:** Tests use `TestClient(app)` from `fastapi.testclient` to make HTTP requests against the actual FastAPI app in-process, not against a deployed server. This tests the full middleware pipeline (header extraction → Supabase validation → user ID return).
- **Real Supabase auth users:** The `test_auth_user_with_token` fixture creates a real auth user via the Admin API, signs them in to get a valid JWT, and cleans up on teardown. This tests against real Supabase infrastructure, not mocks.
- **`time.sleep(0.5)` in fixture:** After creating the auth user, the fixture waits 500ms for the `handle_new_user` trigger to fire and create the `public.users` row. Without this, the sign-in may race the trigger.
- **Comprehensive negative testing:** Tests verify not just that invalid tokens return 401, but also: garbage strings, structurally valid but fabricated JWTs (proves middleware validates with Supabase, not just format), empty bearers, Basic auth instead of Bearer, and raw tokens without the "Bearer " prefix.

### 50. Complete Database Schema Summary (End of Phase 1)
With Phase 1 complete, the full database schema consists of 12 tables:

| # | Table | Parent FK | Delete Behavior | RLS Pattern |
|---|-------|-----------|----------------|-------------|
| 1 | `users` | `auth.users` | CASCADE | Direct (`id = auth.uid()`) |
| 2 | `partner_vaults` | `users` | CASCADE | Direct (`user_id = auth.uid()`) |
| 3 | `partner_interests` | `partner_vaults` | CASCADE | Vault subquery |
| 4 | `partner_milestones` | `partner_vaults` | CASCADE | Vault subquery |
| 5 | `partner_vibes` | `partner_vaults` | CASCADE | Vault subquery |
| 6 | `partner_budgets` | `partner_vaults` | CASCADE | Vault subquery |
| 7 | `partner_love_languages` | `partner_vaults` | CASCADE | Vault subquery |
| 8 | `hints` | `partner_vaults` | CASCADE | Vault subquery |
| 9 | `recommendations` | `partner_vaults` + `partner_milestones` | CASCADE + SET NULL | Vault subquery |
| 10 | `recommendation_feedback` | `recommendations` + `users` | CASCADE + CASCADE | Direct (`user_id = auth.uid()`) |
| 11 | `notification_queue` | `users` + `partner_milestones` | CASCADE + CASCADE | Direct (`user_id = auth.uid()`) |

Total test count: **345 tests** across 16 test files (291 database/infrastructure + 14 auth middleware + 40 vault API).

### 51. Badge overlay pattern (`ZStack` vs inline `HStack`)
When adding selection badges (e.g., "PRIMARY", "SECONDARY") to cards, **never** place them inline with text content in an `HStack` — long text like "Words of Affirmation" will wrap when the badge appears, causing layout jank. Instead, use a `ZStack(alignment: .topTrailing)` with the badge as a separate overlay layer. The text content (`HStack` with icon + name + description) sits in one layer; the badge floats in the top-right corner in another layer. This pattern keeps text layout completely stable regardless of selection state. Used in `LoveLanguageCard` (Step 3.8); should be adopted for any future card components with dynamic badges.

### 52. Love language selection state as `Equatable` enum
`LoveLanguageSelectionState` is a `private enum` with three cases: `.unselected`, `.primary`, `.secondary`. It conforms to `Equatable` (not `Sendable` — only used in view code). The `.animation(.easeInOut, value: selectionState)` modifier on `LoveLanguageCard` uses this as its value parameter, enabling smooth transitions between all three visual states in a single animation declaration. This pattern (dedicated selection enum + value-based animation) is cleaner than using multiple boolean flags.

### 53. Two-step selection with single handler function
The love languages screen implements a two-step selection (primary then secondary) with a single `selectLanguage()` function that handles 5 branches in priority order: (1) tap primary → clear both, (2) tap secondary → clear it, (3) no primary → set primary, (4) no secondary → set secondary, (5) replace secondary. This keeps the logic centralized rather than split across separate "select primary" / "select secondary" functions. The priority ordering matters — tapping the current primary always resets, regardless of whether a secondary exists.

### 54. Love language gradients are hand-tuned (like vibes)
Each love language card has a manually defined 2-color gradient that semantically matches the language's meaning (warm peach for affirmation, teal for service, amber for quality time, etc.). This follows the same pattern as vibes (note #46) — with only 5 options, curated colors are worth the effort vs. algorithmic hue rotation.

### 76. Pydantic Validation as First Line of Defense (Step 3.10)
The `VaultCreateRequest` model in `app/models/vault.py` implements a three-tier validation strategy:

1. **`Literal` type constraints** — FastAPI auto-generates 422 errors for invalid enum values (e.g., `cohabitation_status` must be one of 3 values). No custom validator needed.
2. **`@field_validator` methods** — Per-field rules: count checks (exactly 5 interests), membership checks (interest must be in `VALID_INTEREST_CATEGORIES`), uniqueness checks (no duplicate vibes). These run before the model validator.
3. **`@model_validator(mode="after")` methods** — Cross-field rules: `validate_no_interest_overlap` checks that `interests` and `dislikes` are disjoint. This runs after all field validators complete, so it can safely access validated fields.

This mirrors the database's own validation layers (CHECK constraints for enum values, UNIQUE constraints for deduplication) but catches errors earlier with more descriptive error messages. The database constraints serve as a safety net in case the API layer is bypassed.

### 77. Service Client for Multi-Table API Endpoints (Step 3.10)
The `create_vault()` endpoint uses `get_service_client()` (service_role key, bypasses RLS) rather than the anon client. This design choice:

- **Why not the anon client?** The anon client respects RLS, which requires the user's JWT to be set on the client. The Supabase Python client doesn't have a per-request JWT injection mechanism suitable for a stateless FastAPI endpoint.
- **Why is it safe?** The user's identity is validated by `get_current_user_id` (the auth middleware dependency). The endpoint only inserts data where `user_id` matches the authenticated user. The service_role client bypasses RLS but the application code enforces the same access boundary.
- **Pattern for future endpoints:** All vault/hints/recommendations endpoints that need to write data on behalf of an authenticated user should follow this pattern: auth middleware validates identity → service client performs the write with the validated `user_id`.

### 78. Pseudo-Transactional Multi-Table Insert Pattern (Step 3.10)
PostgREST does not support multi-table transactions. The vault creation endpoint inserts into 6 tables sequentially. If a later insert fails:

1. The `except` block in `create_vault()` calls `_cleanup_vault(client, vault_id)`
2. `_cleanup_vault()` deletes the vault row from `partner_vaults`
3. CASCADE on `partner_vaults` automatically removes all child rows (interests, milestones, vibes, budgets, love languages)
4. The original error is re-raised as an `HTTPException`

This "compensating transaction" pattern is acceptable for MVP volume. For production, consider:
- A Supabase Edge Function (server-side JS with proper SQL transactions)
- A PostgreSQL stored procedure called via RPC
- A Supabase realtime/database function that handles the full insert

### 79. Vault API Test Patterns (Step 3.10)
The `test_vault_api.py` introduces several test patterns for API endpoint testing:

- **`_valid_vault_payload()` helper:** Returns a complete, valid JSON payload that can be shallow-copied and modified per test. Avoids repeating 40+ lines of setup in each test.
- **`_query_table(table, vault_id)` helper:** Queries PostgREST directly with the service_role key to verify data integrity in child tables. This is separate from the API response verification — it confirms data actually reached the database.
- **`_auth_headers(token)` helper:** Simple wrapper to build `{"Authorization": "Bearer ..."}` headers.
- **Validation tests modify one field at a time:** Each test starts with the valid payload and makes exactly one invalid change, then asserts 422. This isolates the specific validation rule being tested and prevents false negatives.
- **Data integrity tests verify all 6 tables independently:** Separate tests for each table (interests, milestones, vibes, budgets, love languages) with field-level assertions. This pinpoints exactly which table/field has the issue if a test fails.

### 80. `VALID_*` Constants as Shared Source of Truth (Step 3.10)
The `app/models/vault.py` file exports `VALID_INTEREST_CATEGORIES`, `VALID_VIBE_TAGS`, and `VALID_LOVE_LANGUAGES` as `set[str]` constants. These serve as the backend's source of truth for valid enum values, mirroring:
- **Database:** CHECK constraints in the SQL migrations (e.g., `interest_category IN ('Travel', 'Cooking', ...)`)
- **iOS:** `Constants.interestCategories`, `Constants.vibeOptions`, `Constants.loveLanguages` in `Constants.swift`

All three sources must stay in sync. When adding a new interest category or vibe:
1. Add to the SQL migration (new migration file for DB ALTER)
2. Add to `VALID_*` in `app/models/vault.py`
3. Add to `Constants` in `iOS/Knot/Core/Constants.swift`

### 81. iOS-to-Backend Communication Pattern (Step 3.11)
The iOS app communicates with the FastAPI backend via standard HTTP requests using `URLSession`. The flow:
1. `VaultService` gets the Supabase access token from `SupabaseManager.client.auth.session`
2. Sets `Authorization: Bearer {token}` header on the request to the FastAPI backend
3. FastAPI's `get_current_user_id` middleware validates the token against Supabase Auth's `/auth/v1/user` endpoint
4. The backend uses `get_service_client()` (bypasses RLS) to insert data on behalf of the validated user

This pattern keeps the iOS app thin (no direct database writes for vault creation) while using the same Supabase JWT for both Supabase PostgREST queries (vault existence check) and FastAPI authentication.

### 82. Vault Existence Check via PostgREST (Step 3.11)
The `VaultService.vaultExists()` method queries Supabase PostgREST directly from the iOS app (not through the FastAPI backend) to check if the user already has a vault. This is used in two places:
- `AuthViewModel.initialSession` — On app relaunch, determines whether to show onboarding or Home
- `AuthViewModel.signedIn` — On returning user sign-in, determines the same

The query uses the anon client with RLS: `SELECT id FROM partner_vaults LIMIT 1`. Row Level Security automatically scopes the result to the authenticated user's vault. This avoids adding a `GET /api/v1/vault` endpoint prematurely (planned for Step 3.12).

### 83. Conditional Backend URL with `#if DEBUG` (Step 3.11)
`Constants.API.baseURL` uses a Swift `#if DEBUG` conditional:
- **Debug builds** (Xcode development): `http://127.0.0.1:8000` (local FastAPI server)
- **Release builds** (App Store): `https://api.knot-app.com` (production Vercel deployment)

This eliminates the need to manually swap URLs before deployment. The `Info.plist` includes `NSAllowsLocalNetworking = true` to permit HTTP for localhost without disabling ATS globally.

### 84. VaultServiceError Typed Error Handling (Step 3.11)
`VaultServiceError` is a `LocalizedError`-conforming enum with 6 cases. Each case provides a user-friendly `errorDescription` string displayed in the alert. Network errors are further differentiated by `URLError.code` (no internet vs. timeout vs. cannot connect). The error parsing handles two FastAPI response formats:
- **String detail** (`{"detail": "A partner vault already exists..."}`) — for 409, 500 errors
- **Array detail** (`{"detail": [{"msg": "..."}]}`) — for 422 Pydantic validation errors

### 85. Loading Overlay and Submission Guard Pattern (Step 3.11)
The `OnboardingContainerView` uses a layered approach for submission UX:
1. `viewModel.isSubmitting` drives a full-screen loading overlay (dimmed background + spinner + message)
2. The "Get Started" button is `.disabled(viewModel.isSubmitting)` to prevent double-taps
3. On failure, an `.alert` with "Try Again" and "Cancel" buttons appears
4. "Try Again" re-calls `submitVault()` with the same payload — no data re-entry needed
5. The `isSubmitting` flag is reset via `defer { isSubmitting = false }` in `submitVault()` to guarantee cleanup even on unexpected errors

### 86. Auth State and Vault Check Ordering (Step 3.11)
The `AuthViewModel.listenForAuthChanges()` handler was restructured for correct ordering:
- **Before Step 3.11:** `isCheckingSession = false` was set immediately after `initialSession`
- **After Step 3.11:** `isCheckingSession = false` is set AFTER the vault existence check completes

This ensures the loading spinner stays visible during both the session restore AND the vault check. Without this ordering, the user would briefly see onboarding flash before being redirected to Home.

The `signedOut` handler resets `hasCompletedOnboarding = false` so that if a different user signs in on the same device, they get their own vault check (not the previous user's state).

### 87. iOS Integration Test Pattern (Step 3.11)
`test_step_3_11_ios_integration.py` introduces an "iOS simulation" test pattern:
- `_ios_onboarding_payload()` builds the EXACT JSON the iOS DTOs produce (including `budget_tier: null` for birthday, `"minor_occasion"` for custom milestones, amounts in cents)
- Tests verify both the API response AND the database state in all 6 tables
- The vault existence check is tested by making raw PostgREST requests with the user's JWT (same query the iOS `VaultService.vaultExists()` makes)
- The returning user test creates two separate sign-in sessions and verifies the vault persists across them

### 88. Network Monitoring via NWPathMonitor (Step 4.1)
`NetworkMonitor` is an `@Observable @MainActor` class using Apple's `NWPathMonitor` (from the `Network` framework) on a dedicated `DispatchQueue`. The monitor's `pathUpdateHandler` dispatches updates to `@MainActor` via `Task { @MainActor in ... }`, making `isConnected` safe for direct SwiftUI binding. Key design decisions:
- Created as `@State` in `HomeView` (not injected via environment) because only the Home screen uses it. If future screens need connectivity info, promote to environment injection from `ContentView`.
- Starts immediately on `init()` and cancels on `deinit` — no manual start/stop lifecycle management needed.
- The `[weak self]` capture in `pathUpdateHandler` prevents retain cycles with the `Task` closure.

### 89. HomeViewModel Data Loading Pattern (Step 4.1)
`HomeViewModel` follows the same `@Observable @MainActor` pattern as `OnboardingViewModel` and `AuthViewModel`. It loads vault data via `.task { await viewModel.loadVault() }` on the view's appearance, and refreshes via `.onChange(of: showEditProfile)` when returning from Edit Profile. Key design decisions:
- `HomeViewModel` is created as `@State` in `HomeView` (not shared via environment) because it's scoped to the Home screen lifecycle. Unlike `AuthViewModel` (which must be shared across the entire app for auth state), the Home screen's data doesn't need cross-feature access.
- Milestone countdown uses `Calendar.current` for locale-aware date computations. Year rollover is handled by trying the current year first, then falling back to next year if the date has already passed.
- `vibeDisplayName()` is a private helper in `HomeView` that converts snake_case to Title Case inline. It does NOT use `OnboardingVibesView.displayName(for:)` to avoid coupling the Home feature to the Onboarding module. If more features need vibe display names, extract to a shared utility in `/Core/`.

### 90. Milestone Urgency Color System (Step 4.1)
Milestones on the Home screen use a 4-tier urgency color system based on `daysUntil`:
| Days Until | Urgency Level | Color | Purpose |
|-----------|--------------|-------|---------|
| 0–3 | `.critical` | Red | Immediate action needed |
| 4–7 | `.soon` | Orange | Action needed this week |
| 8–14 | `.upcoming` | Yellow | Plan ahead |
| 15+ | `.distant` | Pink (accent) | Informational |

This coloring is applied consistently to the countdown badge, milestone subtitle, milestone card icon background, and countdown capsule pill. The `UpcomingMilestone.urgencyLevel` enum centralizes the logic so all components use the same thresholds.

### 91. Backend Server Must Match Code Version (Step 4.1)
If the uvicorn server was started before certain code changes (e.g., before Step 3.10 vault routes), it continues running the OLD code without the new routes. This causes 404 errors for routes that exist in the source but weren't loaded at server start. Always restart the backend after code changes: `kill $(lsof -i :8000 -t) && cd backend && source venv/bin/activate && uvicorn app.main:app --host 127.0.0.1 --port 8000`. Consider adding `--reload` flag during development: `uvicorn app.main:app --reload` to auto-restart on file changes.

### 92. HintService Mirrors VaultService Pattern (Step 4.2)
`HintService` follows the exact same architecture as `VaultService`: `@MainActor` class, typed error enum (`HintServiceError` with 6 cases matching `VaultServiceError`), Bearer token auth via `getAccessToken()`, `URLSession.shared` for HTTP, `JSONEncoder`/`JSONDecoder` for serialization, and the same two-format error parsing (`StringErrorResponse` for 404/500 errors, `ArrayErrorResponse` for 422 Pydantic validation errors). New: `mapURLError()` helper extracts the URL error code mapping into a reusable private method (not duplicated in-line like VaultService). If a third service is created, consider extracting a shared `BaseAPIService` class or protocol to eliminate the duplication.

### 93. Hint Embedding Deferred to Step 4.4 (Step 4.2)
The `POST /api/v1/hints` endpoint inserts hints with `hint_embedding = NULL`. The `hints` table has a `vector(768)` column with an HNSW index, but it's not populated yet. Step 4.4 will add Vertex AI `text-embedding-004` embedding generation (768 dimensions) as an async step in the create endpoint. The `GET /api/v1/hints` endpoint explicitly selects only `id, hint_text, source, is_used, created_at` (excludes `hint_embedding`) to avoid transferring the large vector over the wire for display purposes.

### 94. Optimistic UI for Hint Submission (Step 4.2)
The hint text input is cleared IMMEDIATELY when the user taps submit (before the API call completes). This provides instant feedback and prevents the user from accidentally re-submitting. The async API call runs in a `Task` block. On success, the checkmark animation appears and recent hints refresh. On failure, an error message appears below the now-empty input. This "optimistic clear" pattern prioritizes responsiveness over data consistency — the user sees the input clear instantly, then the success/error state 200-500ms later when the API responds.

### 95. ISO 8601 Date Parsing for Supabase Timestamps (Step 4.2)
Supabase returns timestamps with microsecond precision (e.g., `"2026-02-08T12:34:56.789012+00:00"`). `HomeViewModel.parseISO8601(_:)` uses `ISO8601DateFormatter` with `.withFractionalSeconds` as the primary parse, falling back to `.withInternetDateTime` (without fractional seconds) for simpler formats. This is a `static` method so it can be tested independently and called from mapping closures without capturing `self`.

### 96. Hint API Uses vault_id Lookup Pattern (Step 4.2)
Both `POST` and `GET /api/v1/hints` first look up the user's `vault_id` from `partner_vaults` using the authenticated `user_id`. This ensures: (1) the user has completed onboarding before using hints, (2) hints are scoped to the correct vault, and (3) the vault_id foreign key constraint is always satisfied. If the vault doesn't exist, a 404 is returned with "No partner vault found. Complete onboarding first." This is the same pattern used by future hint-dependent features (recommendations, feedback).

### 97. Success Animation State Machine (Step 4.2)
The hint success animation uses a simple state machine in `HomeViewModel`: `showHintSuccess` starts `false` → set to `true` on API success → drives green checkmark overlay + green border stroke in `HomeView` → auto-reset to `false` after `Task.sleep(for: .seconds(1.5))`. The animation uses `.animation(.easeInOut(duration: 0.3), value: viewModel.showHintSuccess)` on the outer `ZStack` and `.transition(.scale.combined(with: .opacity))` on the checkmark `HStack`. The `TextEditor` opacity is set to 0 during success to prevent text bleeding through the overlay.

### 98. SwiftUI List Required for Swipe Actions (Step 4.5)
SwiftUI's `.swipeActions()` modifier only works properly with `List` views, not with `ScrollView` + `LazyVStack`. The initial `HintsListView` implementation used a `ScrollView`, which caused swipe gestures to fail completely. Converted to `List` with custom styling: `.listStyle(.plain)` removes the default grouped appearance, `.listRowBackground(Color.clear)` makes rows transparent so the background gradient shows through, `.listRowSeparator(.hidden)` removes divider lines, and `.listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))` controls spacing around each row. The row content (card with rounded corners, surface background) is identical to the ScrollView version. **Rule:** Always use `List` (not `ScrollView`) when implementing swipe-to-delete or swipe actions.

### 99. Swipe Direction is Right-to-Left for Trailing Actions (Step 4.5)
`.swipeActions(edge: .trailing)` appears on the **trailing edge**, which in left-to-right locales means the right side. To reveal the action buttons, the user must swipe **from right to left** (not left to right). This is standard iOS behavior — Mail, Messages, Reminders all use this pattern. The `allowsFullSwipe: true` parameter enables the "full swipe to delete" gesture (swipe all the way across to delete without tapping the button).

### 100. Placeholder Deletion Pattern for Step 4.6 (Step 4.5)
`HintsListViewModel.deleteHint(id:)` currently removes hints from the local `hints` array after a 300ms simulated delay (`Task.sleep`). This allows the swipe-to-delete UI to be tested and validated before the backend `DELETE /api/v1/hints/{id}` endpoint exists. Step 4.6 will replace the placeholder with `try await hintService.deleteHint(id: id)` calling the real API. The ViewModel's interface doesn't change — only the implementation is swapped. This "placeholder then real" pattern lets UI and backend be developed in parallel without blocking.

### 101. HintItem vs HintItemResponse Separation (Step 4.5)
`HintItemResponse` (in `/Models/DTOs.swift`) is the wire format from the backend with `createdAt: String` (ISO 8601 timestamp). `HintItem` (in `HintsListViewModel.swift`) is the display model with `createdAt: Date` (parsed Foundation type). The ViewModel maps between them in `loadHints()`. This separation keeps the DTO layer focused on serialization (snake_case, string dates) while the display model provides SwiftUI-friendly types (`.date` and `.time` format styles work directly on `Date`, not on `String`). If other views need `HintItem`, extract it to a shared location. For now, it's scoped to the ViewModel file since only `HintsListView` uses it.

### 102. Upstash-Not-Before for Unlimited-Duration Scheduling (Step 7.2)
`publish_to_qstash()` now supports both `delay_seconds` and `not_before` parameters. `Upstash-Delay` is capped at 7 days (604800 seconds) by QStash, which is insufficient for scheduling a 14-day notification for a milestone 60 days out (would require a 46-day delay). `Upstash-Not-Before` accepts a Unix timestamp with no duration limit. The notification scheduler exclusively uses `not_before` for this reason. The two parameters are mutually exclusive — if both are provided, QStash honors `not_before`.

### 103. Floating Holiday Resolution at Scheduling Time (Step 7.2)
Mother's Day (2nd Sunday of May) and Father's Day (3rd Sunday of June) are stored in `partner_milestones` with approximate fixed dates (May 11, Jun 15) set during onboarding. The actual calendar-correct dates are computed dynamically by `compute_next_occurrence()` at notification scheduling time using `_mothers_day(year)` and `_fathers_day(year)`. Detection is via case-insensitive substring matching on `milestone_name` — "mother" triggers Mother's Day computation, "father" triggers Father's Day. This decouples the milestone identity (which holiday) from the calendar computation (which date this year).

### 104. CASCADE-Based Notification Cleanup on Vault Update (Step 7.2)
When `update_vault()` replaces milestones (DELETE old + INSERT new), the `ON DELETE CASCADE` foreign key on `notification_queue.milestone_id` automatically removes all associated notification entries. No manual cancellation logic is needed. Orphaned QStash messages (already published but targeting deleted notification_queue rows) will receive a 404 from the process endpoint when they fire, and QStash will stop retrying after the configured retry count. New milestones get new UUIDs, so deduplication IDs (`{milestone_id}-{days_before}`) never collide between old and new.

### 105. Fire-and-Forget Notification Scheduling (Step 7.2)
Notification scheduling in vault POST and PUT endpoints is wrapped in `try/except` with `logger.warning()`. A QStash API failure (timeout, rate limit, misconfigured credentials) must never cause vault creation or update to fail — the user's data operation is more important than scheduling notifications. If scheduling fails, the `notification_queue` entries may or may not have been created (depends on where the failure occurred), but the vault data is intact. A future background job could re-scan milestones and schedule any missing notifications.

### 106. Graceful Degradation Without QStash (Step 7.2)
`notification_queue` entries are always inserted into the database regardless of QStash availability. Only the `publish_to_qstash()` call is conditionally skipped when `is_qstash_configured()` returns `False`. This enables: (1) local development without QStash credentials, (2) testing of DB entries in isolation, (3) a future fallback path where a daily cron job could process pending notifications directly instead of relying on QStash delivery.

### 107. Vault Loader as Shared Service (Step 7.3)
`app/services/vault_loader.py` consolidates the ~140-line vault data loading pattern that was duplicated between `generate_recommendations` and `refresh_recommendations`. With Step 7.3 adding a third consumer (notification processing), the duplication would have tripled. The service exposes three functions: `load_vault_data()` (5 table queries → `VaultData`), `load_milestone_context()` (1 table query → `MilestoneContext`), and `find_budget_range()` (pure logic, no DB). All three callers now use identical loading logic, ensuring consistency when the vault schema changes. The `load_vault_data()` function raises `ValueError` for missing vaults — callers convert this to `HTTPException(404)` (recommendations API) or log-and-continue (notification processor), depending on their error handling strategy.

### 108. Notification Processing Recommendation Generation (Step 7.3)
The notification processor's recommendation generation block (Step 6 in the endpoint) is deliberately isolated from the status update (Step 7). The entire recommendation block — vault loading, milestone loading, pipeline execution, DB insertion — is wrapped in a single `try/except Exception`. Any failure within this block logs a warning and sets `recommendations_generated=0`, but does not prevent the notification from being marked as 'sent'. This design prevents QStash from retrying indefinitely when vault data is missing or the AI pipeline is down. The recommendations can always be generated on-demand when the user opens the app.

### 109. Notification Response Model Extension (Step 7.3)
`NotificationProcessResponse` was extended with `recommendations_generated: int = Field(default=0)`. The `default=0` is critical — it means existing code paths that don't generate recommendations (e.g., "skipped" responses for already-processed notifications) don't need to specify the field. The field enables monitoring: a dashboard can alert when `recommendations_generated=0` for `status="processed"` responses, indicating pipeline failures that need investigation.

### 110. APNs Push Service Architecture (Step 7.5)
`app/services/apns.py` is a self-contained APNs integration with four layers: (1) **auth key loading** (`_load_auth_key()` reads the .p8 file from disk), (2) **JWT generation** (`_generate_apns_token()` with 50-minute caching), (3) **payload construction** (`build_notification_payload()` — pure function, no side effects), (4) **HTTP delivery** (`send_push_notification()` via `httpx.AsyncClient(http2=True)`). The high-level `deliver_push_notification()` composes all four layers and adds device token lookup from the database. Each layer can be tested independently — payload builder tests are pure unit tests, JWT tests mock the key file, HTTP tests mock `httpx.AsyncClient`, and delivery tests mock both the DB client and `send_push_notification()`.

### 111. APNs Push Delivery as Non-Blocking Step (Step 7.5)
The notification webhook's processing pipeline has a deliberate ordering: (1) verify signature, (2) parse payload, (3) check notification status, (4) generate recommendations, (5) **deliver push notification**, (6) update status to 'sent'. Push delivery (step 5) is sandwiched between recommendation generation and the status update, both wrapped in their own `try/except`. This means a push delivery failure cannot prevent the notification from being marked as 'sent' — the same graceful degradation pattern from Step 7.3. Push delivery only fires when two conditions are met: `is_apns_configured()` returns `True` AND `recommendations_count > 0`. Sending a push with zero recommendations would be a bad user experience (tapping the notification would show nothing).

### 112. APNs JWT Token Caching Strategy (Step 7.5)
APNs provider tokens are valid for up to 60 minutes. The service caches tokens for 50 minutes (`TOKEN_REFRESH_INTERVAL = 3000`) with module-level `_cached_token` and `_token_generated_at` variables. The 10-minute buffer prevents edge cases where a token generated at minute 59 expires mid-request. The caching is critical for performance — JWT generation requires reading the .p8 key file from disk and performing ES256 signing. The cache is intentionally not thread-safe (no lock) because FastAPI uses async concurrency, not threading, and the worst case of a race condition is generating two tokens instead of one (both valid).

### 113. APNs `deliver_push_notification()` Uses Late Import (Step 7.5)
The `get_service_client` import is inside the function body (`from app.db.supabase_client import get_service_client`) rather than at module top level. This mirrors the pattern in other services and prevents circular import chains — `apns.py` is imported by `notifications.py` (API layer), which also imports from `db/supabase_client.py`. The late import ensures the Supabase client module is fully initialized before first use, regardless of import order.

### 114. Notification History Endpoint Joins Across Three Tables (Step 7.7)
`GET /api/v1/notifications/history` performs three sequential queries per request: (1) notification_queue WHERE user_id AND status IN ('sent', 'failed') ORDER BY sent_at DESC, (2) partner_milestones by ID for each notification's milestone metadata (name, type, date), (3) recommendations COUNT per milestone_id via vault_id lookup. Deleted milestones are handled gracefully with "Deleted Milestone" / "unknown" fallbacks. The endpoint uses `Depends(get_current_user_id)` for auth (not QStash signature like the webhook), making it the first notifications.py endpoint with standard user auth. Recommendation counting requires a vault_id lookup from partner_vaults — if the vault is deleted, recommendations_count defaults to 0.

### 115. Read-Only By-Milestone Recommendations Endpoint (Step 7.7)
`GET /api/v1/recommendations/by-milestone/{milestone_id}` is deliberately read-only — it returns existing recommendations from the DB but never triggers the LangGraph pipeline. This is architecturally different from `POST /generate` and `POST /refresh` which run the full pipeline. The separation ensures the history screen loads instantly (no 10-30 second AI pipeline wait) and prevents duplicate recommendation generation. Recommendations were already generated when the notification fired (Step 7.3). The endpoint validates vault ownership by looking up the user's vault_id first, then filtering recommendations by both vault_id and milestone_id. Returns up to 10 results (most recent, usually 3 from a single generation batch).

### 116. Fire-and-Forget Mark-Viewed Pattern (Step 7.7)
The iOS `NotificationsViewModel.selectNotification()` method uses a fire-and-forget pattern for marking notifications as viewed: it calls `service.markViewed(notificationId:)` which never throws (catches all errors internally and logs to console), then immediately updates the local `notifications` array by creating a copy of the notification item with `viewedAt` set to the current ISO 8601 timestamp. This removes the unviewed accent dot immediately without waiting for the network round-trip. The backend `PATCH /viewed` endpoint is idempotent — calling it multiple times on an already-viewed notification simply updates the timestamp again.

### 117. Notification Row Three-Layer Visual Hierarchy (Step 7.7)
Each notification history row in `NotificationsView` uses a three-layer information hierarchy designed for quick scanning: (1) **Recognition layer** — a milestone type SF Symbol icon (gift.fill for birthday, heart.fill for anniversary, star.fill for holiday, calendar.badge.clock for custom) in an accent-tinted rounded rect, providing instant visual type recognition. (2) **Context layer** — milestone name (bold, 1-line), days-before label + formatted date, status badge (green "Delivered" capsule or red "Failed" capsule with checkmark/xmark SF Symbols), and recommendation count with Lucide sparkles icon. An accent-colored 7pt Circle dot appears next to the milestone name when `viewedAt == nil && status == "sent"`, providing unread status at a glance. (3) **Action layer** — a Lucide chevronRight indicator appears only when `recommendationsCount > 0`, signaling tappability. Tapping is disabled for notifications with zero recommendations.

### 118. Phase 7 Notification Test Architecture (Step 7.8)
The notification system is validated by 7 test files containing 202 tests, organized by subsystem:

| Test File | Tests | Subsystem | Strategy |
|-----------|-------|-----------|----------|
| `test_qstash_webhook.py` | 25 | QStash JWT verification, webhook routing | Unit (mocked QStash keys, mocked Supabase) + integration (real Supabase for webhook processing) |
| `test_notification_queue_table.py` | 26 | DB schema, RLS, cascades | Integration (real Supabase — verifies table structure, column constraints, RLS policies, CASCADE deletes) |
| `test_notification_scheduler.py` | 34 | Milestone date computation, QStash scheduling | Unit (pure date math, mocked QStash publish) + integration (real Supabase for DB inserts) |
| `test_notification_processing.py` | 18 | Vault loading, LangGraph pipeline | Unit (mocked pipeline, mocked Supabase) + integration (real Supabase for recommendation storage) |
| `test_apns_push_service.py` | 43 | APNs payload, JWT tokens, HTTP/2 delivery | Unit (mocked httpx, mocked file I/O for .p8 keys) — no real APNs calls |
| `test_dnd_quiet_hours.py` | 35 | Quiet hours logic, timezone inference | Unit (pure timezone math, mocked DB) + integration (mocked webhook with DND check) |
| `test_notification_history.py` | 21 | History API, mark-viewed, by-milestone | Unit (mocked Supabase client) + integration (real Supabase for full CRUD flows) |

**Key test patterns across Phase 7:**
- **Credentials gating:** All integration tests use `@pytest.mark.skipif(not _supabase_configured())` so CI can run unit tests without Supabase credentials while developers run the full suite locally.
- **Fixture cleanup:** Integration tests create auth users and data in setup, then CASCADE-delete the auth user in teardown to clean up all related rows (vaults, milestones, notifications, recommendations).
- **Mock layering:** External services (QStash, APNs, LangGraph, Vertex AI) are always mocked via `unittest.mock.patch`. Only Supabase is optionally real for integration tests.
- **datetime mock passthrough:** When mocking `datetime.now()`, the mock must also pass through `datetime(...)` constructor calls via `side_effect = lambda *args, **kwargs: datetime(*args, **kwargs)` to avoid `MagicMock` objects leaking into timezone-aware datetime operations.

### 119. YelpService Four-Layer Architecture (Step 8.1)
`app/services/integrations/yelp.py` is the first external API integration for Phase 8, replacing stub experience/date data in `aggregation.py`. The service has four layers: (1) **config** — `is_yelp_configured()` checks for `YELP_API_KEY` env var, returns early with `[]` if missing; (2) **HTTP** — `_make_request()` sends authenticated GET requests via `httpx.AsyncClient` with Bearer token, retries up to 3 times with exponential backoff (1s, 2s, 4s) on HTTP 429, and returns `{"businesses": []}` on timeout, HTTP errors, or connection errors; (3) **normalization** — `_normalize_business()` converts raw Yelp business JSON to `CandidateRecommendation`-compatible dicts with UUID generation, currency detection, price estimation, type classification (date vs experience), and metadata extraction; (4) **search** — `search_businesses()` builds location strings, constructs query params (categories, price filter, limit), calls the API, and batch-normalizes results.

### 120. Vibe-to-Yelp Category Mapping (Step 8.1)
`VIBE_TO_YELP_CATEGORIES` maps each of the 8 aesthetic vibes to 3 Yelp category aliases (24 total categories). The aliases are from Yelp's category taxonomy, not human-readable titles. In Step 8.7, the aggregation node will extract vibes from the vault profile and pass the mapped categories to `YelpService.search_businesses()`. This enables vibe-appropriate discovery — e.g., a "quiet_luxury" partner sees wine bars, wineries, and spas rather than food trucks.

### 121. International Currency Detection (Step 8.1)
`COUNTRY_CURRENCY_MAP` provides ISO 4217 currency codes for 36 country codes. Currency is determined by the search location's country code (from the vault profile), not from Yelp's response. This is because Yelp's API doesn't return currency information — prices are displayed as $/$$/$$$/$$$$. The map includes all major Yelp-supported countries: US, CA, GB/UK, 11 eurozone, JP, AU, NZ, and 15+ others. Unknown codes default to "USD".

### 122. Bidirectional Price Conversion (Step 8.1)
Two static mappings handle price filtering and normalization: (1) `_convert_price_range_to_yelp()` converts a budget in cents to Yelp's 1-4 price filter using range overlap detection — if any part of the user's budget overlaps a price level's range, that level is included. Returns comma-separated string (e.g., "2,3"). (2) `YELP_PRICE_TO_CENTS` converts Yelp's $/$$/$$$/$$$ back to approximate midpoint cents for `CandidateRecommendation.price_cents`. The bidirectional approach ensures consistent pricing through the pipeline — filter at the API level, estimate at the normalization level.

### 123. TicketmasterService Four-Layer Architecture (Step 8.2)
`TicketmasterService` follows the same four-layer pattern as `YelpService`: (1) **config layer** — `is_ticketmaster_configured()` guard returns `[]` immediately if `TICKETMASTER_API_KEY` is empty, (2) **HTTP layer** — `_make_request()` with exponential backoff on 429 and retry on timeout, (3) **normalization layer** — `_normalize_event()` converts Ticketmaster event JSON to `CandidateRecommendation`-compatible dicts with `source="ticketmaster"` and `type="experience"`, (4) **search layer** — `search_events()` orchestrates param building, API call, onsale filtering, price filtering, and batch normalization. Key difference from Yelp: Ticketmaster authenticates via `apikey` query parameter (not `Authorization` header), and adds an onsale filtering step between API call and normalization.

### 124. Interest-to-Genre Mapping (Step 8.2)
`INTEREST_TO_TM_GENRE` maps 8 partner interest categories to Ticketmaster genre objects (`{"name": str, "genreId": str}`). "Concerts" and "Music" both map to the Music genre (`KnvZfZ7vAeA`) — this is intentional since the partner vault uses "Concerts" as the interest label but Ticketmaster calls it "Music". Additional mappings: Theater → Arts & Theatre, Sports → Sports, Comedy → Comedy, Dancing → Dance/Electronic, Movies → Film, Family → Family. The `genreId` strings are Ticketmaster's internal classification identifiers, used as the `genreId` query parameter in the Discovery API.

### 125. Onsale Status Filtering (Step 8.2)
`_is_onsale()` checks `event.dates.status.code` against `VALID_ONSALE_STATUSES` (currently `{"onsale"}`). The check is case-insensitive. Events with `offsale`, `cancelled`, `rescheduled`, or missing status are excluded *before* normalization, ensuring users only see events they can actually book. This filtering happens in `search_events()` after the API response and before price filtering, so offsale events don't consume budget-filter slots.

### 126. Dual-Source Currency Detection (Step 8.2)
Unlike Yelp (which never returns currency in its API response), Ticketmaster includes a `currency` field in `priceRanges`. The normalization uses a dual-source strategy: (1) start with country-based fallback from `COUNTRY_CURRENCY_MAP` (imported from `yelp.py` — no duplication), (2) override with `priceRanges[0].currency` if present. This means a US-based search that returns a GBP-priced touring show correctly reports GBP. The shared `COUNTRY_CURRENCY_MAP` ensures consistent currency detection across all external API integrations.

### 127. Midpoint Price Strategy (Step 8.2)
Ticketmaster returns explicit dollar amounts (`min` and `max`) unlike Yelp's categorical $-$$$$ system. The normalization computes `price_cents = int(((min + max) / 2) * 100)`, using the midpoint as the representative price for budget filtering and display. When only `min` or `max` is available, that value is used directly. Missing `priceRanges` results in `None` `price_cents`, which passes through all budget filters (events without pricing are always included). Raw `min`/`max` values are preserved in `metadata` for downstream nodes that may need the full range.

---

## Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   SwiftUI   │────▶│  Services   │────▶│  Supabase   │
│    Views    │◀────│   Layer     │◀────│  Backend    │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │
       ▼                   ▼
┌─────────────┐     ┌─────────────┐
│  SwiftData  │     │   FastAPI   │
│   (Local)   │     │   Backend   │
└─────────────┘     └─────────────┘
```

1. **Views** call **Services** for data operations
2. **Services** communicate with **Supabase** (auth, database) and **FastAPI** (recommendations)
3. **SwiftData** provides offline-capable local storage
4. **FastAPI** orchestrates LangGraph pipeline and external APIs

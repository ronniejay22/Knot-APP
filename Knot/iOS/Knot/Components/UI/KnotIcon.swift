//
//  KnotIcon.swift
//  Knot
//
//  The app's only icon system: MUI (`@mui/icons-material`) glyphs, bundled as
//  template vector assets under `Assets.xcassets/MUI/`.
//

import SwiftUI
import UIKit

/// Every icon the app draws. Knot uses MUI icons **only** — no Lucide, no SF
/// Symbols (`IconPolicyTests` fails the suite if either comes back). The one
/// allowlisted exception is Apple's own logo on the "Continue with Apple"
/// button, which App Review expects to be Apple-provided artwork.
///
/// **This enum is the source of truth for the asset catalog.** Each case's
/// raw value is the exact MUI component name (`HomeOutlined`, `Bookmark`), and
/// `iOS/scripts/generate-mui-icons.mjs` reads those raw values to produce
/// `Assets.xcassets/MUI/<Name>.imageset`. To add an icon: add a case, run the
/// generator, commit the new imageset. `KnotIconTests` fails if a case has no
/// bundled asset.
///
/// **Style rule:** Outlined by default; the Filled variant only for an "on"
/// state — the selected tab, a saved bookmark, a checked row or radio (or a met
/// selection count), a chosen star, the "primary set" marker, a
/// Delivered/Failed status badge.
///
/// **MUI naming trap:** `FavoriteOutlined`, `BookmarkOutlined` and
/// `StarOutlined` are *solid* glyphs (their paths are identical to `Favorite`,
/// `Bookmark`, `Star`). The outline versions are `FavoriteBorder`,
/// `BookmarkBorder` and `StarBorder` — use those.
enum KnotIcon: String, CaseIterable, Sendable {

    // MARK: Navigation & chrome
    case homeOutlined = "HomeOutlined"
    case home = "Home"
    case accountCircleOutlined = "AccountCircleOutlined"
    case accountCircle = "AccountCircle"
    case arrowBackOutlined = "ArrowBackOutlined"
    case arrowBackIosNewOutlined = "ArrowBackIosNewOutlined"
    case arrowForwardOutlined = "ArrowForwardOutlined"
    case chevronLeftOutlined = "ChevronLeftOutlined"
    case chevronRightOutlined = "ChevronRightOutlined"
    case expandMoreOutlined = "ExpandMoreOutlined"
    case closeOutlined = "CloseOutlined"
    case moreVertOutlined = "MoreVertOutlined"
    case searchOutlined = "SearchOutlined"
    case openInNewOutlined = "OpenInNewOutlined"

    // MARK: Actions
    case addOutlined = "AddOutlined"
    case removeOutlined = "RemoveOutlined"
    case addCircleOutlineOutlined = "AddCircleOutlineOutlined"
    case editOutlined = "EditOutlined"
    case deleteOutlined = "DeleteOutlined"
    case refreshOutlined = "RefreshOutlined"
    case restartAltOutlined = "RestartAltOutlined"
    case autorenewOutlined = "AutorenewOutlined"
    case contentCopyOutlined = "ContentCopyOutlined"
    case logoutOutlined = "LogoutOutlined"
    case shuffleOutlined = "ShuffleOutlined"

    // MARK: State (Filled = "on")
    case bookmarkBorder = "BookmarkBorder"
    case bookmark = "Bookmark"
    case starBorder = "StarBorder"
    case star = "Star"
    case radioButtonUncheckedOutlined = "RadioButtonUncheckedOutlined"
    case checkCircleOutlined = "CheckCircleOutlined"
    case checkCircle = "CheckCircle"
    case checkOutlined = "CheckOutlined"
    case cancelOutlined = "CancelOutlined"
    case cancel = "Cancel"
    case looksOne = "LooksOne"

    // MARK: Status & feedback
    case errorOutlineOutlined = "ErrorOutlineOutlined"
    case warningAmberOutlined = "WarningAmberOutlined"
    case gppMaybeOutlined = "GppMaybeOutlined"
    case verifiedUserOutlined = "VerifiedUserOutlined"
    case shieldOutlined = "ShieldOutlined"
    case wifiOffOutlined = "WifiOffOutlined"
    case notificationsActiveOutlined = "NotificationsActiveOutlined"
    case thumbDownOutlined = "ThumbDownOutlined"
    case arrowCircleUpOutlined = "ArrowCircleUpOutlined"
    case arrowCircleDownOutlined = "ArrowCircleDownOutlined"

    // MARK: Content & objects
    case autoAwesomeOutlined = "AutoAwesomeOutlined"
    case favoriteBorder = "FavoriteBorder"
    case lightbulbOutlined = "LightbulbOutlined"
    case mailOutlined = "MailOutlined"
    case markEmailReadOutlined = "MarkEmailReadOutlined"
    case placeOutlined = "PlaceOutlined"
    case eventOutlined = "EventOutlined"
    case editCalendarOutlined = "EditCalendarOutlined"
    case calendarTodayOutlined = "CalendarTodayOutlined"
    case scheduleOutlined = "ScheduleOutlined"
    case historyOutlined = "HistoryOutlined"
    case cardGiftcardOutlined = "CardGiftcardOutlined"
    case storefrontOutlined = "StorefrontOutlined"
    case shoppingBagOutlined = "ShoppingBagOutlined"
    case attachMoneyOutlined = "AttachMoneyOutlined"
    case paidOutlined = "PaidOutlined"
    case creditCardOutlined = "CreditCardOutlined"
    case accountBalanceWalletOutlined = "AccountBalanceWalletOutlined"
    case chatBubbleOutlineOutlined = "ChatBubbleOutlineOutlined"
    case personOutlineOutlined = "PersonOutlineOutlined"
    case menuBookOutlined = "MenuBookOutlined"
    case descriptionOutlined = "DescriptionOutlined"
    case assignmentOutlined = "AssignmentOutlined"
    case musicNoteOutlined = "MusicNoteOutlined"
    case restaurantOutlined = "RestaurantOutlined"
    case volunteerActivismOutlined = "VolunteerActivismOutlined"
    case panToolOutlined = "PanToolOutlined"
    case cakeOutlined = "CakeOutlined"

    // MARK: Vibes
    case diamondOutlined = "DiamondOutlined"
    case locationCityOutlined = "LocationCityOutlined"
    case parkOutlined = "ParkOutlined"
    case cropSquareOutlined = "CropSquareOutlined"
    case wbSunnyOutlined = "WbSunnyOutlined"
    case exploreOutlined = "ExploreOutlined"

    // MARK: Holidays
    case celebrationOutlined = "CelebrationOutlined"
    case familyRestroomOutlined = "FamilyRestroomOutlined"
    case nightsStayOutlined = "NightsStayOutlined"
    case eggOutlined = "EggOutlined"
    case localFireDepartmentOutlined = "LocalFireDepartmentOutlined"
    case bedtimeOutlined = "BedtimeOutlined"

    // MARK: Interests
    case flightOutlined = "FlightOutlined"
    case outdoorGrillOutlined = "OutdoorGrillOutlined"
    case movieOutlined = "MovieOutlined"
    case sportsSoccerOutlined = "SportsSoccerOutlined"
    case sportsEsportsOutlined = "SportsEsportsOutlined"
    case brushOutlined = "BrushOutlined"
    case photoCameraOutlined = "PhotoCameraOutlined"
    case fitnessCenterOutlined = "FitnessCenterOutlined"
    case checkroomOutlined = "CheckroomOutlined"
    case laptopMacOutlined = "LaptopMacOutlined"
    case natureOutlined = "NatureOutlined"
    case localCafeOutlined = "LocalCafeOutlined"
    case wineBarOutlined = "WineBarOutlined"
    case nightlifeOutlined = "NightlifeOutlined"
    case theaterComedyOutlined = "TheaterComedyOutlined"
    case libraryMusicOutlined = "LibraryMusicOutlined"
    case museumOutlined = "MuseumOutlined"
    case selfImprovementOutlined = "SelfImprovementOutlined"
    case hikingOutlined = "HikingOutlined"
    case beachAccessOutlined = "BeachAccessOutlined"
    case petsOutlined = "PetsOutlined"
    case directionsCarOutlined = "DirectionsCarOutlined"
    case handymanOutlined = "HandymanOutlined"
    case yardOutlined = "YardOutlined"
    case spaOutlined = "SpaOutlined"
    case podcastsOutlined = "PodcastsOutlined"
    case bakeryDiningOutlined = "BakeryDiningOutlined"
    case cabinOutlined = "CabinOutlined"
    case directionsBikeOutlined = "DirectionsBikeOutlined"
    case directionsRunOutlined = "DirectionsRunOutlined"
    case poolOutlined = "PoolOutlined"
    case downhillSkiingOutlined = "DownhillSkiingOutlined"
    case surfingOutlined = "SurfingOutlined"
    case paletteOutlined = "PaletteOutlined"
    case casinoOutlined = "CasinoOutlined"
    case micOutlined = "MicOutlined"

    /// The namespaced asset-catalog name, e.g. `"MUI/HomeOutlined"`.
    var assetName: String { "MUI/\(rawValue)" }

    /// The icon as a SwiftUI image. **Decorative** on purpose: a named asset
    /// image otherwise hands VoiceOver its asset name ("HomeOutlined"), so any
    /// spoken meaning must come from the control's own `accessibilityLabel`.
    var image: Image { Image(decorative: assetName) }

    /// The icon as a `UIImage`, for UIKit surfaces such as the navigation
    /// bar's back indicator. Empty rather than a crash if the asset is missing
    /// — `KnotIconTests` is what guarantees it never is.
    var uiImage: UIImage { UIImage(named: assetName) ?? UIImage() }
}

/// Renders a `KnotIcon` as a template image at a square size, tinted by the
/// surrounding `foregroundStyle`. The one way icons are drawn in the app.
///
/// MUI glyphs sit in a 24-unit box with ~2 units of inset, so `size` is the
/// frame, not the ink: a 20pt `KnotIconView` draws a ~17pt glyph.
struct KnotIconView: View {
    let icon: KnotIcon
    let size: CGFloat

    init(_ icon: KnotIcon, size: CGFloat) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        icon.image
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

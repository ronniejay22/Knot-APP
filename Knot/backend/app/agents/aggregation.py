"""
External API Aggregation Node — LangGraph node for gathering recommendation candidates.

Queries external APIs to find gift and experience candidates matching
the partner's interests, vibes, location, and budget.

Currently uses stub data catalogs. In Phase 8, these will be replaced by:
- AmazonService (gifts via Amazon Associates API)
- ShopifyService (gifts via Shopify Storefront API)
- YelpService (experiences/dates via Yelp Fusion API)
- TicketmasterService (events via Ticketmaster API)

Step 5.3: Create External API Aggregation Node
"""

import asyncio
import logging
import uuid
from typing import Any

from app.agents.state import (
    CandidateRecommendation,
    LocationData,
    RecommendationState,
)

logger = logging.getLogger(__name__)

# --- Constants ---
TARGET_CANDIDATE_COUNT = 20  # aim for 15-20 candidates
MAX_GIFTS_PER_INTEREST = 3  # cap per interest to avoid domination
MAX_EXPERIENCES_PER_VIBE = 3  # cap per vibe


# ======================================================================
# Stub data catalogs (replaced by real API services in Phase 8)
# ======================================================================

# Interest → gift product ideas
# Format: (title, description, price_cents, merchant_name, source)
_INTEREST_GIFTS: dict[str, list[tuple[str, str, int, str, str]]] = {
    "Travel": [
        ("Premium Leather Passport Holder", "Handcrafted genuine leather passport cover with card slots", 4500, "Amazon", "amazon"),
        ("World Scratch Map Poster", "Large scratch-off world map with US states detail", 2500, "Amazon", "amazon"),
        ("Carry-On Packing Cubes Set", "Set of 6 lightweight compression packing cubes", 3200, "TravelGear Co", "shopify"),
    ],
    "Cooking": [
        ("Japanese Chef Knife", "Professional 8-inch VG-10 steel chef knife", 8900, "Amazon", "amazon"),
        ("Artisan Spice Collection", "Curated set of 12 small-batch spices from around the world", 4200, "The Spice House", "shopify"),
        ("Handmade Ceramic Bowl Set", "Set of 4 hand-thrown stoneware ramen bowls", 6500, "Artisan Home", "shopify"),
    ],
    "Movies": [
        ("Classic Film Poster Collection", "Set of 3 vintage movie posters on premium paper", 3500, "Amazon", "amazon"),
        ("Home Theater Projector", "Portable HD mini projector for movie nights", 15900, "Amazon", "amazon"),
        ("Movie Lover Gift Box", "Gourmet popcorn, candy, and streaming gift card", 4800, "FilmBox", "shopify"),
    ],
    "Music": [
        ("Vinyl Record Player", "Bluetooth turntable with built-in speakers", 7900, "Amazon", "amazon"),
        ("Custom Song Portrait Print", "Personalized sound wave art of your song", 4500, "SoundWave Art", "shopify"),
        ("Premium Wireless Headphones", "Noise-cancelling over-ear headphones", 19900, "Amazon", "amazon"),
    ],
    "Reading": [
        ("Kindle Paperwhite", "Waterproof e-reader with adjustable warm light", 14900, "Amazon", "amazon"),
        ("Personalized Leather Bookmark Set", "Set of 3 embossed leather bookmarks", 2800, "BookishGifts", "shopify"),
        ("Book Subscription Box", "3-month curated book subscription with extras", 9900, "Book of the Month", "shopify"),
    ],
    "Sports": [
        ("Smart Fitness Watch", "GPS sports watch with heart rate monitoring", 19900, "Amazon", "amazon"),
        ("Premium Sports Duffel Bag", "Waterproof gym bag with shoe compartment", 5500, "Amazon", "amazon"),
        ("Sports Memorabilia Frame", "Custom shadow box for jerseys and memorabilia", 7500, "FrameIt", "shopify"),
    ],
    "Gaming": [
        ("Mechanical Gaming Keyboard", "RGB mechanical keyboard with Cherry MX switches", 12900, "Amazon", "amazon"),
        ("Gaming Headset", "7.1 surround sound wireless gaming headset", 8900, "Amazon", "amazon"),
        ("Retro Mini Game Console", "Classic console with 500 built-in retro games", 5900, "Amazon", "amazon"),
    ],
    "Art": [
        ("Professional Watercolor Set", "48-color artist watercolor palette with brushes", 6500, "Amazon", "amazon"),
        ("Custom Portrait Commission", "Hand-drawn digital portrait from your photo", 12000, "ArtistAlley", "shopify"),
        ("Art Print Subscription", "Monthly curated art print delivery service", 3500, "Gallery Wall Co", "shopify"),
    ],
    "Photography": [
        ("Camera Lens Filter Set", "Professional ND and polarizer filter kit", 5500, "Amazon", "amazon"),
        ("Premium Photo Book", "Hardcover photo book with 50 pages", 4500, "Artifact Uprising", "shopify"),
        ("Leather Camera Strap", "Handmade leather camera strap with padding", 4200, "Peak Design", "shopify"),
    ],
    "Fitness": [
        ("Resistance Band Set", "Professional-grade resistance bands with handles", 3500, "Amazon", "amazon"),
        ("Smart Water Bottle", "Temperature-tracking insulated water bottle", 4500, "HidrateSpark", "shopify"),
        ("Premium Yoga Mat", "Extra-thick eco-friendly yoga mat with carry strap", 6800, "Amazon", "amazon"),
    ],
    "Fashion": [
        ("Designer Sunglasses", "Classic aviator sunglasses with UV protection", 15900, "Amazon", "amazon"),
        ("Cashmere Scarf", "Luxury 100% cashmere scarf in neutral tones", 8900, "Nordstrom", "shopify"),
        ("Leather Watch Box", "Handcrafted watch organizer with 6 slots", 5500, "Amazon", "amazon"),
    ],
    "Technology": [
        ("Smart Home Speaker", "Voice-controlled smart speaker with premium audio", 9900, "Amazon", "amazon"),
        ("Portable Power Bank", "20000mAh fast-charging portable charger", 3500, "Amazon", "amazon"),
        ("Wireless Charging Pad", "Elegant bamboo wireless charger for desk", 2900, "Amazon", "amazon"),
    ],
    "Nature": [
        ("National Park Poster Set", "Set of 6 vintage-style national park prints", 4500, "Amazon", "amazon"),
        ("Bird Watching Binoculars", "Compact waterproof binoculars for birding", 8900, "Amazon", "amazon"),
        ("Indoor Herb Garden Kit", "Self-watering smart garden with LED grow lights", 9900, "AeroGarden", "shopify"),
    ],
    "Food": [
        ("Gourmet Cheese Board Set", "Bamboo cheese board with knife set and accessories", 4900, "Amazon", "amazon"),
        ("International Snack Box", "Monthly subscription of snacks from 5 countries", 3500, "Universal Yums", "shopify"),
        ("Truffle Oil and Salt Gift Set", "Premium Italian truffle oil and finishing salt", 5500, "Gourmet Gifts", "shopify"),
    ],
    "Coffee": [
        ("Pour Over Coffee Set", "Chemex pour-over brewer with gooseneck kettle", 7500, "Amazon", "amazon"),
        ("Single-Origin Coffee Subscription", "3-month specialty roast subscription", 5400, "Blue Bottle", "shopify"),
        ("Espresso Cups Set", "Set of 4 handmade espresso cups with saucers", 3800, "NotNeutral", "shopify"),
    ],
    "Wine": [
        ("Wine Aerator and Decanter Set", "Crystal wine decanter with aerating pour spout", 5500, "Amazon", "amazon"),
        ("Wine Club Subscription", "2-bottle monthly wine subscription service", 8900, "Winc", "shopify"),
        ("Personalized Wine Label Kit", "Custom wine label maker for home vintners", 2500, "PersonalWine", "shopify"),
    ],
    "Dancing": [
        ("Professional Dance Shoes", "Ballroom dance shoes with suede sole", 7500, "Amazon", "amazon"),
        ("Dance Class Gift Card", "5 dance class sessions at a local studio", 10000, "DanceStudio", "shopify"),
    ],
    "Theater": [
        ("Broadway Show Gift Card", "Gift card for theater show tickets", 15000, "Telecharge", "shopify"),
        ("Theater Binoculars", "Compact opera glasses with LED light", 3500, "Amazon", "amazon"),
    ],
    "Concerts": [
        ("Concert Poster Frame", "Premium poster frame for concert memorabilia", 4500, "Amazon", "amazon"),
        ("High-Fidelity Concert Earplugs", "Earplugs that preserve sound quality at shows", 2500, "Eargasm", "shopify"),
    ],
    "Museums": [
        ("Museum Membership Gift", "Annual membership to local art museum", 12000, "Museum Store", "shopify"),
        ("Art History Coffee Table Book", "Comprehensive illustrated art history compendium", 5500, "Amazon", "amazon"),
    ],
    "Shopping": [
        ("Multi-Store Gift Card Bundle", "Gift cards for top retail stores", 10000, "Amazon", "amazon"),
        ("Personal Shopper Session", "2-hour personal styling consultation", 15000, "StyleBox", "shopify"),
    ],
    "Yoga": [
        ("Cork Yoga Block Set", "Eco-friendly cork yoga blocks with strap", 3200, "Amazon", "amazon"),
        ("Yoga Retreat Gift Card", "Weekend yoga retreat voucher", 25000, "YogaEscape", "shopify"),
    ],
    "Hiking": [
        ("Trail Running Shoes", "Waterproof trail shoes with grip sole", 12900, "Amazon", "amazon"),
        ("Hiking Daypack", "Lightweight 25L hiking backpack with hydration sleeve", 7900, "Amazon", "amazon"),
        ("National Parks Annual Pass", "Annual pass to all US national parks", 8000, "REI", "shopify"),
    ],
    "Beach": [
        ("Sand-Free Beach Towel Set", "Oversized Turkish beach towels that repel sand", 4500, "Amazon", "amazon"),
        ("Waterproof Bluetooth Speaker", "Floating waterproof speaker for beach days", 5900, "JBL", "shopify"),
    ],
    "Pets": [
        ("Custom Pet Portrait", "Hand-painted portrait of their pet from a photo", 8900, "PetPortraits", "shopify"),
        ("Smart Pet Camera", "Two-way audio treat-dispensing pet camera", 6500, "Amazon", "amazon"),
    ],
    "Cars": [
        ("Professional Detailing Kit", "Car detailing kit with ceramic coating spray", 7500, "Amazon", "amazon"),
        ("Exotic Car Driving Experience", "Drive a supercar on a professional track", 19900, "DreamDrives", "shopify"),
    ],
    "DIY": [
        ("Complete Home Tool Set", "112-piece home repair tool kit in carry case", 6900, "Amazon", "amazon"),
        ("Woodworking Class Voucher", "Beginner woodworking workshop for two", 12500, "MakerSpace", "shopify"),
    ],
    "Gardening": [
        ("Ergonomic Garden Tool Set", "Stainless steel garden tools with comfort grips", 4500, "Amazon", "amazon"),
        ("Raised Garden Bed Kit", "Cedar raised bed with soil and seed starter pack", 8900, "Gardeners Supply", "shopify"),
    ],
    "Meditation": [
        ("Meditation Cushion", "Buckwheat fill zafu meditation cushion", 4500, "Amazon", "amazon"),
        ("Tibetan Singing Bowl Set", "Handmade singing bowl with mallet and cushion", 5500, "MindfulHome", "shopify"),
    ],
    "Podcasts": [
        ("Podcast Microphone Kit", "USB condenser mic with pop filter and boom arm", 6900, "Amazon", "amazon"),
        ("True Wireless Earbuds", "Premium wireless earbuds with 8-hour battery", 7900, "Amazon", "amazon"),
    ],
    "Baking": [
        ("Stand Mixer", "5-quart tilt-head stand mixer with attachments", 24900, "Amazon", "amazon"),
        ("Professional Baking Tool Set", "Silicone mats, piping bags, and pastry tools", 3500, "Amazon", "amazon"),
        ("Sourdough Starter Kit", "Complete sourdough bread making kit with guide", 3200, "BreadBox", "shopify"),
    ],
    "Camping": [
        ("Camping Hammock", "Double camping hammock with tree straps", 3500, "Amazon", "amazon"),
        ("Portable Camp Stove", "Compact backpacking stove with fuel canister", 4500, "Amazon", "amazon"),
    ],
    "Cycling": [
        ("Performance Cycling Jersey", "Moisture-wicking cycling jersey with pockets", 6500, "Amazon", "amazon"),
        ("Portable Bike Repair Kit", "Multi-tool bike repair kit with tire patches", 2500, "Amazon", "amazon"),
    ],
    "Running": [
        ("GPS Running Watch", "Running watch with pace alerts and route tracking", 14900, "Amazon", "amazon"),
        ("Foam Roller Recovery Set", "High-density foam roller with massage ball", 3200, "Amazon", "amazon"),
    ],
    "Swimming": [
        ("Competition Swim Goggles", "Anti-fog UV protection swim goggles", 2500, "Amazon", "amazon"),
        ("Waterproof MP3 Player", "Bone conduction waterproof swimming headphones", 7900, "Amazon", "amazon"),
    ],
    "Skiing": [
        ("Heated Ski Gloves", "Rechargeable battery-heated ski gloves", 8900, "Amazon", "amazon"),
        ("Premium Ski Goggles", "Anti-fog UV protection ski goggles with extra lens", 5500, "Amazon", "amazon"),
    ],
    "Surfing": [
        ("Surf Wax Collection", "Premium surf wax set for all water temperatures", 2200, "SurfShop", "shopify"),
        ("Solar Dive Watch", "Solar-powered dive watch rated to 200 meters", 15900, "Amazon", "amazon"),
    ],
    "Painting": [
        ("Professional Oil Paint Set", "24-color oil paint set with brushes and palette", 5500, "Amazon", "amazon"),
        ("Adjustable Tabletop Easel", "Beech wood tabletop easel with storage drawer", 3500, "Amazon", "amazon"),
    ],
    "Board Games": [
        ("Strategy Board Game Collection", "Set of 3 award-winning strategy games", 7900, "Amazon", "amazon"),
        ("Custom Game Night Kit", "Personalized game night box with snacks and games", 4500, "GameNight Co", "shopify"),
    ],
    "Karaoke": [
        ("Wireless Karaoke Microphone", "Bluetooth karaoke mic with built-in speaker", 3500, "Amazon", "amazon"),
        ("Portable Karaoke Machine", "Karaoke system with disco lights and effects", 8900, "Amazon", "amazon"),
    ],
}


# Vibe → experience/date ideas
# Format: (title, description, price_cents, merchant_name, source, type)
_VIBE_EXPERIENCES: dict[str, list[tuple[str, str, int, str, str, str]]] = {
    "quiet_luxury": [
        ("Private Wine Tasting Experience", "Exclusive tasting at a boutique winery with sommelier", 12000, "Napa Valley Vintners", "yelp", "date"),
        ("Spa Day for Two", "Couples massage and full spa treatment package", 18000, "The Ritz Spa", "yelp", "experience"),
        ("Fine Dining Omakase", "12-course chef's tasting menu at acclaimed restaurant", 25000, "Sushi Nakazawa", "yelp", "date"),
    ],
    "street_urban": [
        ("Street Art Walking Tour", "Guided tour of the city's best murals and graffiti art", 4500, "Urban Adventures", "yelp", "experience"),
        ("Underground Comedy Show", "Stand-up comedy night at an intimate underground venue", 3500, "The Comedy Cellar", "ticketmaster", "experience"),
        ("Food Truck Festival Tickets", "Weekend pass to the annual food truck festival", 5000, "City Events", "ticketmaster", "experience"),
    ],
    "outdoorsy": [
        ("Sunset Kayak Tour", "Guided sunset kayaking with wildlife spotting", 8500, "Paddle Co", "yelp", "experience"),
        ("Hot Air Balloon Ride", "Sunrise hot air balloon flight for two with champagne", 35000, "Sky High Balloons", "yelp", "experience"),
        ("Rock Climbing Class", "Intro to outdoor rock climbing with all gear provided", 9500, "Summit Adventures", "yelp", "experience"),
    ],
    "vintage": [
        ("Antique Market Tour", "Curated tour of the city's hidden antique shops", 5000, "Vintage Finds", "yelp", "date"),
        ("Classic Film Screening", "Vintage cinema screening of a restored classic film", 3000, "The Grand Theater", "ticketmaster", "experience"),
        ("Prohibition-Era Cocktail Class", "Learn to make classic cocktails at a speakeasy", 7500, "The Speakeasy", "yelp", "date"),
    ],
    "minimalist": [
        ("Japanese Tea Ceremony", "Authentic matcha tea ceremony experience", 6000, "Tea Garden", "yelp", "experience"),
        ("Meditation Retreat Day", "Full-day guided meditation and mindfulness retreat", 12000, "Zen Center", "yelp", "experience"),
        ("Architecture Walking Tour", "Modernist architecture tour of the city's landmarks", 4000, "Design Tours", "yelp", "experience"),
    ],
    "bohemian": [
        ("Pottery Wheel Workshop", "Hands-on pottery making class for two people", 8500, "Clay Studio", "yelp", "date"),
        ("Indie Music Festival Pass", "Weekend pass to an indie music festival", 15000, "Festival Live", "ticketmaster", "experience"),
        ("Tie-Dye Workshop", "Create custom tie-dye apparel together", 5500, "Art Collective", "yelp", "experience"),
    ],
    "romantic": [
        ("Couples Sunset Cruise", "Private sunset sailing cruise with champagne toast", 22000, "Harbor Cruises", "yelp", "date"),
        ("Candlelit Cooking Class", "Italian cooking class with wine pairing for two", 14000, "Chef's Table", "yelp", "date"),
        ("Stargazing Experience", "Private telescope viewing with astronomer guide", 9500, "Dark Sky Tours", "yelp", "date"),
    ],
    "adventurous": [
        ("Skydiving Tandem Jump", "First-time tandem skydiving experience with instructor", 25000, "SkyCo Adventures", "yelp", "experience"),
        ("White Water Rafting Trip", "Half-day guided rafting on class III-IV rapids", 9500, "River Rush", "yelp", "experience"),
        ("Escape Room Challenge", "Premium themed escape room experience for two", 7000, "Puzzle Palace", "yelp", "experience"),
    ],
}


# ======================================================================
# Candidate construction helpers
# ======================================================================

def _generate_candidate_id() -> str:
    """Generate a unique ID for a candidate recommendation."""
    return str(uuid.uuid4())


def _build_gift_candidate(
    interest: str,
    entry: tuple[str, str, int, str, str],
) -> CandidateRecommendation:
    """Build a CandidateRecommendation from a gift catalog entry."""
    title, description, price_cents, merchant_name, source = entry
    slug = title.lower().replace(" ", "-").replace("'", "")

    return CandidateRecommendation(
        id=_generate_candidate_id(),
        source=source,
        type="gift",
        title=title,
        description=description,
        price_cents=price_cents,
        external_url=f"https://{source}.com/products/{slug}",
        image_url=f"https://images.example.com/{slug}.jpg",
        merchant_name=merchant_name,
        location=None,
        metadata={"matched_interest": interest, "catalog": "stub"},
    )


def _build_experience_candidate(
    vibe: str,
    entry: tuple[str, str, int, str, str, str],
    location: LocationData | None,
) -> CandidateRecommendation:
    """Build a CandidateRecommendation from an experience/date catalog entry."""
    title, description, price_cents, merchant_name, source, rec_type = entry
    slug = title.lower().replace(" ", "-").replace("'", "")

    return CandidateRecommendation(
        id=_generate_candidate_id(),
        source=source,
        type=rec_type,
        title=title,
        description=description,
        price_cents=price_cents,
        external_url=f"https://{source}.com/events/{slug}",
        image_url=f"https://images.example.com/{slug}.jpg",
        merchant_name=merchant_name,
        location=location,
        metadata={"matched_vibe": vibe, "catalog": "stub"},
    )


# ======================================================================
# Stub API fetch functions (replaced by real API services in Phase 8)
# ======================================================================

async def _fetch_gift_candidates(
    interests: list[str],
    budget_min: int,
    budget_max: int,
) -> list[CandidateRecommendation]:
    """
    Fetch gift candidates matching the given interests within budget.

    In Phase 8, this will call AmazonService and ShopifyService in parallel.
    """
    candidates = []

    for interest in interests:
        entries = _INTEREST_GIFTS.get(interest, [])
        for entry in entries[:MAX_GIFTS_PER_INTEREST]:
            candidate = _build_gift_candidate(interest, entry)
            # Budget filter: keep if price is within range or unknown
            if candidate.price_cents is None or (
                budget_min <= candidate.price_cents <= budget_max
            ):
                candidates.append(candidate)

    return candidates


async def _fetch_experience_candidates(
    vibes: list[str],
    budget_min: int,
    budget_max: int,
    location: LocationData | None,
) -> list[CandidateRecommendation]:
    """
    Fetch experience/date candidates matching the given vibes within budget.

    In Phase 8, this will call YelpService and TicketmasterService in parallel.
    """
    candidates = []

    for vibe in vibes:
        entries = _VIBE_EXPERIENCES.get(vibe, [])
        for entry in entries[:MAX_EXPERIENCES_PER_VIBE]:
            candidate = _build_experience_candidate(vibe, entry, location)
            # Budget filter: keep if price is within range or unknown
            if candidate.price_cents is None or (
                budget_min <= candidate.price_cents <= budget_max
            ):
                candidates.append(candidate)

    return candidates


# ======================================================================
# LangGraph node
# ======================================================================

async def aggregate_external_data(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    LangGraph node: Aggregate candidate recommendations from external APIs.

    1. Reads interests and vibes from the vault data
    2. Calls gift APIs (Amazon, Shopify) and experience APIs (Yelp, Ticketmaster)
       in parallel
    3. Filters candidates by budget range
    4. Returns 15-20 raw candidate recommendations

    If no candidates are found after filtering, sets an error message.
    If one API source fails, returns partial results from the other.

    Args:
        state: The current RecommendationState with vault_data and budget_range.

    Returns:
        A dict with "candidate_recommendations" key containing
        list[CandidateRecommendation], and optionally "error" if no
        candidates were found.
    """
    vault = state.vault_data
    budget = state.budget_range

    # Build location data for experience candidates
    location = None
    if vault.location_city or vault.location_state or vault.location_country:
        location = LocationData(
            city=vault.location_city,
            state=vault.location_state,
            country=vault.location_country,
        )

    logger.info(
        "Aggregating candidates for vault %s: interests=%s, vibes=%s, budget=%d-%d %s",
        vault.vault_id, vault.interests, vault.vibes,
        budget.min_amount, budget.max_amount, budget.currency,
    )

    # Fetch gifts and experiences in parallel
    results = await asyncio.gather(
        _fetch_gift_candidates(
            vault.interests, budget.min_amount, budget.max_amount,
        ),
        _fetch_experience_candidates(
            vault.vibes, budget.min_amount, budget.max_amount, location,
        ),
        return_exceptions=True,
    )

    # Handle partial failures
    gift_candidates: list[CandidateRecommendation] = []
    experience_candidates: list[CandidateRecommendation] = []

    if isinstance(results[0], Exception):
        logger.error("Gift candidate fetch failed: %s", results[0])
    else:
        gift_candidates = results[0]

    if isinstance(results[1], Exception):
        logger.error("Experience candidate fetch failed: %s", results[1])
    else:
        experience_candidates = results[1]

    # Combine candidates with interleaving to avoid bias when capping
    all_candidates: list[CandidateRecommendation] = []
    gi, ei = 0, 0
    while len(all_candidates) < TARGET_CANDIDATE_COUNT and (
        gi < len(gift_candidates) or ei < len(experience_candidates)
    ):
        if gi < len(gift_candidates):
            all_candidates.append(gift_candidates[gi])
            gi += 1
        if len(all_candidates) < TARGET_CANDIDATE_COUNT and ei < len(experience_candidates):
            all_candidates.append(experience_candidates[ei])
            ei += 1

    logger.info(
        "Aggregated %d candidates (%d gifts, %d experiences) for vault %s",
        len(all_candidates), len(gift_candidates), len(experience_candidates),
        vault.vault_id,
    )

    # Build result
    result: dict[str, Any] = {"candidate_recommendations": all_candidates}

    if not all_candidates:
        result["error"] = "No candidates found matching budget and criteria"
        logger.warning("No candidates found for vault %s", vault.vault_id)

    return result

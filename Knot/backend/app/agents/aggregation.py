"""
External API Aggregation Node — LangGraph node for gathering recommendation candidates.

Three-tier fallback for candidate aggregation:
1. ClaudeSearchService (Brave Search + Claude extraction) — primary
2. AggregatorService (Yelp, Ticketmaster, etc.) — secondary
3. Stub catalogs — final fallback

Step 5.3: Create External API Aggregation Node
Step 8.8: Wire real services into the aggregation pipeline
Step 13.1: Replace External APIs with Claude Search Agent
"""

import asyncio
import logging
import uuid
from urllib.parse import quote_plus
from typing import Any

from app.agents.state import (
    CandidateRecommendation,
    LocationData,
    RecommendationState,
)
from app.services.integrations.aggregator import AggregatorService, AggregationError
from app.services.integrations.claude_search_service import ClaudeSearchService

logger = logging.getLogger(__name__)

# --- Constants ---
TARGET_CANDIDATE_COUNT = 20


# ======================================================================
# Dict → CandidateRecommendation conversion
# ======================================================================

def _dict_to_candidate(raw: dict[str, Any]) -> CandidateRecommendation:
    """
    Convert a dict from AggregatorService into a CandidateRecommendation.

    The real services return dicts with keys matching CandidateRecommendation
    fields, but the `location` field is a plain dict that needs conversion
    to LocationData.
    """
    # Convert location dict to LocationData if present
    location = None
    raw_location = raw.get("location")
    if isinstance(raw_location, dict):
        location = LocationData(
            city=raw_location.get("city"),
            state=raw_location.get("state"),
            country=raw_location.get("country"),
            address=raw_location.get("address"),
        )

    return CandidateRecommendation(
        id=raw.get("id", str(uuid.uuid4())),
        source=raw["source"],
        type=raw["type"],
        title=raw["title"],
        description=raw.get("description"),
        price_cents=raw.get("price_cents"),
        currency=raw.get("currency", "USD"),
        external_url=raw["external_url"],
        image_url=raw.get("image_url"),
        merchant_name=raw.get("merchant_name"),
        location=location,
        metadata=raw.get("metadata", {}),
        price_confidence=raw.get("price_confidence", "unknown"),
    )


# ======================================================================
# Stub data fallback (used only when all real services fail)
# ======================================================================

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
    ],
    "Music": [
        ("Vinyl Record Player", "Bluetooth turntable with built-in speakers", 7900, "Amazon", "amazon"),
        ("Premium Wireless Headphones", "Noise-cancelling over-ear headphones", 19900, "Amazon", "amazon"),
    ],
    "Reading": [
        ("Kindle Paperwhite", "Waterproof e-reader with adjustable warm light", 14900, "Amazon", "amazon"),
        ("Book Subscription Box", "3-month curated book subscription with extras", 9900, "Book of the Month", "shopify"),
    ],
    "Sports": [
        ("Smart Fitness Watch", "GPS sports watch with heart rate monitoring", 19900, "Amazon", "amazon"),
        ("Premium Sports Duffel Bag", "Waterproof gym bag with shoe compartment", 5500, "Amazon", "amazon"),
    ],
    "Gaming": [
        ("Mechanical Gaming Keyboard", "RGB mechanical keyboard with Cherry MX switches", 12900, "Amazon", "amazon"),
        ("Retro Mini Game Console", "Classic console with 500 built-in retro games", 5900, "Amazon", "amazon"),
    ],
    "Art": [
        ("Professional Watercolor Set", "48-color artist watercolor palette with brushes", 6500, "Amazon", "amazon"),
        ("Custom Portrait Commission", "Hand-drawn digital portrait from your photo", 12000, "ArtistAlley", "shopify"),
    ],
    "Photography": [
        ("Camera Lens Filter Set", "Professional ND and polarizer filter kit", 5500, "Amazon", "amazon"),
        ("Premium Photo Book", "Hardcover photo book with 50 pages", 4500, "Artifact Uprising", "shopify"),
    ],
    "Fitness": [
        ("Resistance Band Set", "Professional-grade resistance bands with handles", 3500, "Amazon", "amazon"),
        ("Premium Yoga Mat", "Extra-thick eco-friendly yoga mat with carry strap", 6800, "Amazon", "amazon"),
    ],
    "Fashion": [
        ("Designer Sunglasses", "Classic aviator sunglasses with UV protection", 15900, "Amazon", "amazon"),
        ("Cashmere Scarf", "Luxury 100% cashmere scarf in neutral tones", 8900, "Nordstrom", "shopify"),
    ],
    "Technology": [
        ("Smart Home Speaker", "Voice-controlled smart speaker with premium audio", 9900, "Amazon", "amazon"),
        ("Portable Power Bank", "20000mAh fast-charging portable charger", 3500, "Amazon", "amazon"),
    ],
    "Nature": [
        ("National Park Poster Set", "Set of 6 vintage-style national park prints", 4500, "Amazon", "amazon"),
        ("Indoor Herb Garden Kit", "Self-watering smart garden with LED grow lights", 9900, "AeroGarden", "shopify"),
    ],
    "Food": [
        ("Gourmet Cheese Board Set", "Bamboo cheese board with knife set and accessories", 4900, "Amazon", "amazon"),
        ("International Snack Box", "Monthly subscription of snacks from 5 countries", 3500, "Universal Yums", "shopify"),
    ],
    "Coffee": [
        ("Pour Over Coffee Set", "Chemex pour-over brewer with gooseneck kettle", 7500, "Amazon", "amazon"),
        ("Single-Origin Coffee Subscription", "3-month specialty roast subscription", 5400, "Blue Bottle", "shopify"),
    ],
    "Wine": [
        ("Wine Aerator and Decanter Set", "Crystal wine decanter with aerating pour spout", 5500, "Amazon", "amazon"),
        ("Wine Club Subscription", "2-bottle monthly wine subscription service", 8900, "Winc", "shopify"),
    ],
    "Dancing": [
        ("Professional Dance Shoes", "Ballroom dance shoes with suede sole", 7500, "Amazon", "amazon"),
    ],
    "Theater": [
        ("Broadway Show Gift Card", "Gift card for theater show tickets", 15000, "Telecharge", "shopify"),
    ],
    "Concerts": [
        ("Concert Poster Frame", "Premium poster frame for concert memorabilia", 4500, "Amazon", "amazon"),
    ],
    "Museums": [
        ("Museum Membership Gift", "Annual membership to local art museum", 12000, "Museum Store", "shopify"),
    ],
    "Shopping": [
        ("Multi-Store Gift Card Bundle", "Gift cards for top retail stores", 10000, "Amazon", "amazon"),
    ],
    "Yoga": [
        ("Cork Yoga Block Set", "Eco-friendly cork yoga blocks with strap", 3200, "Amazon", "amazon"),
    ],
    "Hiking": [
        ("Trail Running Shoes", "Waterproof trail shoes with grip sole", 12900, "Amazon", "amazon"),
        ("National Parks Annual Pass", "Annual pass to all US national parks", 8000, "REI", "shopify"),
    ],
    "Beach": [
        ("Sand-Free Beach Towel Set", "Oversized Turkish beach towels that repel sand", 4500, "Amazon", "amazon"),
    ],
    "Pets": [
        ("Custom Pet Portrait", "Hand-painted portrait of their pet from a photo", 8900, "PetPortraits", "shopify"),
    ],
    "Cars": [
        ("Professional Detailing Kit", "Car detailing kit with ceramic coating spray", 7500, "Amazon", "amazon"),
    ],
    "DIY": [
        ("Complete Home Tool Set", "112-piece home repair tool kit in carry case", 6900, "Amazon", "amazon"),
    ],
    "Gardening": [
        ("Ergonomic Garden Tool Set", "Stainless steel garden tools with comfort grips", 4500, "Amazon", "amazon"),
    ],
    "Meditation": [
        ("Meditation Cushion", "Buckwheat fill zafu meditation cushion", 4500, "Amazon", "amazon"),
    ],
    "Podcasts": [
        ("Podcast Microphone Kit", "USB condenser mic with pop filter and boom arm", 6900, "Amazon", "amazon"),
    ],
    "Baking": [
        ("Stand Mixer", "5-quart tilt-head stand mixer with attachments", 24900, "Amazon", "amazon"),
        ("Sourdough Starter Kit", "Complete sourdough bread making kit with guide", 3200, "BreadBox", "shopify"),
    ],
    "Camping": [
        ("Camping Hammock", "Double camping hammock with tree straps", 3500, "Amazon", "amazon"),
    ],
    "Cycling": [
        ("Performance Cycling Jersey", "Moisture-wicking cycling jersey with pockets", 6500, "Amazon", "amazon"),
    ],
    "Running": [
        ("GPS Running Watch", "Running watch with pace alerts and route tracking", 14900, "Amazon", "amazon"),
    ],
    "Swimming": [
        ("Competition Swim Goggles", "Anti-fog UV protection swim goggles", 2500, "Amazon", "amazon"),
    ],
    "Skiing": [
        ("Heated Ski Gloves", "Rechargeable battery-heated ski gloves", 8900, "Amazon", "amazon"),
    ],
    "Surfing": [
        ("Solar Dive Watch", "Solar-powered dive watch rated to 200 meters", 15900, "Amazon", "amazon"),
    ],
    "Painting": [
        ("Professional Oil Paint Set", "24-color oil paint set with brushes and palette", 5500, "Amazon", "amazon"),
    ],
    "Board Games": [
        ("Strategy Board Game Collection", "Set of 3 award-winning strategy games", 7900, "Amazon", "amazon"),
    ],
    "Karaoke": [
        ("Wireless Karaoke Microphone", "Bluetooth karaoke mic with built-in speaker", 3500, "Amazon", "amazon"),
    ],
}

_VIBE_EXPERIENCES: dict[str, list[tuple[str, str, int, str, str, str]]] = {
    "quiet_luxury": [
        ("Private Wine Tasting Experience", "Exclusive tasting at a boutique winery with sommelier", 12000, "Napa Valley Vintners", "yelp", "date"),
        ("Spa Day for Two", "Couples massage and full spa treatment package", 18000, "The Ritz Spa", "yelp", "experience"),
    ],
    "street_urban": [
        ("Street Art Walking Tour", "Guided tour of the city's best murals and graffiti art", 4500, "Urban Adventures", "yelp", "experience"),
        ("Underground Comedy Show", "Stand-up comedy night at an intimate underground venue", 3500, "The Comedy Cellar", "ticketmaster", "experience"),
    ],
    "outdoorsy": [
        ("Sunset Kayak Tour", "Guided sunset kayaking with wildlife spotting", 8500, "Paddle Co", "yelp", "experience"),
        ("Hot Air Balloon Ride", "Sunrise hot air balloon flight for two with champagne", 35000, "Sky High Balloons", "yelp", "experience"),
    ],
    "vintage": [
        ("Antique Market Tour", "Curated tour of the city's hidden antique shops", 5000, "Vintage Finds", "yelp", "date"),
        ("Prohibition-Era Cocktail Class", "Learn to make classic cocktails at a speakeasy", 7500, "The Speakeasy", "yelp", "date"),
    ],
    "minimalist": [
        ("Japanese Tea Ceremony", "Authentic matcha tea ceremony experience", 6000, "Tea Garden", "yelp", "experience"),
        ("Architecture Walking Tour", "Modernist architecture tour of the city's landmarks", 4000, "Design Tours", "yelp", "experience"),
    ],
    "bohemian": [
        ("Pottery Wheel Workshop", "Hands-on pottery making class for two people", 8500, "Clay Studio", "yelp", "date"),
        ("Indie Music Festival Pass", "Weekend pass to an indie music festival", 15000, "Festival Live", "ticketmaster", "experience"),
    ],
    "romantic": [
        ("Couples Sunset Cruise", "Private sunset sailing cruise with champagne toast", 22000, "Harbor Cruises", "yelp", "date"),
        ("Candlelit Cooking Class", "Italian cooking class with wine pairing for two", 14000, "Chef's Table", "yelp", "date"),
    ],
    "adventurous": [
        ("Skydiving Tandem Jump", "First-time tandem skydiving experience with instructor", 25000, "SkyCo Adventures", "yelp", "experience"),
        ("White Water Rafting Trip", "Half-day guided rafting on class III-IV rapids", 9500, "River Rush", "yelp", "experience"),
    ],
}


def _generate_candidate_id() -> str:
    return str(uuid.uuid4())


# Merchant search URL templates — these resolve to real search pages
_MERCHANT_SEARCH_URLS: dict[str, str] = {
    "amazon": "https://www.amazon.com/s?k={query}",
    "etsy": "https://www.etsy.com/search?q={query}",
    "shopify": "https://www.google.com/search?q={query}+buy+online",
    "yelp": "https://www.yelp.com/search?find_desc={query}",
    "ticketmaster": "https://www.ticketmaster.com/search?q={query}",
}


def _merchant_search_url(source: str, title: str) -> str:
    """Build a real search URL for the given merchant and product title."""
    template = _MERCHANT_SEARCH_URLS.get(
        source, "https://www.google.com/search?q={query}",
    )
    return template.format(query=quote_plus(title))


def _build_gift_candidate(
    interest: str,
    entry: tuple[str, str, int, str, str],
) -> CandidateRecommendation:
    title, description, price_cents, merchant_name, source = entry
    return CandidateRecommendation(
        id=_generate_candidate_id(),
        source=source,
        type="gift",
        title=title,
        description=description,
        price_cents=price_cents,
        price_confidence="estimated",
        external_url=_merchant_search_url(source, title),
        image_url=None,
        merchant_name=merchant_name,
        location=None,
        metadata={"matched_interest": interest, "catalog": "stub"},
    )


def _build_experience_candidate(
    vibe: str,
    entry: tuple[str, str, int, str, str, str],
    location: LocationData | None,
) -> CandidateRecommendation:
    title, description, price_cents, merchant_name, source, rec_type = entry
    return CandidateRecommendation(
        id=_generate_candidate_id(),
        source=source,
        type=rec_type,
        title=title,
        description=description,
        price_cents=price_cents,
        price_confidence="estimated",
        external_url=_merchant_search_url(source, title),
        image_url=None,
        merchant_name=merchant_name,
        location=location,
        metadata={"matched_vibe": vibe, "catalog": "stub"},
    )


async def _fetch_stub_candidates(
    vault_data: Any,
    budget: Any,
) -> list[CandidateRecommendation]:
    """Fallback: fetch candidates from stub catalogs when real services are down."""
    location = None
    if vault_data.location_city or vault_data.location_state or vault_data.location_country:
        location = LocationData(
            city=vault_data.location_city,
            state=vault_data.location_state,
            country=vault_data.location_country,
        )

    candidates: list[CandidateRecommendation] = []

    # Gifts from interests
    for interest in vault_data.interests:
        entries = _INTEREST_GIFTS.get(interest, [])
        for entry in entries:
            c = _build_gift_candidate(interest, entry)
            if c.price_cents is None or (budget.min_amount <= c.price_cents <= budget.max_amount):
                candidates.append(c)

    # Experiences from vibes
    for vibe in vault_data.vibes:
        entries = _VIBE_EXPERIENCES.get(vibe, [])
        for entry in entries:
            c = _build_experience_candidate(vibe, entry, location)
            if c.price_cents is None or (budget.min_amount <= c.price_cents <= budget.max_amount):
                candidates.append(c)

    return candidates


# ======================================================================
# LangGraph node
# ======================================================================

async def aggregate_external_data(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    LangGraph node: Aggregate candidate recommendations.

    Three-tier fallback:
    1. ClaudeSearchService (Brave Search + Claude extraction) — primary
    2. AggregatorService (Yelp, Ticketmaster, etc.) — secondary
    3. Stub catalogs — final

    Args:
        state: The current RecommendationState with vault_data, budget_range,
               relevant_hints, occasion_type, and optional milestone_context.

    Returns:
        A dict with "candidate_recommendations" key containing
        list[CandidateRecommendation], and optionally "error" if no
        candidates were found.
    """
    vault = state.vault_data
    budget = state.budget_range

    location_tuple = (
        vault.location_city or "",
        vault.location_state or "",
        vault.location_country,
    )
    budget_tuple = (budget.min_amount, budget.max_amount)

    # Prepare hints as plain text for the Claude search service
    hint_texts = [h.hint_text for h in state.relevant_hints if h.hint_text]

    # Prepare milestone context dict if present
    milestone_ctx = None
    if state.milestone_context:
        milestone_ctx = {
            "milestone_type": state.milestone_context.milestone_type,
            "milestone_name": state.milestone_context.milestone_name,
        }

    logger.info(
        "Aggregating candidates for vault %s: interests=%s, vibes=%s, "
        "budget=%d-%d %s, hints=%d",
        vault.vault_id, vault.interests, vault.vibes,
        budget.min_amount, budget.max_amount, budget.currency,
        len(hint_texts),
    )

    candidates: list[CandidateRecommendation] = []

    # --- Tier 1: Claude Search (primary) ---
    try:
        claude_service = ClaudeSearchService()
        raw_candidates = await claude_service.search(
            interests=vault.interests,
            vibes=vault.vibes,
            location=location_tuple,
            budget_range=budget_tuple,
            occasion_type=state.occasion_type,
            hints=hint_texts,
            milestone_context=milestone_ctx,
        )

        for raw in raw_candidates:
            try:
                candidates.append(_dict_to_candidate(raw))
            except (KeyError, ValueError) as e:
                logger.warning(
                    "Skipping malformed Claude candidate: %s — %s",
                    e, raw.get("title", "unknown"),
                )

        if candidates:
            logger.info(
                "Claude Search returned %d candidates for vault %s",
                len(candidates), vault.vault_id,
            )
    except Exception as e:
        logger.warning(
            "Claude Search failed for vault %s: %s — trying AggregatorService",
            vault.vault_id, e,
        )

    # --- Tier 2: AggregatorService (secondary fallback) ---
    if not candidates:
        logger.info(
            "Tier 1 returned 0 candidates for vault %s, trying AggregatorService",
            vault.vault_id,
        )
        try:
            aggregator = AggregatorService()
            raw_candidates = await aggregator.aggregate(
                interests=vault.interests,
                vibes=vault.vibes,
                location=location_tuple,
                budget_range=budget_tuple,
                limit_per_service=10,
            )

            for raw in raw_candidates:
                try:
                    candidates.append(_dict_to_candidate(raw))
                except (KeyError, ValueError) as e:
                    logger.warning(
                        "Skipping malformed candidate: %s — %s",
                        e, raw.get("title", "unknown"),
                    )

            if candidates:
                logger.info(
                    "AggregatorService returned %d candidates for vault %s",
                    len(candidates), vault.vault_id,
                )
        except Exception as e:
            logger.warning(
                "AggregatorService also failed for vault %s: %s — falling back to stubs",
                vault.vault_id, e,
            )

    # --- Tier 3: Stub catalogs (supplement or full fallback) ---
    if len(candidates) < TARGET_CANDIDATE_COUNT:
        if not candidates:
            logger.warning(
                "All services returned 0 candidates for vault %s, using stubs",
                vault.vault_id,
            )
        else:
            logger.info(
                "Only %d candidates from services for vault %s, supplementing with stubs",
                len(candidates), vault.vault_id,
            )
        stub_candidates = await _fetch_stub_candidates(vault, budget)
        existing_titles = {c.title.lower() for c in candidates}
        for stub in stub_candidates:
            if stub.title.lower() not in existing_titles:
                candidates.append(stub)
                existing_titles.add(stub.title.lower())

    # Filter candidates outside budget range
    pre_filter_count = len(candidates)
    candidates = [
        c for c in candidates
        if c.price_cents is None
        or (budget.min_amount <= c.price_cents <= budget.max_amount)
    ]
    if len(candidates) < pre_filter_count:
        logger.info(
            "Budget filter removed %d candidates outside %d-%d range",
            pre_filter_count - len(candidates),
            budget.min_amount, budget.max_amount,
        )

    # Cap at target count
    candidates = candidates[:TARGET_CANDIDATE_COUNT]

    logger.info(
        "Aggregated %d candidates for vault %s",
        len(candidates), vault.vault_id,
    )

    result: dict[str, Any] = {"candidate_recommendations": candidates}

    if not candidates:
        result["error"] = "No candidates found matching budget and criteria"
        logger.warning("No candidates found for vault %s", vault.vault_id)

    return result

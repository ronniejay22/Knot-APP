//
//  DTOs.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.11: Data Transfer Objects for backend API communication.
//  Step 4.2: Added Hint DTOs (HintCreatePayload, HintCreateResponse, HintListResponse, HintItemResponse).
//  Step 6.5: Added vibeOverride to RecommendationRefreshPayload for manual vibe override.
//

import Foundation

// MARK: - Vault Creation Request

/// Payload for `POST /api/v1/vault` — matches the backend Pydantic `VaultCreateRequest`.
///
/// Contains all partner profile data collected during the onboarding flow.
/// JSON keys use snake_case to match the FastAPI backend convention.
struct VaultCreatePayload: Codable, Sendable {
    let partnerName: String
    let relationshipTenureMonths: Int?
    let cohabitationStatus: String?
    let locationCity: String?
    let locationState: String?
    let locationCountry: String?

    let interests: [String]   // exactly 5 likes
    let dislikes: [String]    // exactly 5 hard avoids

    let milestones: [MilestonePayload]
    let vibes: [String]       // 1–8 valid vibe tags
    let budgets: [BudgetPayload]
    let loveLanguages: LoveLanguagesPayload

    enum CodingKeys: String, CodingKey {
        case partnerName = "partner_name"
        case relationshipTenureMonths = "relationship_tenure_months"
        case cohabitationStatus = "cohabitation_status"
        case locationCity = "location_city"
        case locationState = "location_state"
        case locationCountry = "location_country"
        case interests, dislikes, milestones, vibes, budgets
        case loveLanguages = "love_languages"
    }
}

/// A single milestone in the vault submission payload.
struct MilestonePayload: Codable, Sendable {
    let milestoneType: String
    let milestoneName: String
    let milestoneDate: String  // ISO date format: "2000-MM-DD"
    let recurrence: String     // "yearly" or "one_time"
    let budgetTier: String?    // nil → DB trigger sets default

    enum CodingKeys: String, CodingKey {
        case milestoneType = "milestone_type"
        case milestoneName = "milestone_name"
        case milestoneDate = "milestone_date"
        case recurrence
        case budgetTier = "budget_tier"
    }
}

/// A single budget tier in the vault submission payload.
/// Amounts are in cents (e.g., 2000 = $20.00).
struct BudgetPayload: Codable, Sendable {
    let occasionType: String
    let minAmount: Int
    let maxAmount: Int
    let currency: String

    enum CodingKeys: String, CodingKey {
        case occasionType = "occasion_type"
        case minAmount = "min_amount"
        case maxAmount = "max_amount"
        case currency
    }
}

/// Primary and secondary love language selections.
struct LoveLanguagesPayload: Codable, Sendable {
    let primary: String
    let secondary: String
}

// MARK: - Vault Creation Response

/// Response from `POST /api/v1/vault` — matches the backend Pydantic `VaultCreateResponse`.
struct VaultCreateResponse: Codable, Sendable {
    let vaultId: String
    let partnerName: String
    let interestsCount: Int
    let dislikesCount: Int
    let milestonesCount: Int
    let vibesCount: Int
    let budgetsCount: Int
    let loveLanguages: [String: String]

    enum CodingKeys: String, CodingKey {
        case vaultId = "vault_id"
        case partnerName = "partner_name"
        case interestsCount = "interests_count"
        case dislikesCount = "dislikes_count"
        case milestonesCount = "milestones_count"
        case vibesCount = "vibes_count"
        case budgetsCount = "budgets_count"
        case loveLanguages = "love_languages"
    }
}

// MARK: - Vault GET Response (Step 3.12)

/// Full vault data returned by `GET /api/v1/vault`.
/// Matches the backend Pydantic `VaultGetResponse`.
struct VaultGetResponse: Codable, Sendable {
    let vaultId: String
    let partnerName: String
    let relationshipTenureMonths: Int?
    let cohabitationStatus: String?
    let locationCity: String?
    let locationState: String?
    let locationCountry: String?

    let interests: [String]
    let dislikes: [String]
    let milestones: [MilestoneGetResponse]
    let vibes: [String]
    let budgets: [BudgetGetResponse]
    let loveLanguages: [LoveLanguageGetResponse]

    enum CodingKeys: String, CodingKey {
        case vaultId = "vault_id"
        case partnerName = "partner_name"
        case relationshipTenureMonths = "relationship_tenure_months"
        case cohabitationStatus = "cohabitation_status"
        case locationCity = "location_city"
        case locationState = "location_state"
        case locationCountry = "location_country"
        case interests, dislikes, milestones, vibes, budgets
        case loveLanguages = "love_languages"
    }
}

/// A single milestone in the vault GET response.
struct MilestoneGetResponse: Codable, Sendable {
    let id: String
    let milestoneType: String
    let milestoneName: String
    let milestoneDate: String
    let recurrence: String
    let budgetTier: String?

    enum CodingKeys: String, CodingKey {
        case id
        case milestoneType = "milestone_type"
        case milestoneName = "milestone_name"
        case milestoneDate = "milestone_date"
        case recurrence
        case budgetTier = "budget_tier"
    }
}

/// A single budget tier in the vault GET response.
struct BudgetGetResponse: Codable, Sendable {
    let id: String
    let occasionType: String
    let minAmount: Int
    let maxAmount: Int
    let currency: String

    enum CodingKeys: String, CodingKey {
        case id
        case occasionType = "occasion_type"
        case minAmount = "min_amount"
        case maxAmount = "max_amount"
        case currency
    }
}

/// A single love language entry in the vault GET response.
struct LoveLanguageGetResponse: Codable, Sendable {
    let language: String
    let priority: Int
}

// MARK: - Vault Update Response (Step 3.12)

/// Response from `PUT /api/v1/vault` — matches the backend Pydantic `VaultUpdateResponse`.
struct VaultUpdateResponse: Codable, Sendable {
    let vaultId: String
    let partnerName: String
    let interestsCount: Int
    let dislikesCount: Int
    let milestonesCount: Int
    let vibesCount: Int
    let budgetsCount: Int
    let loveLanguages: [String: String]

    enum CodingKeys: String, CodingKey {
        case vaultId = "vault_id"
        case partnerName = "partner_name"
        case interestsCount = "interests_count"
        case dislikesCount = "dislikes_count"
        case milestonesCount = "milestones_count"
        case vibesCount = "vibes_count"
        case budgetsCount = "budgets_count"
        case loveLanguages = "love_languages"
    }
}

// MARK: - Hint Creation Request (Step 4.2)

/// Payload for `POST /api/v1/hints` — matches the backend Pydantic `HintCreateRequest`.
struct HintCreatePayload: Codable, Sendable {
    let hintText: String
    let source: String  // "text_input" or "voice_transcription"

    enum CodingKeys: String, CodingKey {
        case hintText = "hint_text"
        case source
    }
}

// MARK: - Hint Creation Response (Step 4.2)

/// Response from `POST /api/v1/hints` — matches the backend Pydantic `HintCreateResponse`.
struct HintCreateResponse: Codable, Sendable {
    let id: String
    let hintText: String
    let source: String
    let isUsed: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case hintText = "hint_text"
        case source
        case isUsed = "is_used"
        case createdAt = "created_at"
    }
}

// MARK: - Hint List Response (Step 4.2)

/// Response from `GET /api/v1/hints` — matches the backend Pydantic `HintListResponse`.
struct HintListResponse: Codable, Sendable {
    let hints: [HintItemResponse]
    let total: Int
}

/// A single hint in the list response.
struct HintItemResponse: Codable, Sendable {
    let id: String
    let hintText: String
    let source: String
    let isUsed: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case hintText = "hint_text"
        case source
        case isUsed = "is_used"
        case createdAt = "created_at"
    }
}

// MARK: - Recommendation Generate Request (Step 6.2)

/// Payload for `POST /api/v1/recommendations/generate`.
struct RecommendationGeneratePayload: Codable, Sendable {
    let milestoneId: String?
    let occasionType: String

    enum CodingKeys: String, CodingKey {
        case milestoneId = "milestone_id"
        case occasionType = "occasion_type"
    }
}

// MARK: - Recommendation Refresh Request (Step 6.2)

/// Payload for `POST /api/v1/recommendations/refresh`.
struct RecommendationRefreshPayload: Codable, Sendable {
    let rejectedRecommendationIds: [String]
    let rejectionReason: String
    let vibeOverride: [String]?

    enum CodingKeys: String, CodingKey {
        case rejectedRecommendationIds = "rejected_recommendation_ids"
        case rejectionReason = "rejection_reason"
        case vibeOverride = "vibe_override"
    }
}

// MARK: - Recommendation Generate Response (Step 6.2)

/// Response from `POST /api/v1/recommendations/generate`.
struct RecommendationGenerateResponse: Codable, Sendable {
    let recommendations: [RecommendationItemResponse]
    let count: Int
    let milestoneId: String?
    let occasionType: String

    enum CodingKeys: String, CodingKey {
        case recommendations, count
        case milestoneId = "milestone_id"
        case occasionType = "occasion_type"
    }
}

// MARK: - Recommendation Refresh Response (Step 6.2)

/// Response from `POST /api/v1/recommendations/refresh`.
struct RecommendationRefreshResponse: Codable, Sendable {
    let recommendations: [RecommendationItemResponse]
    let count: Int
    let rejectionReason: String

    enum CodingKeys: String, CodingKey {
        case recommendations, count
        case rejectionReason = "rejection_reason"
    }
}

// MARK: - Recommendation Item Response (Step 6.2)

/// A single recommendation in the Choice-of-Three response.
struct RecommendationItemResponse: Codable, Sendable, Identifiable {
    let id: String
    let recommendationType: String
    let title: String
    let description: String?
    let priceCents: Int?
    let currency: String
    let externalUrl: String
    let imageUrl: String?
    let merchantName: String?
    let source: String
    let location: RecommendationLocationResponse?
    let interestScore: Double
    let vibeScore: Double
    let loveLanguageScore: Double
    let finalScore: Double

    enum CodingKeys: String, CodingKey {
        case id
        case recommendationType = "recommendation_type"
        case title, description
        case priceCents = "price_cents"
        case currency
        case externalUrl = "external_url"
        case imageUrl = "image_url"
        case merchantName = "merchant_name"
        case source, location
        case interestScore = "interest_score"
        case vibeScore = "vibe_score"
        case loveLanguageScore = "love_language_score"
        case finalScore = "final_score"
    }
}

/// Location info for experience/date recommendations.
struct RecommendationLocationResponse: Codable, Sendable {
    let city: String?
    let state: String?
    let country: String?
    let address: String?
}

// MARK: - Recommendation Feedback Request (Step 6.3)

/// Payload for `POST /api/v1/recommendations/feedback`.
struct RecommendationFeedbackPayload: Codable, Sendable {
    let recommendationId: String
    let action: String  // "selected", "saved", "shared", "rated"

    enum CodingKeys: String, CodingKey {
        case recommendationId = "recommendation_id"
        case action
    }
}

// MARK: - Recommendation Feedback Response (Step 6.3)

/// Response from `POST /api/v1/recommendations/feedback`.
struct RecommendationFeedbackResponse: Codable, Sendable {
    let id: String
    let recommendationId: String
    let action: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case recommendationId = "recommendation_id"
        case action
        case createdAt = "created_at"
    }
}

// MARK: - Device Token Registration (Step 7.4)

/// Payload for `POST /api/v1/users/device-token`.
struct DeviceTokenPayload: Codable, Sendable {
    let deviceToken: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case platform
    }
}

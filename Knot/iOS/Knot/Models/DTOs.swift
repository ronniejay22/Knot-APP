//
//  DTOs.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.11: Data Transfer Objects for backend API communication.
//  Step 4.2: Added Hint DTOs (HintCreatePayload, HintCreateResponse, HintListResponse, HintItemResponse).
//  Step 6.5: Added vibeOverride to RecommendationRefreshPayload for manual vibe override.
//  Step 7.7: Added Notification History and Milestone Recommendations DTOs.
//  Step 11.4: Added Notification Preferences DTOs.
//  Step 14.6: Added Knot Originals DTOs (IdeaContentSection, IdeaGeneratePayload,
//             IdeaItemResponse, IdeaGenerateResponse, IdeaListResponse).
//             Made externalUrl optional on RecommendationItemResponse for ideas.
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
    let priceConfidence: String?
    let externalUrl: String?
    let imageUrl: String?
    let merchantName: String?
    let source: String
    let location: RecommendationLocationResponse?
    // Knot Originals fields (Step 14.6)
    let isIdea: Bool?
    let contentSections: [IdeaContentSection]?
    let interestScore: Double
    let vibeScore: Double
    let loveLanguageScore: Double
    let finalScore: Double
    let matchedInterests: [String]?
    let matchedVibes: [String]?
    let matchedLoveLanguages: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case recommendationType = "recommendation_type"
        case title, description
        case priceCents = "price_cents"
        case currency
        case priceConfidence = "price_confidence"
        case externalUrl = "external_url"
        case imageUrl = "image_url"
        case merchantName = "merchant_name"
        case source, location
        case isIdea = "is_idea"
        case contentSections = "content_sections"
        case interestScore = "interest_score"
        case vibeScore = "vibe_score"
        case loveLanguageScore = "love_language_score"
        case finalScore = "final_score"
        case matchedInterests = "matched_interests"
        case matchedVibes = "matched_vibes"
        case matchedLoveLanguages = "matched_love_languages"
    }
}

/// Location info for experience/date recommendations.
struct RecommendationLocationResponse: Codable, Sendable {
    let city: String?
    let state: String?
    let country: String?
    let address: String?
}

// MARK: - Knot Originals / Ideas DTOs (Step 14.6)

/// A single section of structured content within a Knot Original idea.
///
/// Each idea contains multiple sections (overview, steps, tips, etc.) that are
/// rendered in a dedicated detail view. Sections use either `body` (paragraph text)
/// or `items` (list of strings), never both.
struct IdeaContentSection: Codable, Sendable, Identifiable {
    /// Local-only identifier for SwiftUI list rendering.
    var id: String { "\(type)-\(heading)" }

    let type: String
    let heading: String
    let body: String?
    let items: [String]?
}

/// Payload for `POST /api/v1/ideas/generate`.
struct IdeaGeneratePayload: Codable, Sendable {
    let count: Int
    let occasionType: String
    let category: String?

    init(count: Int = 3, occasionType: String = "just_because", category: String? = nil) {
        self.count = count
        self.occasionType = occasionType
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case count
        case occasionType = "occasion_type"
        case category
    }
}

/// A single Knot Original idea in the API response.
struct IdeaItemResponse: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let recommendationType: String
    let contentSections: [IdeaContentSection]
    let matchedInterests: [String]?
    let matchedVibes: [String]?
    let matchedLoveLanguages: [String]?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case recommendationType = "recommendation_type"
        case contentSections = "content_sections"
        case matchedInterests = "matched_interests"
        case matchedVibes = "matched_vibes"
        case matchedLoveLanguages = "matched_love_languages"
        case createdAt = "created_at"
    }
}

/// Response from `POST /api/v1/ideas/generate`.
struct IdeaGenerateResponse: Codable, Sendable {
    let ideas: [IdeaItemResponse]
    let count: Int
}

/// Response from `GET /api/v1/ideas` (paginated).
struct IdeaListResponse: Codable, Sendable {
    let ideas: [IdeaItemResponse]
    let count: Int
    let total: Int
}

// MARK: - Recommendation Feedback Request (Step 6.3, Step 9.4)

/// Payload for `POST /api/v1/recommendations/feedback`.
struct RecommendationFeedbackPayload: Codable, Sendable {
    let recommendationId: String
    let action: String  // "selected", "saved", "shared", "rated", "handoff", "purchased"
    let rating: Int?
    let feedbackText: String?

    init(recommendationId: String, action: String, rating: Int? = nil, feedbackText: String? = nil) {
        self.recommendationId = recommendationId
        self.action = action
        self.rating = rating
        self.feedbackText = feedbackText
    }

    enum CodingKeys: String, CodingKey {
        case recommendationId = "recommendation_id"
        case action
        case rating
        case feedbackText = "feedback_text"
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

// MARK: - Notification History Response (Step 7.7)

/// Response from `GET /api/v1/notifications/history`.
/// Returns the user's sent/failed notifications with milestone metadata.
struct NotificationHistoryResponse: Codable, Sendable {
    let notifications: [NotificationHistoryItemResponse]
    let total: Int
}

/// A single notification in the history response.
struct NotificationHistoryItemResponse: Codable, Sendable, Identifiable {
    let id: String
    let milestoneId: String
    let milestoneName: String
    let milestoneType: String
    let milestoneDate: String?
    let daysBefore: Int
    let status: String
    let sentAt: String?
    let viewedAt: String?
    let createdAt: String
    let recommendationsCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case milestoneId = "milestone_id"
        case milestoneName = "milestone_name"
        case milestoneType = "milestone_type"
        case milestoneDate = "milestone_date"
        case daysBefore = "days_before"
        case status
        case sentAt = "sent_at"
        case viewedAt = "viewed_at"
        case createdAt = "created_at"
        case recommendationsCount = "recommendations_count"
    }
}

// MARK: - Milestone Recommendations Response (Step 7.7)

/// Response from `GET /api/v1/recommendations/by-milestone/{milestone_id}`.
/// Returns pre-generated recommendations associated with a notification's milestone.
struct MilestoneRecommendationsResponse: Codable, Sendable {
    let recommendations: [MilestoneRecommendationItemResponse]
    let count: Int
    let milestoneId: String

    enum CodingKeys: String, CodingKey {
        case recommendations, count
        case milestoneId = "milestone_id"
    }
}

/// A single recommendation from the milestone-specific endpoint.
struct MilestoneRecommendationItemResponse: Codable, Sendable, Identifiable {
    let id: String
    let recommendationType: String
    let title: String
    let description: String?
    let externalUrl: String?
    let priceCents: Int?
    let merchantName: String?
    let imageUrl: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case recommendationType = "recommendation_type"
        case title, description
        case externalUrl = "external_url"
        case priceCents = "price_cents"
        case merchantName = "merchant_name"
        case imageUrl = "image_url"
        case createdAt = "created_at"
    }
}

// MARK: - Data Export DTOs (Step 11.3)

/// Full data export returned by `GET /api/v1/users/me/export`.
/// Decoded on iOS to render a styled PDF export document.
struct DataExportResponse: Codable, Sendable {
    let exportedAt: String
    let user: ExportUser
    let partnerVault: ExportVault?
    let milestones: [ExportMilestone]
    let hints: [ExportHint]
    let recommendations: [ExportRecommendation]
    let feedback: [ExportFeedback]
    let notifications: [ExportNotification]

    enum CodingKeys: String, CodingKey {
        case exportedAt = "exported_at"
        case user
        case partnerVault = "partner_vault"
        case milestones, hints, recommendations, feedback, notifications
    }
}

struct ExportUser: Codable, Sendable {
    let id: String
    let email: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case createdAt = "created_at"
    }
}

struct ExportVault: Codable, Sendable {
    let partnerName: String
    let relationshipTenureMonths: Int?
    let cohabitationStatus: String?
    let locationCity: String?
    let locationState: String?
    let locationCountry: String?
    let interests: [String]
    let dislikes: [String]
    let vibes: [String]
    let budgets: [ExportBudget]
    let loveLanguages: [ExportLoveLanguage]
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case partnerName = "partner_name"
        case relationshipTenureMonths = "relationship_tenure_months"
        case cohabitationStatus = "cohabitation_status"
        case locationCity = "location_city"
        case locationState = "location_state"
        case locationCountry = "location_country"
        case interests, dislikes, vibes, budgets
        case loveLanguages = "love_languages"
        case createdAt = "created_at"
    }
}

struct ExportBudget: Codable, Sendable {
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

struct ExportLoveLanguage: Codable, Sendable {
    let language: String
    let priority: Int
}

struct ExportMilestone: Codable, Sendable {
    let milestoneType: String
    let milestoneName: String
    let milestoneDate: String
    let recurrence: String
    let budgetTier: String?

    enum CodingKeys: String, CodingKey {
        case milestoneType = "milestone_type"
        case milestoneName = "milestone_name"
        case milestoneDate = "milestone_date"
        case recurrence
        case budgetTier = "budget_tier"
    }
}

struct ExportHint: Codable, Sendable {
    let hintText: String
    let source: String
    let isUsed: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case hintText = "hint_text"
        case source
        case isUsed = "is_used"
        case createdAt = "created_at"
    }
}

struct ExportRecommendation: Codable, Sendable {
    let recommendationType: String
    let title: String
    let description: String?
    let externalUrl: String?
    let priceCents: Int?
    let merchantName: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case recommendationType = "recommendation_type"
        case title, description
        case externalUrl = "external_url"
        case priceCents = "price_cents"
        case merchantName = "merchant_name"
        case createdAt = "created_at"
    }
}

struct ExportFeedback: Codable, Sendable {
    let recommendationId: String
    let action: String
    let rating: Int?
    let feedbackText: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case recommendationId = "recommendation_id"
        case action, rating
        case feedbackText = "feedback_text"
        case createdAt = "created_at"
    }
}

struct ExportNotification: Codable, Sendable {
    let milestoneId: String
    let scheduledFor: String
    let daysBefore: Int
    let status: String
    let sentAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case milestoneId = "milestone_id"
        case scheduledFor = "scheduled_for"
        case daysBefore = "days_before"
        case status
        case sentAt = "sent_at"
        case createdAt = "created_at"
    }
}

// MARK: - Notification Preferences (Step 11.4)

/// Response from GET /api/v1/users/me/notification-preferences.
///
/// Contains the user's current notification settings including global toggle,
/// quiet hours range, and timezone.
struct NotificationPreferencesDTO: Codable, Sendable {
    let notificationsEnabled: Bool
    let quietHoursStart: Int
    let quietHoursEnd: Int
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case notificationsEnabled = "notifications_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case timezone
    }
}

/// Payload for PUT /api/v1/users/me/notification-preferences.
///
/// All fields are optional — only provided fields are updated on the backend.
struct NotificationPreferencesUpdateDTO: Codable, Sendable {
    let notificationsEnabled: Bool?
    let quietHoursStart: Int?
    let quietHoursEnd: Int?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case notificationsEnabled = "notifications_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case timezone
    }
}

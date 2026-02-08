//
//  DTOs.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.11: Data Transfer Objects for backend API communication.
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

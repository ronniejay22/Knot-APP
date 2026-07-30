//
//  RecommendationFallbackImage.swift
//  Knot
//
//  A local, bundled photo shown whenever a recommendation's remote image is
//  missing or fails to load. This guarantees a real photo is ALWAYS visible on a
//  recommendation surface — a recommendation card never shows a gradient or a
//  blank state, even offline or when the remote image request fails.
//
//  The per-type photos mirror the backend's `_TYPE_DEFAULT_IMAGES`
//  (backend/app/agents/aggregation.py), so the on-device fallback matches the
//  remote default the API would otherwise serve.
//

import SwiftUI

/// A `contentMode: .fill` local photo keyed to a recommendation type. Use it as
/// the always-present base beneath an `AsyncImage`, and as the `.failure` /
/// `.empty` result, so a real image is shown in every state.
///
/// The photo is hosted in a flexible `Color.clear` and clipped, so it fills its
/// container without imposing the image's intrinsic size on the layout (the same
/// pattern the remote `.success` image uses). This keeps the card sized by its
/// own frame — a raw `.fill` image would otherwise blow out the card width.
struct RecommendationFallbackImage: View {
    let recommendationType: String

    var body: some View {
        Color.clear
            .overlay {
                Image(Self.assetName(for: recommendationType))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }

    /// Asset-catalog name of the bundled fallback photo for a recommendation type.
    /// Unknown/`plan`-adjacent types fall through to a neutral default so the
    /// lookup can never miss.
    static func assetName(for recommendationType: String) -> String {
        switch recommendationType {
        case "gift": return "RecFallbackGift"
        case "experience": return "RecFallbackExperience"
        case "date": return "RecFallbackDate"
        case "idea": return "RecFallbackIdea"
        case "plan": return "RecFallbackPlan"
        default: return "RecFallbackDefault"
        }
    }
}

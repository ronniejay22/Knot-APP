//
//  SavedRecommendationMigrationTests.swift
//  KnotTests
//
//  The Moments feature stored `completedAt` / `rating` / `reflectionNote` on
//  every saved item. Removing those fields changes the on-disk schema, and the
//  app opens its store in `KnotApp` with no migration plan and a `fatalError`
//  on failure — so an install carrying the old columns has to migrate on its
//  own or the app would crash at launch.
//

import XCTest
import SwiftData
@testable import Knot

/// `SavedRecommendation` as it stood before the Moments fields were removed,
/// used only to write a store in that shape. Nested so its entity keeps the
/// name `SavedRecommendation`, the way `VersionedSchema` models do.
private enum SchemaWithMoments {

    @Model
    final class SavedRecommendation {
        @Attribute(.unique) var recommendationId: String
        var recommendationType: String
        var title: String
        var descriptionText: String?
        var externalURL: String?
        var priceCents: Int?
        var currency: String
        var merchantName: String?
        var imageURL: String?
        var isIdea: Bool
        var contentSectionsData: Data?
        var milestoneId: String?
        var savedAt: Date
        var completedAt: Date?
        var rating: Int?
        var reflectionNote: String?

        init(
            recommendationId: String,
            title: String,
            savedAt: Date,
            completedAt: Date? = nil,
            rating: Int? = nil,
            reflectionNote: String? = nil
        ) {
            self.recommendationId = recommendationId
            self.recommendationType = "date"
            self.title = title
            self.currency = "USD"
            self.isIdea = true
            self.savedAt = savedAt
            self.completedAt = completedAt
            self.rating = rating
            self.reflectionNote = reflectionNote
        }
    }
}

@MainActor
final class SavedRecommendationMigrationTests: XCTestCase {

    /// A completed Moment and a plain saved idea, written with the old
    /// columns, both come back through the current model.
    func testStoreWithMomentsFieldsOpensWithEveryItem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Saved.store")

        // Both containers register every model `KnotApp.sharedModelContainer`
        // does, so the store is laid out like the app's. Only the location
        // differs: a test must not open the host app's default store.
        //
        // The pool releases the old container, and the store it holds open,
        // before the current model opens the same file.
        try autoreleasepool {
            let legacy = try ModelContainer(
                for: Schema([
                    PartnerVaultLocal.self,
                    HintLocal.self,
                    MilestoneLocal.self,
                    RecommendationLocal.self,
                    SchemaWithMoments.SavedRecommendation.self,
                ]),
                configurations: ModelConfiguration(url: storeURL)
            )
            let context = ModelContext(legacy)
            context.insert(SchemaWithMoments.SavedRecommendation(
                recommendationId: "moment",
                title: "Movie Night",
                savedAt: Date(timeIntervalSince1970: 2000),
                completedAt: Date(timeIntervalSince1970: 3000),
                rating: 5,
                reflectionNote: "We stayed up talking about the soundtrack."
            ))
            context.insert(SchemaWithMoments.SavedRecommendation(
                recommendationId: "idea",
                title: "Sunset Picnic",
                savedAt: Date(timeIntervalSince1970: 1000)
            ))
            try context.save()
        }

        let current = try ModelContainer(
            for: Schema([
                PartnerVaultLocal.self,
                HintLocal.self,
                MilestoneLocal.self,
                RecommendationLocal.self,
                SavedRecommendation.self,
            ]),
            configurations: ModelConfiguration(url: storeURL)
        )
        let items = try ModelContext(current).fetch(
            FetchDescriptor<SavedRecommendation>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        )

        XCTAssertEqual(items.map(\.recommendationId), ["moment", "idea"])
        XCTAssertEqual(items.map(\.title), ["Movie Night", "Sunset Picnic"])
    }
}

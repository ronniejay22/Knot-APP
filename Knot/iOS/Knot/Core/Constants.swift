//
//  Constants.swift
//  Knot
//
//  Created on February 3, 2026.
//

import Foundation

/// App-wide constants
enum Constants {
    /// API Configuration
    enum API {
        static let baseURL = "https://api.knot-app.com"
        static let version = "v1"
    }
    
    /// Validation Rules
    enum Validation {
        static let maxHintLength = 500
        static let requiredInterests = 5
        static let requiredDislikes = 5
        static let maxVibes = 4
        static let minVibes = 1
    }
    
    /// Interest Categories (41 total)
    static let interestCategories: [String] = [
        "Travel", "Cooking", "Movies", "Music", "Reading", "Sports", "Gaming", "Art",
        "Photography", "Fitness", "Fashion", "Technology", "Nature", "Food", "Coffee",
        "Wine", "Dancing", "Theater", "Concerts", "Museums", "Shopping", "Yoga",
        "Hiking", "Beach", "Pets", "Cars", "DIY", "Gardening", "Meditation",
        "Podcasts", "Baking", "Camping", "Cycling", "Running", "Swimming", "Skiing",
        "Surfing", "Painting", "Board Games", "Karaoke"
    ]
    
    /// Vibe Options (8 total)
    static let vibeOptions: [String] = [
        "quiet_luxury", "street_urban", "outdoorsy", "vintage",
        "minimalist", "bohemian", "romantic", "adventurous"
    ]
    
    /// Love Languages
    static let loveLanguages: [String] = [
        "words_of_affirmation", "acts_of_service", "receiving_gifts",
        "quality_time", "physical_touch"
    ]
}

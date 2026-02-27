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
    ///
    /// During development, the backend runs locally via `uvicorn`.
    /// Change `baseURL` to the production Vercel URL before deployment.
    enum API {
        #if DEBUG
        static let baseURL = "http://127.0.0.1:8000"
        #else
        static let baseURL = "https://api.knot-app.com"
        #endif
        static let version = "v1"
    }

    /// Supabase Configuration
    /// The anon key is the publishable (public) key — safe to embed in the app binary.
    /// Row Level Security (RLS) in the database enforces per-user access control.
    enum Supabase {
        static let projectURL = URL(string: "https://nmruwlfvhkvkbcdncwaq.supabase.co")!
        static let anonKey = "sb_publishable_QhaP3fnVMLpH-lE2n1XWvQ_X-1zodXi"
        static let redirectURL = URL(string: "com.ronniejay.knot://login-callback")!
    }

    /// Google Sign-In Configuration
    /// Uses the native Google Sign-In SDK for a seamless in-app authentication experience.
    /// `clientID` is the iOS OAuth Client ID (used by the native SDK on device).
    /// `webClientID` is the Web OAuth Client ID (used by Supabase for token verification).
    enum Google {
        static let clientID = "528827192667-b0tsanftdkjjn616b4bph5sv3un35859.apps.googleusercontent.com"
        static let webClientID = "528827192667-nk58fts62eq99v1d96djqc7gg311iske.apps.googleusercontent.com"
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

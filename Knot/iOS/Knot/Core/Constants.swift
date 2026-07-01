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
    /// Release builds use the production server. DEBUG builds target the local
    /// backend: the Mac's current LAN IP is auto-detected and written into a
    /// bundled `DevServer.plist` (`DevAPIBaseURL`) at build time by
    /// `scripts/inject-dev-host.sh`, so the simulator AND a physical iPhone on
    /// the same Wi-Fi both connect with no manual edits. Run the backend with
    /// `backend/scripts/dev.sh` (binds 0.0.0.0).
    enum API {
        #if DEBUG
        static let baseURL = resolveDebugBaseURL()

        /// The hardcoded fallback when no injected/override value is present.
        /// Stays loopback — never commit a LAN IP here.
        static let debugFallbackBaseURL = "http://127.0.0.1:8000"

        /// UserDefaults key for a manual override that wins over auto-detection
        /// (e.g. `defaults write … KnotDevAPIBaseURL http://10.0.0.5:8000`).
        static let debugOverrideKey = "KnotDevAPIBaseURL"

        /// Whether this DEBUG build is running in the iOS Simulator. The
        /// simulator shares the Mac's loopback, so `127.0.0.1` always reaches a
        /// local backend regardless of how uvicorn is bound; the injected LAN IP
        /// is only needed on a physical device.
        #if targetEnvironment(simulator)
        static let isRunningInSimulator = true
        #else
        static let isRunningInSimulator = false
        #endif

        /// Reads the build-time auto-detected host from the bundled DevServer.plist.
        static func injectedDevBaseURL() -> String? {
            guard let url = Bundle.main.url(forResource: "DevServer", withExtension: "plist"),
                  let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
                return nil
            }
            return dict["DevAPIBaseURL"] as? String
        }

        /// Resolves the DEBUG base URL in priority order:
        /// 1. `UserDefaults[KnotDevAPIBaseURL]` — manual override escape hatch.
        /// 2. `DevServer.plist[DevAPIBaseURL]` — build-time auto-detected Mac LAN
        ///    IP — physical device only.
        /// 3. `http://127.0.0.1:8000` — loopback (also the Simulator's default).
        ///
        /// On the Simulator the injected LAN IP is skipped: the simulator shares
        /// the Mac's loopback, so `127.0.0.1` always reaches the local backend
        /// even when uvicorn is bound to loopback only. Using the LAN IP there
        /// fails (cannotConnectToHost) whenever the backend isn't on `0.0.0.0`.
        ///
        /// Inputs are injected for testability.
        static func resolveDebugBaseURL(
            override: String? = UserDefaults.standard.string(forKey: debugOverrideKey),
            injected: String? = injectedDevBaseURL(),
            isSimulator: Bool = isRunningInSimulator
        ) -> String {
            if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
                return override
            }
            if !isSimulator, let injected, !injected.trimmingCharacters(in: .whitespaces).isEmpty {
                return injected
            }
            return debugFallbackBaseURL
        }
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
        static let minInterests = 5
        static let minDislikes = 5
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

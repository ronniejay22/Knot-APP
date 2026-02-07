//
//  ContentView.swift
//  Knot
//
//  Created on February 3, 2026.
//  Updated February 6, 2026 — Step 2.1: Show SignInView as the initial screen.
//

import SwiftUI

/// Root view of the app. Displays the appropriate screen based on auth state.
/// Currently shows SignInView (Step 2.1). Session-based navigation will be
/// added in Step 2.3 to conditionally show Home vs Sign-In.
struct ContentView: View {
    var body: some View {
        SignInView()
    }
}

#Preview {
    ContentView()
}

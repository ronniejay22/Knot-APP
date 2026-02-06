//
//  ContentView.swift
//  Knot
//
//  Created on February 3, 2026.
//

import SwiftUI
import LucideIcons

struct ContentView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Lucide Heart icon (verifies Step 0.3 dependency)
            Image(uiImage: Lucide.heart)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundStyle(.pink)
            
            Text("Knot")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Relational Excellence on Autopilot")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Additional Lucide icons to confirm package works
            HStack(spacing: 16) {
                Image(uiImage: Lucide.gift)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                
                Image(uiImage: Lucide.calendar)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                
                Image(uiImage: Lucide.sparkles)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

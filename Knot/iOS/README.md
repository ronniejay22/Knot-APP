# Knot iOS App

**Relational Excellence on Autopilot**

## Requirements

- Xcode 15.0+
- iOS 17.0+
- Swift 6.0
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

## Setup

### Option 1: Generate Project with XcodeGen (Recommended)

1. Install XcodeGen if you haven't already:
   ```bash
   brew install xcodegen
   ```

2. Navigate to the iOS directory:
   ```bash
   cd iOS
   ```

3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

4. Open the generated project:
   ```bash
   open Knot.xcodeproj
   ```

### Option 2: Manual Xcode Project Creation

1. Open Xcode and create a new project
2. Select "App" under iOS
3. Configure:
   - Product Name: `Knot`
   - Interface: SwiftUI
   - Language: Swift
   - Storage: SwiftData
   - Minimum Deployment: iOS 17.0
4. Copy the source files from this directory into the project

## Project Structure

```
iOS/
├── Knot/
│   ├── App/              # App entry point and configuration
│   │   ├── KnotApp.swift
│   │   └── ContentView.swift
│   ├── Features/         # Feature modules
│   │   ├── Auth/
│   │   ├── Onboarding/
│   │   ├── Home/
│   │   ├── Recommendations/
│   │   └── HintCapture/
│   ├── Core/             # Shared utilities and constants
│   │   └── Constants.swift
│   ├── Services/         # API clients and data services
│   ├── Models/           # SwiftData models and DTOs
│   ├── Components/       # Reusable UI components
│   ├── Resources/        # Assets, colors, fonts
│   │   └── Assets.xcassets/
│   └── Info.plist
├── KnotTests/            # Unit tests
├── KnotUITests/          # UI tests
└── project.yml           # XcodeGen configuration
```

## Build Settings

The project is configured with:
- **Swift Version:** 6.0
- **Strict Concurrency:** Complete (enabled for thread safety)
- **Minimum iOS:** 17.0 (required for SwiftData)

## Running Tests

```bash
# Run unit tests
xcodebuild test -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 15'

# Run UI tests
xcodebuild test -scheme Knot -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KnotUITests
```

## Dependencies

Dependencies will be managed via Swift Package Manager (SPM). Add packages in Xcode:
- File > Add Package Dependencies...

Required packages (to be added in Step 0.3):
- Lucide Icons (Swift port)

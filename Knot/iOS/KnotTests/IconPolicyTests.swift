//
//  IconPolicyTests.swift
//  KnotTests
//
//  Enforces "MUI icons only": Knot draws every icon through `KnotIcon`. Lucide
//  and SF Symbols are banned — the one allowlisted glyph is Apple's own logo
//  on "Continue with Apple", which App Review expects to be Apple artwork.
//

import XCTest

final class IconPolicyTests: XCTestCase {

    /// `…/Knot/iOS`, located from this file so the test reads the source tree
    /// it was compiled from.
    private static let iosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let scannedFolders = ["Knot", "KnotTests", "KnotUITests"]

    /// Any of these on a line means a non-MUI icon came back. The bare
    /// `systemName:` label (not `Image(systemName:`) also catches a call split
    /// across lines and `UIImage(systemName:)` / `.init(systemName:)`.
    private static let forbiddenTokens = [
        "LucideIcons",
        "Lucide.",
        "systemName:",
        "systemImage:",
        ".symbolVariant(",
    ]

    /// The Apple logo line must carry this marker to be exempt.
    private static let appleLogoMarker = "// icon-policy: apple-logo-exception"

    func testSourceUsesNoLucideOrSFSymbols() throws {
        var violations: [String] = []
        var scannedFiles = 0

        for folder in Self.scannedFolders {
            let root = Self.iosRoot.appendingPathComponent(folder)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            else {
                XCTFail("Can't read \(root.path) — IconPolicyTests scans the source tree")
                continue
            }

            for case let url as URL in files where url.pathExtension == "swift" {
                guard url.lastPathComponent != "IconPolicyTests.swift" else { continue }
                scannedFiles += 1
                let source = try String(contentsOf: url, encoding: .utf8)
                let relativePath = String(url.path.dropFirst(Self.iosRoot.path.count + 1))

                for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                    if line.contains("\"apple.logo\""), line.contains(Self.appleLogoMarker) { continue }
                    for token in Self.forbiddenTokens where line.contains(token) {
                        violations.append("\(relativePath):\(index + 1) uses `\(token)`")
                    }
                }
            }
        }

        XCTAssertGreaterThan(scannedFiles, 100, "Expected to scan the whole app, found \(scannedFiles) files")
        XCTAssertTrue(
            violations.isEmpty,
            "Knot draws MUI icons only (KnotIcon). Replace these:\n" + violations.joined(separator: "\n")
        )
    }

    /// The package is gone from the project, so `import LucideIcons` can't
    /// compile — this keeps it from being re-added, whether through
    /// `project.yml` or straight into the Xcode project from Xcode's UI.
    func testProjectDoesNotDeclareLucide() throws {
        let projectFiles = [
            "project.yml",
            "Knot.xcodeproj/project.pbxproj",
            "Knot.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        ]
        for path in projectFiles {
            let contents = try String(contentsOf: Self.iosRoot.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(contents.localizedCaseInsensitiveContains("lucide"), "\(path) must not declare Lucide")
        }
    }
}

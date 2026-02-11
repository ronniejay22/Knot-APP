//
//  KnotTests.swift
//  KnotTests
//
//  Created on February 3, 2026.
//

import XCTest
@testable import Knot

final class KnotTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testInterestCategoriesCount() throws {
        // Verify we have exactly 40 interest categories
        XCTAssertEqual(Constants.interestCategories.count, 40, "Should have exactly 40 interest categories")
    }
    
    func testVibeOptionsCount() throws {
        // Verify we have exactly 8 vibe options
        XCTAssertEqual(Constants.vibeOptions.count, 8, "Should have exactly 8 vibe options")
    }
    
    func testLoveLanguagesCount() throws {
        // Verify we have exactly 5 love languages
        XCTAssertEqual(Constants.loveLanguages.count, 5, "Should have exactly 5 love languages")
    }
    
    func testMaxHintLength() throws {
        // Verify hint length constant
        XCTAssertEqual(Constants.Validation.maxHintLength, 500, "Max hint length should be 500")
    }
}

import XCTest
@testable import Engine

final class LayoutCheckerTests: XCTestCase {
    let checker = LayoutChecker()

    func testGhbdtnIncorrect() {
        XCTAssertEqual(checker.check("ghbdtn"), .incorrect)
    }

    func testRuddochIncorrect() {
        XCTAssertEqual(checker.check("руддщ"), .incorrect)
    }

    func testRealRussianUnknown() {
        XCTAssertEqual(checker.check("привет"), .unknown)
    }

    func testRealEnglishUnknown() {
        XCTAssertEqual(checker.check("hello"), .unknown)
    }

    func testShortUnknown() {
        XCTAssertEqual(checker.check("a"), .unknown)
    }

    func testNeverRule() {
        let rules = [UserRule(pattern: "ghbdtn", shouldSwitch: false)]
        let c = LayoutChecker(userRules: rules)
        XCTAssertEqual(c.check("ghbdtn"), .exception)
    }
}

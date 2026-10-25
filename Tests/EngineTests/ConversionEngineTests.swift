import XCTest
@testable import Engine

final class ConversionEngineTests: XCTestCase {
    func testHelloUSToRU() {
        XCTAssertEqual(ConversionEngine.convert("ghbdtn", direction: .usToRussian), "привет")
    }

    func testHelloRUToUS() {
        XCTAssertEqual(ConversionEngine.convert("руддщ", direction: .russianToUs), "hello")
    }

    func testAutoLatin() {
        XCTAssertEqual(ConversionEngine.convert("ghbdtn", direction: .auto), "привет")
    }

    func testAutoCyrillic() {
        XCTAssertEqual(ConversionEngine.convert("руддщ", direction: .auto), "hello")
    }

    func testDigitsPreserved() {
        XCTAssertEqual(ConversionEngine.convert("ntcn123", direction: .usToRussian), "тест123")
        XCTAssertEqual(ConversionEngine.convert("test", direction: .usToRussian), "еуые")
    }
}

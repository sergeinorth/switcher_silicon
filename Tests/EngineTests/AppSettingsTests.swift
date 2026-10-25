import XCTest
@testable import Engine

final class AppSettingsTests: XCTestCase {
    func testDefaults() {
        XCTAssertTrue(AppSettings.default.isAutocorrectionActive)
        XCTAssertTrue(AppSettings.default.isSoundOn)
        XCTAssertTrue(AppSettings.default.useOptionTrigger)
    }

    func testRoundtrip() throws {
        var settings = AppSettings.default
        settings.excludedApps = ["com.apple.Terminal"]
        settings.isSoundOn = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}

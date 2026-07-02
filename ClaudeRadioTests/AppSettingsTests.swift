import XCTest
@testable import ClaudeRadio

final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: AppSettings!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: #file)
        defaults.removePersistentDomain(forName: #file)
        settings = AppSettings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: #file)
        super.tearDown()
    }

    func testDefaultVolumeIs70() {
        XCTAssertEqual(settings.volume, 70)
    }

    func testVolumeClampsToValidRange() {
        settings.volume = 150
        XCTAssertEqual(settings.volume, 100)
        settings.volume = -10
        XCTAssertEqual(settings.volume, 0)
    }

    func testLaunchAtLoginPersists() {
        XCTAssertFalse(settings.launchAtLogin)
        settings.launchAtLogin = true
        XCTAssertTrue(settings.launchAtLogin)
    }
}

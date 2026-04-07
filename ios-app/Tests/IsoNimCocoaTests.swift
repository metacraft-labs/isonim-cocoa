import XCTest
@testable import IsoNimCocoa_iOS

class IsoNimCocoaTests: XCTestCase {

    var app: AppDelegate!

    override func setUp() {
        super.setUp()
        app = AppDelegate()
        _ = app.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - App Launch

    func testAppLaunchSetsRootViewController() {
        XCTAssertNotNil(app.window, "Window should be created")
        XCTAssertNotNil(app.window?.rootViewController, "Root view controller should be set")
        XCTAssertTrue(app.window?.rootViewController is ViewController,
                      "Root view controller should be a ViewController")
    }

    func testWindowIsVisible() {
        XCTAssertTrue(app.window?.isKeyWindow ?? false,
                      "Window should be key and visible after launch")
    }

    // MARK: - Tap Gesture

    func testButtonTapChangesFlag() {
        var tapped = false
        let button = UIButton(type: .system)
        button.addAction(UIAction { _ in tapped = true }, for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(tapped, "Tap action should set the flag to true")
    }

    // MARK: - Safe Area

    func testSafeAreaInsetsNonZero() {
        guard let vc = app.window?.rootViewController else {
            XCTFail("No root view controller")
            return
        }
        // Force layout so safe area insets are computed
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()

        let insets = vc.view.safeAreaInsets
        // On iPhone 17 Pro simulator (with notch/dynamic island), top inset > 0
        XCTAssertGreaterThan(insets.top, 0,
                             "Top safe area inset should be non-zero on a notched device")
    }

    // MARK: - Orientation

    func testViewControllerSupportsMultipleOrientations() {
        guard let vc = app.window?.rootViewController as? ViewController else {
            XCTFail("Root view controller should be a ViewController")
            return
        }
        let mask = vc.supportedInterfaceOrientations
        XCTAssertTrue(mask.contains(.portrait), "Should support portrait")
        XCTAssertTrue(mask.contains(.landscapeLeft), "Should support landscape left")
        XCTAssertTrue(mask.contains(.landscapeRight), "Should support landscape right")
    }

    // MARK: - UI Content

    func testTitleLabelIsPresent() {
        guard let vc = app.window?.rootViewController as? ViewController else {
            XCTFail("Root view controller should be a ViewController")
            return
        }
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        XCTAssertEqual(vc.titleLabel.text, "IsoNim Cocoa")
    }

    func testVersionLabelIsPresent() {
        guard let vc = app.window?.rootViewController as? ViewController else {
            XCTFail("Root view controller should be a ViewController")
            return
        }
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        XCTAssertNotNil(vc.versionLabel.text, "Version label should have text")
        XCTAssertTrue(vc.versionLabel.text?.hasPrefix("v") ?? false,
                      "Version label should start with 'v'")
    }
}

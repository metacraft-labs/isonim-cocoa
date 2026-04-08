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
        XCTAssertTrue(app.window?.rootViewController is UINavigationController,
                      "Root view controller should be a UINavigationController")
        let nav = app.window?.rootViewController as? UINavigationController
        XCTAssertTrue(nav?.topViewController is TaskManagerViewController,
                      "Top view controller should be a TaskManagerViewController")
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
        let nav = app.window?.rootViewController as? UINavigationController
        guard let vc = nav?.topViewController as? TaskManagerViewController else {
            XCTFail("Top view controller should be a TaskManagerViewController")
            return
        }
        let mask = vc.supportedInterfaceOrientations
        XCTAssertTrue(mask.contains(.portrait), "Should support portrait")
        XCTAssertTrue(mask.contains(.landscapeLeft), "Should support landscape left")
        XCTAssertTrue(mask.contains(.landscapeRight), "Should support landscape right")
    }

    // MARK: - UI Content

    func testTaskManagerHasTitle() {
        let nav = app.window?.rootViewController as? UINavigationController
        guard let vc = nav?.topViewController as? TaskManagerViewController else {
            XCTFail("Top view controller should be a TaskManagerViewController")
            return
        }
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        XCTAssertEqual(vc.title, "Tasks", "Navigation title should be 'Tasks'")
    }

    func testTaskManagerHasNavigationBar() {
        let nav = app.window?.rootViewController as? UINavigationController
        XCTAssertNotNil(nav, "Should have navigation controller")
        XCTAssertFalse(nav?.isNavigationBarHidden ?? true,
                       "Navigation bar should be visible")
    }
}

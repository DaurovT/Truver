import XCTest

class TruverUITestCase: XCTestCase {
    var app: XCUIApplication!
    var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            for title in ["Разрешить", "Allow", "OK", "ОК"] where alert.buttons[title].exists {
                alert.buttons[title].tap(); return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        shot("zz-final")
        app?.terminate()
    }

    func launch(_ args: [String] = [], skipOnboarding: Bool = true) {
        app.launchArguments = ["-uiTest", "-resetSettings", "-muteAudio"] + (skipOnboarding ? ["-skipOnboarding"] : []) + args
        app.launch()
        sleep(2)
    }

    /// Screenshot + accessibility tree dump.
    /// Wait until no SpringBoard notification banner is on screen (banners cover the header buttons).
    func waitForNoBanner() {
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<20 {
            let banner = sb.otherElements.matching(NSPredicate(format: "identifier == 'NotificationShortLookView' OR identifier CONTAINS 'BannerView' OR identifier CONTAINS 'NotificationShortLook'")).firstMatch
            if !banner.exists { return }
            sleep(1)
        }
    }

    func safeTap(_ e: XCUIElement) {
        ensureForeground()
        if e.exists && e.frame.minY < 200 { waitForNoBanner() }
        if e.isHittable { e.tap() } else { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        ensureForeground()
    }

    func ensureForeground() {
        if app.state != .runningForeground && app.state != .notRunning {
            XCTFail("Truver left foreground (state \(app.state.rawValue)) — reactivating")
            app.activate(); sleep(1)
        }
    }

    func shot(_ name: String, tree: Bool = false) {
        ensureForeground()
        step += 1
        let label = String(format: "%@-%02d-%@", String(describing: type(of: self)) + "." + (testRun?.test.name.components(separatedBy: " ").last?.replacingOccurrences(of: "]", with: "") ?? ""), step, name)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = label
        a.lifetime = .keepAlways
        add(a)
        if tree {
            let t = XCTAttachment(string: app.debugDescription)
            t.name = label + "-tree"
            t.lifetime = .keepAlways
            add(t)
        }
    }

    func tap(_ label: String, _ type: XCUIElement.ElementType = .any, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line) {
        ensureForeground()
        let e = element(label, type)
        if e.waitForExistence(timeout: timeout) {
            safeTap(e)
        } else {
            XCTFail("Not found: \(label)", file: file, line: line)
        }
        usleep(700_000)
    }

    func element(_ label: String, _ type: XCUIElement.ElementType = .any) -> XCUIElement {
        let q = app.descendants(matching: type).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label))
        return q.firstMatch
    }

    func elementBegins(_ prefix: String, _ type: XCUIElement.ElementType = .any) -> XCUIElement {
        app.descendants(matching: type).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    @discardableResult
    func tapIfExists(_ label: String, _ type: XCUIElement.ElementType = .any) -> Bool {
        let e = element(label, type)
        if e.waitForExistence(timeout: 2) { safeTap(e); usleep(700_000); return true }
        return false
    }

    func tapBegins(_ prefix: String, _ type: XCUIElement.ElementType = .any, file: StaticString = #filePath, line: UInt = #line) {
        let e = elementBegins(prefix, type)
        if e.waitForExistence(timeout: 3) { safeTap(e) } else { XCTFail("Not found prefix: \(prefix)", file: file, line: line) }
        usleep(700_000)
    }

    func tab(_ name: String) { tap(name, .button) }

    /// Tap outside a sheet (dim area near top).
    func dismissByDim() {
        ensureForeground()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        usleep(700_000)
    }

    func swipeDownSheet() {
        let s = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        s.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        usleep(800_000)
    }
}

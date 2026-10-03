import XCTest
@testable import herdrm

final class MouseGestureRouterTests: XCTestCase {
    private func captured(shift: Bool = false, clickCount: Int = 1, reporting: Bool = true)
        -> (MouseGestureRouter, [MouseGestureRouter.Action])
    {
        var router = MouseGestureRouter()
        let actions = router.press(
            at: .zero, clickCount: clickCount, shift: shift, captured: true, reportingEnabled: reporting
        )
        return (router, actions)
    }

    func testCapturedClickReachesTheAppOnRelease() {
        var (router, pressActions) = captured()
        XCTAssertEqual(pressActions, [])
        XCTAssertEqual(router.release(), [.press(.app), .release(.app)])
    }

    func testCapturedDragBecomesALocalSelectionFromThePressPoint() {
        var (router, _) = captured()
        XCTAssertEqual(router.drag(to: CGPoint(x: 1, y: 1)), [])
        XCTAssertEqual(
            router.drag(to: CGPoint(x: MouseGestureRouter.dragThreshold + 1, y: 0)),
            [.press(.local), .drag(.local)]
        )
        XCTAssertEqual(router.drag(to: CGPoint(x: 40, y: 0)), [.drag(.local)])
        XCTAssertEqual(router.release(), [.release(.local)])
    }

    func testShiftPressIsLocalImmediately() {
        var (router, pressActions) = captured(shift: true)
        XCTAssertEqual(pressActions, [.press(.local)])
        XCTAssertEqual(router.drag(to: CGPoint(x: 1, y: 0)), [.drag(.local)])
        XCTAssertEqual(router.release(), [.release(.local)])
    }

    func testDoubleClickIsLocalImmediately() {
        var (router, pressActions) = captured(clickCount: 2)
        XCTAssertEqual(pressActions, [.press(.local)])
        XCTAssertEqual(router.release(), [.release(.local)])
    }

    func testMouseReportingOffKeepsEverythingLocal() {
        var (router, pressActions) = captured(reporting: false)
        XCTAssertEqual(pressActions, [.press(.local)])
        XCTAssertEqual(router.release(), [.release(.local)])
    }

    func testUncapturedPressIsLocalImmediately() {
        var router = MouseGestureRouter()
        XCTAssertEqual(
            router.press(at: .zero, clickCount: 1, shift: false, captured: false, reportingEnabled: true),
            [.press(.local)]
        )
        XCTAssertEqual(router.release(), [.release(.local)])
    }

    func testReleaseAndDragWithoutAPressAreDropped() {
        var router = MouseGestureRouter()
        XCTAssertEqual(router.drag(to: CGPoint(x: 50, y: 50)), [])
        XCTAssertEqual(router.release(), [])
    }

    func testGestureResetsAfterRelease() {
        var (router, _) = captured()
        _ = router.release()
        XCTAssertEqual(
            router.press(at: .zero, clickCount: 1, shift: false, captured: true, reportingEnabled: true),
            []
        )
        XCTAssertEqual(router.release(), [.press(.app), .release(.app)])
    }
}

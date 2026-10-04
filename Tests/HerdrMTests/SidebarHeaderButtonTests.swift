import AppKit
import SwiftUI
import XCTest
@testable import herdrm

/// The small button at the right end of a sidebar section header, on its own.
@MainActor
final class SidebarHeaderButtonTests: XCTestCase {
    private var presses = 0
    private var window: NSWindow!
    private var root: NSHostingView<SidebarHeaderButton>!

    override func setUp() async throws {
        presses = 0
        root = NSHostingView(rootView: SidebarHeaderButton(systemName: "square.and.pencil", title: "New Agent") { [weak self] in
            self?.presses += 1
        })
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "SidebarHeaderButton \(UUID().uuidString)" // AccessibilityProbe finds the window by title
        window.contentView = root
        window.orderFrontRegardless()
        settle()
    }

    override func tearDown() async throws {
        window.close()
    }

    func testAClickRunsTheActionOnce() throws {
        let center = root.convert(NSPoint(x: root.bounds.midX, y: root.bounds.midY), to: nil)
        for (type, number) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: center, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: number, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)))
            settle()
        }
        XCTAssertEqual(presses, 1)
    }

    func testVoiceOverReadsItsTitleAndCanPressIt() throws {
        let buttons = AccessibilityProbe.elements(in: window).filter { $0.role == "AXButton" && $0.name == String(localized: "New Agent") }
        XCTAssertEqual(buttons.count, 1, "one button, named by its title rather than its icon")

        AccessibilityProbe.press(try XCTUnwrap(buttons.first))
        settle()
        XCTAssertEqual(presses, 1)
    }

    func testIsTwentyPointsSquare() {
        XCTAssertEqual(root.fittingSize, NSSize(width: 20, height: 20))
    }

    private func settle(_ seconds: TimeInterval = 0.2) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

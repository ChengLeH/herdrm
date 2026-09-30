import CoreGraphics

/// Decides who owns a left-button gesture while a TUI has captured the mouse:
/// a click belongs to the app, a drag belongs to the terminal's selection.
///
/// A captured press is held back until the gesture reveals itself. A release
/// with no movement replays press and release to the app together; movement
/// past `dragThreshold` replays the press as a local one at the original point
/// so the selection anchors where the button went down. Shift, repeated
/// clicks, an uncaptured surface and Mouse Reporting off all go local at once.
struct MouseGestureRouter {
    enum Route: Equatable { case local, app }
    enum Action: Equatable {
        case press(Route)
        case drag(Route)
        case release(Route)
    }

    /// Points of travel that turn a held-back press into a selection.
    static let dragThreshold: CGFloat = 4

    private enum State {
        case idle
        case pending(origin: CGPoint)
        case active(Route)
    }

    private var state: State = .idle

    mutating func press(
        at point: CGPoint, clickCount: Int, shift: Bool, captured: Bool, reportingEnabled: Bool
    ) -> [Action] {
        let local = !captured || !reportingEnabled || shift || clickCount > 1
        if local {
            state = .active(.local)
            return [.press(.local)]
        }
        state = .pending(origin: point)
        return []
    }

    mutating func drag(to point: CGPoint) -> [Action] {
        switch state {
        case .idle:
            return []
        case .active(let route):
            return [.drag(route)]
        case .pending(let origin):
            guard hypot(point.x - origin.x, point.y - origin.y) >= Self.dragThreshold else { return [] }
            state = .active(.local)
            return [.press(.local), .drag(.local)]
        }
    }

    mutating func release() -> [Action] {
        defer { state = .idle }
        switch state {
        case .idle:
            return []
        case .active(let route):
            return [.release(route)]
        case .pending:
            return [.press(.app), .release(.app)]
        }
    }
}

import XCTest
@testable import HerdrKit

final class PluginActionsTests: XCTestCase {
    /// Shapes copied from a live `plugin.action.list` (herdr 0.9).
    func testDecodesTheWireShape() throws {
        let json = """
        {"actions": [
          {"plugin_id": "herdr-agent-quota", "action_id": "refresh", "title": "Refresh agent quota",
           "command": ["sh", "-c", "true"], "platforms": ["macos", "linux"]},
          {"plugin_id": "wazum.grazr", "action_id": "swap", "title": "grazr: swap to the next account now",
           "description": "Move to the first account in ACCOUNTS with headroom",
           "contexts": ["global", "workspace"], "command": ["python3", "grazr.py", "swap"]}
        ]}
        """
        struct Envelope: Decodable { let actions: [PluginAction] }
        let actions = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).actions

        XCTAssertEqual(actions.map(\.id), ["herdr-agent-quota.refresh", "wazum.grazr.swap"])
        XCTAssertEqual(actions[0].contexts, [])
        XCTAssertEqual(actions[1].contexts, ["global", "workspace"])
        XCTAssertEqual(actions[1].description, "Move to the first account in ACCOUNTS with headroom")
    }

    func testThePluginPrefixLeavesTheTitleInsideItsSubmenu() {
        let swap = PluginAction(pluginID: "wazum.grazr", actionID: "swap", title: "grazr: swap to the next account now")
        XCTAssertEqual(swap.pluginName, "grazr")
        XCTAssertEqual(swap.menuTitle, "Swap to the next account now")

        let other = PluginAction(pluginID: "herdr.auto-title", actionID: "restart", title: "Auto Title: restart")
        XCTAssertEqual(other.pluginName, "auto-title")
        XCTAssertEqual(other.menuTitle, "Auto Title: restart")
    }

    func testGroupsPerPluginInNameOrderAndDropsSelectionOnlyActions() {
        let groups = PluginActionGroup.menu([
            PluginAction(pluginID: "wazum.grazr", actionID: "tag", title: "grazr: tag every pane"),
            PluginAction(pluginID: "furkankly.zoetrope", actionID: "open", title: "zoetrope: session graph"),
            PluginAction(pluginID: "wazum.grazr", actionID: "swap", title: "grazr: swap to the next account now"),
            PluginAction(pluginID: "x.lookup", actionID: "define", title: "Define", contexts: ["selection"]),
        ])

        XCTAssertEqual(groups.map(\.name), ["grazr", "zoetrope"])
        XCTAssertEqual(groups[0].actions.map(\.actionID), ["swap", "tag"])
    }

    func testAnActionThatAlsoRunsOnAPaneStaysInTheMenu() {
        let action = PluginAction(pluginID: "a.b", actionID: "c", title: "C", contexts: ["selection", "pane"])
        XCTAssertTrue(action.runsFromAgentMenu)
    }

    func testSummaryIsTheLastLineOfWhatTheCommandSaid() {
        let rotated = PluginCommandLog(
            logID: "plugin-log-1", status: "succeeded", exitCode: 0,
            stdout: "Rotated a -> b\n", stderr: ""
        )
        XCTAssertTrue(rotated.isFinished)
        XCTAssertEqual(rotated.summary, "Rotated a -> b")

        let refused = PluginCommandLog(
            logID: "plugin-log-2", status: "failed", exitCode: 1,
            stdout: "", stderr: "Traceback\n  Nothing to swap to, earliest reset Thu 18:30\n"
        )
        XCTAssertFalse(refused.succeeded)
        XCTAssertEqual(refused.summary, "Nothing to swap to, earliest reset Thu 18:30")

        let running = PluginCommandLog(logID: "plugin-log-3", status: "running")
        XCTAssertFalse(running.isFinished)
        XCTAssertNil(running.summary)
    }
}

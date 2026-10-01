import XCTest
@testable import HerdrKit

final class GrazrAccountsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_876_000) // 2026-10-01 17:33 UTC

    private func window(_ group: String, _ remaining: Int, scope: String? = nil, resetsIn hours: Double) -> GrazrWindow {
        GrazrWindow(
            kind: group, scope: scope, group: group, remaining: remaining,
            resetsAt: now.addingTimeInterval(hours * 3600)
        )
    }

    func testOrdersActiveFirstThenTheConfiguredOrder() {
        let report = GrazrReport(
            active: "c",
            accounts: [
                GrazrAccount(id: "a", name: "a@x"),
                GrazrAccount(id: "z", name: "unlisted@x"),
                GrazrAccount(id: "b", name: "b@x"),
                GrazrAccount(id: "c", name: "c@x"),
            ],
            order: ["b@x", "a@x", "c@x"]
        )

        XCTAssertEqual(report.sortedAccounts.map(\.id), ["c", "b", "a", "z"])
        XCTAssertFalse(report.isListed(report.accounts[1]))
    }

    func testAWindowPastItsResetIsFullAgain() {
        let spent = window("session", 0, resetsIn: -1)
        XCTAssertFalse(spent.isOpen(now: now))
        XCTAssertEqual(spent.left(now: now), 100)

        let open = window("weekly", 14, resetsIn: 30)
        XCTAssertEqual(open.left(now: now), 14)
    }

    func testLeastLeftIgnoresWindowsThatHaveReset() {
        let account = GrazrAccount(id: "a", name: "a", windows: [
            window("session", 0, resetsIn: -2),
            window("weekly", 14, resetsIn: 30),
            window("weekly", 42, scope: "Fable", resetsIn: 30),
        ])
        XCTAssertEqual(account.leastLeft(now: now), 14)
        XCTAssertEqual(account.sortedWindows.map(\.label), ["5h", "Week", "Fable week"])
    }

    func testThresholdsFallBackToGrazrsDefaults() {
        XCTAssertEqual(GrazrReport().sessionThreshold, 15)
        XCTAssertEqual(GrazrReport().weeklyThreshold, 20)
        let report = GrazrReport(settings: ["REMAINING_WEEKLY": "10", "DRY_RUN": "1", "ENABLED": "0"])
        XCTAssertEqual(report.weeklyThreshold, 10)
        XCTAssertTrue(report.dryRun)
        XCTAssertFalse(report.enabled)
    }

    func testALapsedBlockNoLongerApplies() {
        let account = GrazrAccount(id: "a", name: "a")
        let lapsed = GrazrReport(blocked: ["a": GrazrBlock(reason: "rate_limit", until: now.timeIntervalSince1970 - 1)])
        XCTAssertNil(lapsed.block(for: account, now: now))
        let refused = GrazrReport(blocked: ["a": GrazrBlock(reason: "billing_error")])
        XCTAssertEqual(refused.block(for: account, now: now)?.reason, "billing_error")
    }

    #if os(macOS)
    /// The reader script itself, against grazr's real file layout in a
    /// throwaway home: what it reports, and that nothing else leaves.
    func testTheReaderReportsGrazrsFilesAndNothingSecret() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("grazr-reader-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let state = home.appendingPathComponent(".local/state/herdr/plugins/wazum.grazr")
        let accounts = state.appendingPathComponent("accounts")
        let config = home.appendingPathComponent(".config/herdr/plugins/config/wazum.grazr")
        try FileManager.default.createDirectory(at: accounts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)

        func write(_ text: String, to url: URL) throws {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("""
        {"name": "work@x", "email": "work@x", "organization": "Acme",
         "accessToken": "sk-SECRET-1",
         "oauthAccount": {"accountUuid": "uuid-work", "emailAddress": "work@x", "refreshToken": "SECRET-2"},
         "snapshot": [
           {"kind": "session", "scope": null, "group": "session", "remaining": 0, "resets_at": "2026-10-01T21:50:00+00:00"},
           {"kind": "weekly_scoped", "scope": "Fable", "group": "weekly", "remaining": 84, "resets_at": "2026-10-04T18:00:00.513830+00:00"}
         ]}
        """, to: accounts.appendingPathComponent("uuid-work.json"))
        try write(#"{"name": "home@x", "oauthAccount": {"accountUuid": "uuid-home"}, "snapshot": null}"#,
                  to: accounts.appendingPathComponent("uuid-home.json"))
        try write("not json", to: accounts.appendingPathComponent(".grazr-tmp"))
        try write("""
        # comment
        REMAINING_WEEKLY=10   # weekly
        ACCOUNTS="work@x home@x"
        """, to: config.appendingPathComponent("config.env"))
        try write(#"{"uuid-home": {"reason": "billing_error", "at": 1, "until": null, "reading": [{"secret": "SECRET-3"}]}}"#,
                  to: state.appendingPathComponent("blocked.json"))
        try write(#"{"oauthAccount": {"accountUuid": "uuid-work"}, "primaryApiKey": "SECRET-4"}"#,
                  to: home.appendingPathComponent(".claude.json"))

        let environment = "HOME='\(home.path)' XDG_STATE_HOME= XDG_CONFIG_HOME= CLAUDE_CONFIG_DIR= "
        let output = try await DeviceFileService(device: .local).run(environment + Grazr.readerCommand)
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("SECRET"))

        let report = try JSONDecoder().decode(GrazrReport.self, from: output)
        XCTAssertEqual(report.active, "uuid-work")
        XCTAssertEqual(report.order, ["work@x", "home@x"])
        XCTAssertEqual(report.weeklyThreshold, 10)
        XCTAssertEqual(report.blocked["uuid-home"]?.reason, "billing_error")
        XCTAssertEqual(report.sortedAccounts.map(\.id), ["uuid-work", "uuid-home"])
        let work = report.sortedAccounts[0]
        XCTAssertEqual(work.organization, "Acme")
        XCTAssertEqual(work.windows.map(\.label), ["5h", "Fable week"])
        XCTAssertEqual(work.windows[0].resetsAt, ISO8601DateFormatter().date(from: "2026-10-01T21:50:00Z"))
        XCTAssertEqual(report.sortedAccounts[1].windows, [])
    }
    #endif
}

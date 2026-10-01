import Foundation

/// grazr (github.com/wazum/herdr-grazr) rotates Claude Code between several
/// subscriptions. It keeps what each account had left in plain JSON files on
/// the device; this reads them for the sidebar's Accounts window.
public enum Grazr {
    public static let pluginID = "wazum.grazr"
    public static let swapActionID = "swap"

    /// Prints a `GrazrReport` as JSON. Runs on the device with the python3
    /// grazr itself needs. Only names, ids and usage readings leave the device:
    /// the parked credentials live elsewhere, and `.claude.json` contributes
    /// the active account's id and nothing else.
    public static let readerCommand = #"""
    python3 - <<'GRAZR_EOF'
    import glob, json, os
    from datetime import datetime

    home = os.path.expanduser("~")
    state = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(home, ".local/state"), "herdr/plugins/wazum.grazr")
    config = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config"), "herdr/plugins/config/wazum.grazr/config.env")

    def load(path, default=None):
        try:
            with open(path) as handle:
                return json.load(handle)
        except Exception:
            return default

    def epoch(text):
        try:
            return datetime.fromisoformat(text).timestamp()
        except Exception:
            return None

    report = {"installed": os.path.isdir(state), "accounts": [], "order": [], "settings": {}, "blocked": {}}
    for path in sorted(glob.glob(os.path.join(state, "accounts", "*.json"))):
        entry = load(path)
        if not isinstance(entry, dict):
            continue
        oauth = entry.get("oauthAccount") or {}
        windows = []
        for window in entry.get("snapshot") or []:
            if isinstance(window, dict) and isinstance(window.get("remaining"), (int, float)):
                windows.append({
                    "kind": str(window.get("kind") or ""),
                    "scope": window.get("scope"),
                    "group": str(window.get("group") or ""),
                    "remaining": int(window["remaining"]),
                    "resets_at": epoch(window.get("resets_at") or ""),
                })
        report["accounts"].append({
            "id": oauth.get("accountUuid") or os.path.basename(path)[:-5],
            "name": entry.get("name") or entry.get("email") or "",
            "organization": entry.get("organization"),
            "windows": windows,
            "updated": os.path.getmtime(path),
        })

    claude = load(os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or home, ".claude.json"), {})
    report["active"] = ((claude or {}).get("oauthAccount") or {}).get("accountUuid")

    try:
        with open(config) as handle:
            for line in handle:
                line = line.split("#", 1)[0].strip()
                if "=" in line:
                    key, value = line.split("=", 1)
                    report["settings"][key.strip()] = value.strip().strip("\"'")
    except Exception:
        pass
    report["order"] = report["settings"].get("ACCOUNTS", "").split()

    for identifier, entry in (load(os.path.join(state, "blocked.json"), {}) or {}).items():
        if isinstance(entry, dict):
            report["blocked"][identifier] = {"reason": str(entry.get("reason") or ""), "until": entry.get("until")}

    print(json.dumps(report))
    GRAZR_EOF
    """#
}

public struct GrazrReport: Decodable, Sendable, Equatable {
    public let installed: Bool
    public let active: String?
    public let accounts: [GrazrAccount]
    /// `ACCOUNTS` in config.env: the order grazr tries them in.
    public let order: [String]
    public let settings: [String: String]
    public let blocked: [String: GrazrBlock]

    public init(
        installed: Bool = true,
        active: String? = nil,
        accounts: [GrazrAccount] = [],
        order: [String] = [],
        settings: [String: String] = [:],
        blocked: [String: GrazrBlock] = [:]
    ) {
        self.installed = installed
        self.active = active
        self.accounts = accounts
        self.order = order
        self.settings = settings
        self.blocked = blocked
    }

    /// grazr's own defaults when config.env does not say.
    public var sessionThreshold: Int { settings["REMAINING_SESSION"].flatMap(Int.init) ?? 15 }
    public var weeklyThreshold: Int { settings["REMAINING_WEEKLY"].flatMap(Int.init) ?? 20 }
    public var enabled: Bool { settings["ENABLED"] != "0" }
    public var dryRun: Bool { settings["DRY_RUN"] == "1" }

    /// The active account first, then `ACCOUNTS` order, then any enrolled
    /// account the config leaves out.
    public var sortedAccounts: [GrazrAccount] {
        accounts.sorted { lhs, rhs in
            func rank(_ account: GrazrAccount) -> (Int, Int, String) {
                let listed = order.firstIndex(of: account.name) ?? order.count
                return (account.id == active ? 0 : 1, listed, account.name)
            }
            return rank(lhs) < rank(rhs)
        }
    }

    public func isListed(_ account: GrazrAccount) -> Bool { order.contains(account.name) }

    /// A block with a lapsed `until` no longer applies.
    public func block(for account: GrazrAccount, now: Date) -> GrazrBlock? {
        guard let block = blocked[account.id] else { return nil }
        if let until = block.until, until <= now.timeIntervalSince1970 { return nil }
        return block
    }

    public func threshold(for window: GrazrWindow) -> Int? {
        switch window.group {
        case "session": return sessionThreshold
        case "weekly": return weeklyThreshold
        default: return nil
        }
    }
}

public struct GrazrAccount: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let organization: String?
    public let windows: [GrazrWindow]
    /// When grazr last wrote this account's reading (unix seconds).
    public let updated: Double?

    public init(id: String, name: String, organization: String? = nil, windows: [GrazrWindow] = [], updated: Double? = nil) {
        self.id = id
        self.name = name
        self.organization = organization
        self.windows = windows
        self.updated = updated
    }

    /// Session first, then the all-models week, then per-model weeks.
    public var sortedWindows: [GrazrWindow] {
        windows.sorted { lhs, rhs in
            func rank(_ window: GrazrWindow) -> Int {
                switch (window.group, window.scope) {
                case ("session", _): return 0
                case ("weekly", nil): return 1
                default: return 2
                }
            }
            return (rank(lhs), lhs.scope ?? "") < (rank(rhs), rhs.scope ?? "")
        }
    }

    /// The tightest window still open: how close the account is to the wall.
    public func leastLeft(now: Date) -> Int? {
        windows.filter { $0.isOpen(now: now) }.map(\.remaining).min()
    }
}

public struct GrazrWindow: Decodable, Sendable, Equatable {
    public let kind: String
    /// A model name for a per-model weekly limit ("Fable"), nil otherwise.
    public let scope: String?
    public let group: String
    /// Percent left, as Claude reported it.
    public let remaining: Int
    public let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case kind, scope, group, remaining
        case resetsAt = "resets_at"
    }

    public init(kind: String, scope: String? = nil, group: String, remaining: Int, resetsAt: Date?) {
        self.kind = kind
        self.scope = scope
        self.group = group
        self.remaining = remaining
        self.resetsAt = resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        group = try container.decode(String.self, forKey: .group)
        remaining = try container.decode(Int.self, forKey: .remaining)
        resetsAt = try container.decodeIfPresent(Double.self, forKey: .resetsAt)
            .map(Date.init(timeIntervalSince1970:))
    }

    /// A window past its reset has refilled, whatever the last reading said.
    public func isOpen(now: Date) -> Bool {
        resetsAt.map { $0 > now } ?? true
    }

    /// What is left right now: the reading inside the window, all of it after.
    public func left(now: Date) -> Int {
        isOpen(now: now) ? remaining : 100
    }

    public var label: String {
        switch (group, scope) {
        case ("session", _): return "5h"
        case ("weekly", nil): return "Week"
        case (_, let scope?): return "\(scope) week"
        default: return group
        }
    }
}

public struct GrazrBlock: Decodable, Sendable, Equatable {
    public let reason: String
    public let until: Double?

    public init(reason: String, until: Double? = nil) {
        self.reason = reason
        self.until = until
    }
}

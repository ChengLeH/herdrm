import Foundation

/// A herdr plugin action (`plugin.action.list`): grazr's account swap,
/// agent-quota's refresh, zoetrope's graph, …
public struct PluginAction: Decodable, Sendable, Equatable, Identifiable {
    public let pluginID: String
    public let actionID: String
    public let title: String
    public let description: String?
    /// herdr's `global` / `workspace` / `tab` / `pane` / `selection`. Missing
    /// means the action runs anywhere.
    public let contexts: [String]

    public var id: String { "\(pluginID).\(actionID)" }

    enum CodingKeys: String, CodingKey {
        case pluginID = "plugin_id"
        case actionID = "action_id"
        case title
        case description
        case contexts
    }

    public init(pluginID: String, actionID: String, title: String, description: String? = nil, contexts: [String] = []) {
        self.pluginID = pluginID
        self.actionID = actionID
        self.title = title
        self.description = description
        self.contexts = contexts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pluginID = try container.decode(String.self, forKey: .pluginID)
        actionID = try container.decode(String.self, forKey: .actionID)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        contexts = try container.decodeIfPresent([String].self, forKey: .contexts) ?? []
    }

    /// A selection-only action needs selected text, which a sidebar row has not.
    public var runsFromAgentMenu: Bool {
        contexts.isEmpty || contexts.contains { $0 != "selection" }
    }

    /// `wazum.grazr` → `grazr`, `herdr-agent-quota` stays as is.
    public var pluginName: String {
        pluginID.split(separator: ".").last.map(String.init) ?? pluginID
    }

    /// The title inside its plugin's submenu: "grazr: swap to the next account
    /// now" reads "Swap to the next account now" under "grazr".
    public var menuTitle: String {
        let prefix = pluginName + ":"
        guard title.lowercased().hasPrefix(prefix.lowercased()) else { return title }
        let rest = title.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let first = rest.first else { return title }
        return first.uppercased() + rest.dropFirst()
    }
}

/// One submenu of the agent row's context menu.
public struct PluginActionGroup: Sendable, Equatable, Identifiable {
    public let pluginID: String
    public let name: String
    public let actions: [PluginAction]

    public var id: String { pluginID }

    /// Actions runnable from a sidebar row, one group per plugin, plugins and
    /// actions in name order.
    public static func menu(_ actions: [PluginAction]) -> [PluginActionGroup] {
        Dictionary(grouping: actions.filter(\.runsFromAgentMenu), by: \.pluginID)
            .map { pluginID, actions in
                PluginActionGroup(
                    pluginID: pluginID,
                    name: actions[0].pluginName,
                    actions: actions.sorted {
                        $0.menuTitle.localizedStandardCompare($1.menuTitle) == .orderedAscending
                    }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// One run of a plugin command (`plugin.log.list`), enough to say how it went.
public struct PluginCommandLog: Decodable, Sendable, Equatable {
    public let logID: String
    public let status: String
    public let exitCode: Int?
    public let stdout: String?
    public let stderr: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case logID = "log_id"
        case status
        case exitCode = "exit_code"
        case stdout
        case stderr
        case error
    }

    public init(logID: String, status: String, exitCode: Int? = nil, stdout: String? = nil, stderr: String? = nil, error: String? = nil) {
        self.logID = logID
        self.status = status
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.error = error
    }

    public var isFinished: Bool { status != "running" }
    public var succeeded: Bool { status == "succeeded" }

    /// What the command had to say, last line first: grazr prints its verdict
    /// ("Rotated a -> b", "Nothing to swap to, …") as the final line.
    public var summary: String? {
        let sources = succeeded ? [stdout, stderr] : [error, stderr, stdout]
        for source in sources {
            let lines = (source ?? "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if let last = lines.last { return last }
        }
        return nil
    }
}

/// Where an action runs: the agent row it was picked from.
public struct PluginInvocationTarget: Sendable, Equatable {
    public let workspaceID: String
    public let tabID: String
    public let paneID: String

    public init(workspaceID: String, tabID: String, paneID: String) {
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.paneID = paneID
    }
}

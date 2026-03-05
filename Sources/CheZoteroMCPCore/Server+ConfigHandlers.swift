// Server+ConfigHandlers.swift — Config read/write handlers
import Foundation
import MCP

extension CheZoteroMCPServer {

    func handleSetConfig(_ params: CallTool.Parameters) throws -> CallTool.Result {
        let key = params.arguments?["key"]?.stringValue ?? ""
        let value = params.arguments?["value"]?.stringValue
        let action = params.arguments?["action"]?.stringValue ?? "set"

        guard !key.isEmpty else {
            return CallTool.Result(content: [.text("Key must not be empty")], isError: true)
        }

        switch action {
        case "delete":
            try config.remove(key)
            return CallTool.Result(content: [.text("Deleted config key: \(key)")], isError: false)
        default:
            guard let value = value, !value.isEmpty else {
                return CallTool.Result(content: [.text("Value is required for action 'set'")], isError: true)
            }
            try config.set(key, value: value)
            return CallTool.Result(content: [.text("Config saved: \(key) = \(value)")], isError: false)
        }
    }

    func handleGetConfig(_ params: CallTool.Parameters) -> CallTool.Result {
        let key = params.arguments?["key"]?.stringValue

        if let key = key, !key.isEmpty {
            if let value = config.get(key) {
                return CallTool.Result(content: [.text("\(key) = \(value)")], isError: false)
            } else {
                return CallTool.Result(content: [.text("No config value for key: \(key)")], isError: false)
            }
        }

        // Return all config
        let all = config.getAll()
        if all.isEmpty {
            return CallTool.Result(content: [.text("Config is empty. Use zotero_set_config to store values.\n\nSuggested keys:\n  my.orcid — your ORCID ID\n  my.name — your name\n  my.openalex_author_id — your OpenAlex Author ID\n  researchers.<alias>.orcid — a collaborator's ORCID\n  researchers.<alias>.name — a collaborator's name")], isError: false)
        }

        var lines = ["Config (\(all.count) entries):"]
        for key in all.keys.sorted() {
            lines.append("  \(key) = \(all[key]!)")
        }
        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}

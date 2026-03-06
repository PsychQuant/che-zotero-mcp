// Server+CitationHandlers.swift — Citation formatting tool handlers
import Foundation
import MCP

extension CheZoteroMCPServer {

    func handleToAPA(_ params: CallTool.Parameters) throws -> CallTool.Result {
        let format = params.arguments?["format"]?.stringValue ?? "reference"
        let items = try resolveItems(params)
        if items.isEmpty {
            return CallTool.Result(content: [.text("No items found.")], isError: true)
        }

        let result: String
        switch format {
        case "citation":
            result = items.map { item in
                let ref = APACitationFormatter.formatReference(item)
                let cite = APACitationFormatter.formatCitation(item)
                let narrative = APACitationFormatter.formatNarrativeCitation(item)
                return "Parenthetical: \(cite)\nNarrative: \(narrative)\nFull reference: \(ref)"
            }.joined(separator: "\n\n---\n\n")
        case "reference_list":
            result = APACitationFormatter.formatReferenceList(items)
        default:
            // Single or multiple references
            result = items.map { APACitationFormatter.formatReference($0) }.joined(separator: "\n\n")
        }

        return CallTool.Result(content: [.text(result)], isError: false)
    }

    func handleToBiblatexAPA(_ params: CallTool.Parameters) throws -> CallTool.Result {
        let items = try resolveItems(params)
        if items.isEmpty {
            return CallTool.Result(content: [.text("No items found.")], isError: true)
        }

        let result = BiblatexAPAFormatter.formatAll(items)
        return CallTool.Result(content: [.text(result)], isError: false)
    }

    // MARK: - Resolve items from params (item_key, item_keys, or collection_key)

    private func resolveItems(_ params: CallTool.Parameters) throws -> [ZoteroItem] {
        // Single item
        if let key = params.arguments?["item_key"]?.stringValue, !key.isEmpty {
            if let item = try reader.getItem(key: key) {
                return [item]
            }
            return []
        }

        // Multiple items
        if let keysValue = params.arguments?["item_keys"],
           case .array(let keysArray) = keysValue {
            let keys = keysArray.compactMap(\.stringValue)
            return try keys.compactMap { try reader.getItem(key: $0) }
        }

        // Collection
        if let collKey = params.arguments?["collection_key"]?.stringValue, !collKey.isEmpty {
            return try reader.getItemsInCollection(collectionKey: collKey, limit: 500)
        }

        return []
    }
}

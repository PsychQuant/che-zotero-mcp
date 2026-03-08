import Foundation

public struct ImportResult {
    public var papersCreated: Int = 0
    public var papersSkipped: Int = 0
    public var researchersCreated: Int = 0
    public var journalsCreated: Int = 0
    public var authoredEdges: Int = 0
    public var coAuthorEdges: Int = 0
    public var publishedInEdges: Int = 0

    public var summary: String {
        """
        Import complete:
        - Papers: \(papersCreated) created, \(papersSkipped) skipped (duplicate DOI)
        - Researchers: \(researchersCreated) created
        - Journals: \(journalsCreated) created
        - Edges: \(authoredEdges) AUTHORED, \(coAuthorEdges) CO_AUTHOR, \(publishedInEdges) PUBLISHED_IN
        """
    }
}

public enum GraphImporter {

    public static func importFromZotero(items: [ZoteroItem], into engine: GraphEngine) -> ImportResult {
        var result = ImportResult()

        // Track co-author pairs to accumulate weights
        var coAuthorPairs: [String: (a: GraphNode, b: GraphNode, count: Int)] = [:]

        for item in items {
            // Skip if DOI already in graph
            if let doi = item.DOI, !doi.isEmpty {
                if engine.findByDOI(doi) != nil {
                    result.papersSkipped += 1
                    continue
                }
            }

            // Create Paper node
            var paperProps: [String: String] = ["title": item.title]
            if let doi = item.DOI, !doi.isEmpty { paperProps["doi"] = doi }
            if let date = item.date { paperProps["year"] = date }
            if let abstract = item.abstractNote { paperProps["abstract"] = abstract }
            let paperNode = engine.addNode(label: .paper, properties: paperProps)
            result.papersCreated += 1

            // Create/find Researcher nodes and AUTHORED edges
            var authorNodes: [GraphNode] = []
            for creator in item.creators {
                let normalized = creator.trimmingCharacters(in: .whitespaces)
                let existing = engine.findByName(normalized)
                let authorNode: GraphNode
                if let found = existing.first(where: { $0.label == .researcher }) {
                    authorNode = found
                } else {
                    authorNode = engine.addNode(label: .researcher, properties: ["name": normalized])
                    result.researchersCreated += 1
                }
                authorNodes.append(authorNode)

                _ = engine.addEdge(type: .authored, source: authorNode, target: paperNode, properties: [:])
                result.authoredEdges += 1
            }

            // CO_AUTHOR edges (accumulate)
            for i in 0..<authorNodes.count {
                for j in (i+1)..<authorNodes.count {
                    let a = authorNodes[i]
                    let b = authorNodes[j]
                    let key = coAuthorKey(a.properties["name"] ?? "", b.properties["name"] ?? "")
                    if let existing = coAuthorPairs[key] {
                        coAuthorPairs[key] = (existing.a, existing.b, existing.count + 1)
                    } else {
                        coAuthorPairs[key] = (a, b, 1)
                    }
                }
            }

            // Create/find Journal node and PUBLISHED_IN edge
            if let journal = item.publicationTitle, !journal.isEmpty {
                let normalizedJournal = journal.trimmingCharacters(in: .whitespaces)
                let existing = engine.findByName(normalizedJournal)
                let journalNode: GraphNode
                if let found = existing.first(where: { $0.label == .journal }) {
                    journalNode = found
                } else {
                    journalNode = engine.addNode(label: .journal, properties: ["name": normalizedJournal])
                    result.journalsCreated += 1
                }
                _ = engine.addEdge(type: .publishedIn, source: paperNode, target: journalNode, properties: [:])
                result.publishedInEdges += 1
            }
        }

        // Create CO_AUTHOR edges with accumulated weights
        for (_, pair) in coAuthorPairs {
            _ = engine.addEdge(
                type: .coAuthor,
                source: pair.a,
                target: pair.b,
                properties: ["weight": String(pair.count)]
            )
            result.coAuthorEdges += 1
        }

        return result
    }

    private static func coAuthorKey(_ a: String, _ b: String) -> String {
        let sorted = [a, b].sorted()
        return "\(sorted[0])::\(sorted[1])"
    }
}

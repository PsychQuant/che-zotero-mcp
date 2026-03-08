import Foundation

public struct CoAuthorStat {
    public let coauthor: GraphNode
    public let sharedPapers: Int
}

public enum GraphAlgorithms {

    // MARK: - Neighbor Discovery

    public static func neighbors(
        of node: GraphNode,
        edgeType: EdgeType? = nil,
        direction: EdgeDirection = .both
    ) -> [GraphNode] {
        node.neighbors(direction: direction, edgeType: edgeType)
    }

    // MARK: - Shortest Path (BFS)

    public static func shortestPath(
        from source: GraphNode,
        to target: GraphNode,
        edgeTypes: Set<EdgeType>? = nil
    ) -> [GraphNode]? {
        if source === target { return [source] }

        var visited: Set<UInt32> = [source.id]
        var queue: [(node: GraphNode, path: [GraphNode])] = [(source, [source])]
        var head = 0

        while head < queue.count {
            let (current, path) = queue[head]
            head += 1

            for edge in current.edges {
                if let allowed = edgeTypes, !allowed.contains(edge.type) { continue }

                let neighbor: GraphNode
                if edge.source === current {
                    neighbor = edge.target
                } else if edge.target === current {
                    neighbor = edge.source
                } else {
                    continue
                }

                if neighbor.id == target.id {
                    return path + [neighbor]
                }

                if !visited.contains(neighbor.id) {
                    visited.insert(neighbor.id)
                    queue.append((neighbor, path + [neighbor]))
                }
            }
        }

        return nil
    }

    // MARK: - Co-Author Stats

    public static func coAuthorStats(for researcher: GraphNode, in engine: GraphEngine) -> [CoAuthorStat] {
        var stats: [UInt32: (node: GraphNode, weight: Int)] = [:]

        for edge in researcher.edges where edge.type == .coAuthor {
            let other: GraphNode
            if edge.source === researcher {
                other = edge.target
            } else if edge.target === researcher {
                other = edge.source
            } else {
                continue
            }

            let weight = Int(edge.properties["weight"] ?? "1") ?? 1
            if let existing = stats[other.id] {
                stats[other.id] = (existing.node, existing.weight + weight)
            } else {
                stats[other.id] = (other, weight)
            }
        }

        return stats.values
            .map { CoAuthorStat(coauthor: $0.node, sharedPapers: $0.weight) }
            .sorted { $0.sharedPapers > $1.sharedPapers }
    }
}

// MARK: - Citation Tree

public struct CitationTree {
    public let node: GraphNode
    public let references: [CitationTree]  // papers this one cites (outgoing CITES)
    public let citedBy: [CitationTree]     // papers that cite this one (incoming CITES)
}

// MARK: - Citation Network

extension GraphAlgorithms {

    public static func citationNetwork(for paper: GraphNode, depth: Int) -> CitationTree {
        buildCitationTree(node: paper, depth: depth, visited: Set())
    }

    private static func buildCitationTree(node: GraphNode, depth: Int, visited: Set<UInt32>) -> CitationTree {
        guard depth > 0 else {
            return CitationTree(node: node, references: [], citedBy: [])
        }

        var newVisited = visited
        newVisited.insert(node.id)

        var references: [CitationTree] = []
        for edge in node.edges where edge.type == .cites && edge.source === node {
            let target = edge.target
            if !newVisited.contains(target.id) {
                references.append(buildCitationTree(node: target, depth: depth - 1, visited: newVisited))
            }
        }

        var citedBy: [CitationTree] = []
        for edge in node.edges where edge.type == .cites && edge.target === node {
            let source = edge.source
            if !newVisited.contains(source.id) {
                citedBy.append(buildCitationTree(node: source, depth: depth - 1, visited: newVisited))
            }
        }

        return CitationTree(node: node, references: references, citedBy: citedBy)
    }

    // MARK: - Community Detection (BFS-bounded)

    public static func community(
        seed: GraphNode,
        edgeType: EdgeType? = nil,
        maxHops: Int = 3
    ) -> Set<GraphNode> {
        var visited: Set<GraphNode> = [seed]
        var frontier: Set<GraphNode> = [seed]

        for _ in 0..<maxHops {
            var nextFrontier: Set<GraphNode> = []
            for node in frontier {
                for neighbor in node.neighbors(direction: .both, edgeType: edgeType) {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        nextFrontier.insert(neighbor)
                    }
                }
            }
            if nextFrontier.isEmpty { break }
            frontier = nextFrontier
        }

        return visited
    }
}

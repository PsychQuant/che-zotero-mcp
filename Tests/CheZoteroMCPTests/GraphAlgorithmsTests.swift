import XCTest
@testable import CheZoteroMCPCore

final class GraphAlgorithmsTests: XCTestCase {

    // Helper: build a small co-authorship graph
    //   A --coauthor(3)--> B --coauthor(1)--> C
    //   A --authored--> P1, B --authored--> P1
    //   B --authored--> P2, C --authored--> P2
    private func buildTestGraph() -> GraphEngine {
        let engine = GraphEngine()
        let a = engine.addNode(label: .researcher, properties: ["name": "A"])
        let b = engine.addNode(label: .researcher, properties: ["name": "B"])
        let c = engine.addNode(label: .researcher, properties: ["name": "C"])
        let p1 = engine.addNode(label: .paper, properties: ["title": "P1", "doi": "10.1/p1"])
        let p2 = engine.addNode(label: .paper, properties: ["title": "P2", "doi": "10.1/p2"])
        let j = engine.addNode(label: .journal, properties: ["name": "J1"])

        _ = engine.addEdge(type: .authored, source: a, target: p1, properties: [:])
        _ = engine.addEdge(type: .authored, source: b, target: p1, properties: [:])
        _ = engine.addEdge(type: .authored, source: b, target: p2, properties: [:])
        _ = engine.addEdge(type: .authored, source: c, target: p2, properties: [:])
        _ = engine.addEdge(type: .coAuthor, source: a, target: b, properties: ["weight": "3"])
        _ = engine.addEdge(type: .coAuthor, source: b, target: c, properties: ["weight": "1"])
        _ = engine.addEdge(type: .publishedIn, source: p1, target: j, properties: [:])
        _ = engine.addEdge(type: .publishedIn, source: p2, target: j, properties: [:])
        return engine
    }

    func testNeighbors() {
        let engine = buildTestGraph()
        let a = engine.findByName("A")[0]
        let neighbors = GraphAlgorithms.neighbors(of: a, edgeType: .coAuthor, direction: .outgoing)
        XCTAssertEqual(neighbors.count, 1)
        XCTAssertEqual(neighbors[0].properties["name"], "B")
    }

    func testNeighborsAllTypes() {
        let engine = buildTestGraph()
        let b = engine.findByName("B")[0]
        let all = GraphAlgorithms.neighbors(of: b, direction: .both)
        // B connects to: A (coauthor incoming), C (coauthor outgoing), P1 (authored), P2 (authored)
        XCTAssertGreaterThanOrEqual(all.count, 4)
    }

    func testShortestPathDirect() {
        let engine = buildTestGraph()
        let a = engine.findByName("A")[0]
        let b = engine.findByName("B")[0]
        let path = GraphAlgorithms.shortestPath(from: a, to: b, edgeTypes: [.coAuthor])
        XCTAssertNotNil(path)
        XCTAssertEqual(path?.count, 2) // [A, B]
        XCTAssertTrue(path![0] === a)
        XCTAssertTrue(path![1] === b)
    }

    func testShortestPathTwoHops() {
        let engine = buildTestGraph()
        let a = engine.findByName("A")[0]
        let c = engine.findByName("C")[0]
        let path = GraphAlgorithms.shortestPath(from: a, to: c, edgeTypes: [.coAuthor])
        XCTAssertNotNil(path)
        XCTAssertEqual(path?.count, 3) // [A, B, C]
    }

    func testShortestPathNoPath() {
        let engine = GraphEngine()
        let a = engine.addNode(label: .researcher, properties: ["name": "A"])
        let b = engine.addNode(label: .researcher, properties: ["name": "B"])
        let path = GraphAlgorithms.shortestPath(from: a, to: b)
        XCTAssertNil(path)
    }

    func testCoAuthorStats() {
        let engine = buildTestGraph()
        let a = engine.findByName("A")[0]
        let stats = GraphAlgorithms.coAuthorStats(for: a, in: engine)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].coauthor.properties["name"], "B")
        XCTAssertEqual(stats[0].sharedPapers, 3)
    }

    func testCoAuthorStatsMultiple() {
        let engine = buildTestGraph()
        let b = engine.findByName("B")[0]
        let stats = GraphAlgorithms.coAuthorStats(for: b, in: engine)
        XCTAssertEqual(stats.count, 2)
        // Sorted by weight descending
        XCTAssertEqual(stats[0].sharedPapers, 3)
        XCTAssertEqual(stats[1].sharedPapers, 1)
    }

    // MARK: - Citation Network

    private func buildCitationGraph() -> GraphEngine {
        let engine = GraphEngine()
        let p1 = engine.addNode(label: .paper, properties: ["title": "Root Paper", "doi": "10.1/root"])
        let p2 = engine.addNode(label: .paper, properties: ["title": "Cited A", "doi": "10.1/a"])
        let p3 = engine.addNode(label: .paper, properties: ["title": "Cited B", "doi": "10.1/b"])
        let p4 = engine.addNode(label: .paper, properties: ["title": "Cited by A", "doi": "10.1/c"])

        _ = engine.addEdge(type: .cites, source: p1, target: p2, properties: [:])
        _ = engine.addEdge(type: .cites, source: p1, target: p3, properties: [:])
        _ = engine.addEdge(type: .cites, source: p4, target: p1, properties: [:])
        return engine
    }

    func testCitationNetworkReferences() {
        let engine = buildCitationGraph()
        let root = engine.findByDOI("10.1/root")!
        let tree = GraphAlgorithms.citationNetwork(for: root, depth: 1)

        XCTAssertEqual(tree.references.count, 2)
        let refTitles = Set(tree.references.map { $0.node.properties["title"]! })
        XCTAssertTrue(refTitles.contains("Cited A"))
        XCTAssertTrue(refTitles.contains("Cited B"))
    }

    func testCitationNetworkCitedBy() {
        let engine = buildCitationGraph()
        let root = engine.findByDOI("10.1/root")!
        let tree = GraphAlgorithms.citationNetwork(for: root, depth: 1)

        XCTAssertEqual(tree.citedBy.count, 1)
        XCTAssertEqual(tree.citedBy[0].node.properties["title"], "Cited by A")
    }

    func testCitationNetworkDepthZero() {
        let engine = buildCitationGraph()
        let root = engine.findByDOI("10.1/root")!
        let tree = GraphAlgorithms.citationNetwork(for: root, depth: 0)
        XCTAssertTrue(tree.references.isEmpty)
        XCTAssertTrue(tree.citedBy.isEmpty)
    }

    // MARK: - Community Detection

    func testCommunityDetection() {
        let engine = GraphEngine()
        let a = engine.addNode(label: .researcher, properties: ["name": "A"])
        let b = engine.addNode(label: .researcher, properties: ["name": "B"])
        let c = engine.addNode(label: .researcher, properties: ["name": "C"])
        let d = engine.addNode(label: .researcher, properties: ["name": "D"])
        let e = engine.addNode(label: .researcher, properties: ["name": "E"])

        _ = engine.addEdge(type: .coAuthor, source: a, target: b, properties: [:])
        _ = engine.addEdge(type: .coAuthor, source: b, target: c, properties: [:])
        _ = engine.addEdge(type: .coAuthor, source: a, target: c, properties: [:])
        _ = engine.addEdge(type: .coAuthor, source: d, target: e, properties: [:])
        _ = engine.addEdge(type: .coAuthor, source: a, target: d, properties: [:])

        let community = GraphAlgorithms.community(seed: a, edgeType: .coAuthor, maxHops: 2)
        XCTAssertTrue(community.contains(a))
        XCTAssertTrue(community.contains(b))
        XCTAssertTrue(community.contains(c))
    }
}

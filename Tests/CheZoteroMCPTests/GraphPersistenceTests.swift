import XCTest
@testable import CheZoteroMCPCore

final class GraphPersistenceTests: XCTestCase {

    private var tempPath: String!

    override func setUp() {
        super.setUp()
        tempPath = NSTemporaryDirectory() + "test_graph_\(UUID().uuidString).bin"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempPath)
        super.tearDown()
    }

    func testSaveCreatesFile() throws {
        let engine = GraphEngine()
        _ = engine.addNode(label: .researcher, properties: ["name": "Test"])

        try GraphPersistence.save(engine: engine, to: tempPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
    }

    func testSaveHeaderMagicBytes() throws {
        let engine = GraphEngine()
        _ = engine.addNode(label: .researcher, properties: ["name": "Test"])

        try GraphPersistence.save(engine: engine, to: tempPath)

        let data = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        XCTAssertEqual(data[0], 0x43) // C
        XCTAssertEqual(data[1], 0x48) // H
        XCTAssertEqual(data[2], 0x45) // E
        XCTAssertEqual(data[3], 0x47) // G
    }

    func testSaveAndLoadRoundTrip() throws {
        let engine = GraphEngine()
        let a = engine.addNode(label: .researcher, properties: ["name": "Yi-Hau Chen", "orcid": "0000-0001-1234-5678"])
        let b = engine.addNode(label: .paper, properties: ["title": "A Great Paper", "doi": "10.1234/test", "year": "2024"])
        let j = engine.addNode(label: .journal, properties: ["name": "Biometrika"])
        _ = engine.addEdge(type: .authored, source: a, target: b, properties: [:])
        _ = engine.addEdge(type: .publishedIn, source: b, target: j, properties: [:])

        try GraphPersistence.save(engine: engine, to: tempPath)

        let loaded = try GraphPersistence.load(from: tempPath)
        XCTAssertEqual(loaded.nodeCount, 3)
        XCTAssertEqual(loaded.edgeCount, 2)

        let researchers = loaded.findByLabel(.researcher)
        XCTAssertEqual(researchers.count, 1)
        XCTAssertEqual(researchers[0].properties["name"], "Yi-Hau Chen")
        XCTAssertEqual(researchers[0].properties["orcid"], "0000-0001-1234-5678")

        let paper = loaded.findByDOI("10.1234/test")
        XCTAssertNotNil(paper)
        XCTAssertEqual(paper?.properties["title"], "A Great Paper")

        let paperNeighbors = paper!.neighbors(direction: .incoming, edgeType: .authored)
        XCTAssertEqual(paperNeighbors.count, 1)
        XCTAssertEqual(paperNeighbors[0].properties["name"], "Yi-Hau Chen")
    }

    func testLoadNonexistentFileReturnsEmptyEngine() throws {
        let loaded = try GraphPersistence.load(from: "/nonexistent/graph.bin")
        XCTAssertEqual(loaded.nodeCount, 0)
        XCTAssertEqual(loaded.edgeCount, 0)
    }

    func testSaveMarksClean() throws {
        let engine = GraphEngine()
        _ = engine.addNode(label: .researcher, properties: [:])
        XCTAssertTrue(engine.isDirty)

        try GraphPersistence.save(engine: engine, to: tempPath)
        XCTAssertFalse(engine.isDirty)
    }

    func testRoundTripWithEdgeProperties() throws {
        let engine = GraphEngine()
        let a = engine.addNode(label: .researcher, properties: ["name": "A"])
        let b = engine.addNode(label: .researcher, properties: ["name": "B"])
        _ = engine.addEdge(type: .coAuthor, source: a, target: b, properties: ["weight": "5"])

        try GraphPersistence.save(engine: engine, to: tempPath)
        let loaded = try GraphPersistence.load(from: tempPath)

        XCTAssertEqual(loaded.edgeCount, 1)
        let coauthorEdges = loaded.findByLabel(.researcher)[0].edges.filter { $0.type == .coAuthor }
        XCTAssertEqual(coauthorEdges.count, 1)
        XCTAssertEqual(coauthorEdges[0].properties["weight"], "5")
    }

    func testRoundTripUnicodeProperties() throws {
        let engine = GraphEngine()
        _ = engine.addNode(label: .researcher, properties: ["name": "程毅豪", "affiliation": "中央研究院統計科學研究所"])

        try GraphPersistence.save(engine: engine, to: tempPath)
        let loaded = try GraphPersistence.load(from: tempPath)

        let node = loaded.findByLabel(.researcher)[0]
        XCTAssertEqual(node.properties["name"], "程毅豪")
        XCTAssertEqual(node.properties["affiliation"], "中央研究院統計科學研究所")
    }
}

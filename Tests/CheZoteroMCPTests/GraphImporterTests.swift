import XCTest
@testable import CheZoteroMCPCore

final class GraphImporterTests: XCTestCase {

    private func makePaper(key: String, title: String, doi: String?, creators: [String], journal: String?) -> ZoteroItem {
        ZoteroItem(
            key: key,
            itemType: "journalArticle",
            title: title,
            creators: creators,
            creatorDetails: [],
            abstractNote: nil,
            date: "2024",
            publicationTitle: journal,
            DOI: doi,
            url: nil,
            tags: [],
            collections: [],
            dateAdded: "2024-01-01",
            dateModified: "2024-01-01",
            allFields: [:]
        )
    }

    func testImportSinglePaper() {
        let engine = GraphEngine()
        let items = [makePaper(key: "K1", title: "Paper 1", doi: "10.1/p1", creators: ["Alice", "Bob"], journal: "Nature")]
        let result = GraphImporter.importFromZotero(items: items, into: engine)

        XCTAssertEqual(result.papersCreated, 1)
        XCTAssertEqual(result.researchersCreated, 2)
        XCTAssertEqual(result.journalsCreated, 1)
        XCTAssertEqual(engine.findByLabel(.paper).count, 1)
        XCTAssertEqual(engine.findByLabel(.researcher).count, 2)
        XCTAssertEqual(engine.findByLabel(.journal).count, 1)

        XCTAssertNotNil(engine.findByDOI("10.1/p1"))
    }

    func testImportDeduplicatesAuthors() {
        let engine = GraphEngine()
        let items = [
            makePaper(key: "K1", title: "P1", doi: "10.1/p1", creators: ["Alice", "Bob"], journal: "Nature"),
            makePaper(key: "K2", title: "P2", doi: "10.1/p2", creators: ["Alice", "Charlie"], journal: "Science"),
        ]
        let result = GraphImporter.importFromZotero(items: items, into: engine)

        XCTAssertEqual(result.researchersCreated, 3) // Alice, Bob, Charlie
        XCTAssertEqual(engine.findByName("Alice").count, 1)
    }

    func testImportCreatesCoAuthorEdges() {
        let engine = GraphEngine()
        let items = [
            makePaper(key: "K1", title: "P1", doi: "10.1/p1", creators: ["Alice", "Bob"], journal: nil),
        ]
        _ = GraphImporter.importFromZotero(items: items, into: engine)

        let alice = engine.findByName("Alice")[0]
        let coauthors = alice.neighbors(direction: .both, edgeType: .coAuthor)
        XCTAssertEqual(coauthors.count, 1)
        XCTAssertEqual(coauthors[0].properties["name"], "Bob")
    }

    func testImportCoAuthorWeightAccumulates() {
        let engine = GraphEngine()
        let items = [
            makePaper(key: "K1", title: "P1", doi: "10.1/p1", creators: ["Alice", "Bob"], journal: nil),
            makePaper(key: "K2", title: "P2", doi: "10.1/p2", creators: ["Alice", "Bob"], journal: nil),
        ]
        _ = GraphImporter.importFromZotero(items: items, into: engine)

        let alice = engine.findByName("Alice")[0]
        let coauthorEdges = alice.edges.filter { $0.type == .coAuthor }
        XCTAssertEqual(coauthorEdges.count, 1)
        XCTAssertEqual(coauthorEdges[0].properties["weight"], "2")
    }

    func testImportDeduplicatesJournals() {
        let engine = GraphEngine()
        let items = [
            makePaper(key: "K1", title: "P1", doi: "10.1/p1", creators: ["A"], journal: "Nature"),
            makePaper(key: "K2", title: "P2", doi: "10.1/p2", creators: ["B"], journal: "Nature"),
        ]
        let result = GraphImporter.importFromZotero(items: items, into: engine)

        XCTAssertEqual(result.journalsCreated, 1)
        XCTAssertEqual(engine.findByLabel(.journal).count, 1)
    }

    func testImportSkipsDuplicateDOIs() {
        let engine = GraphEngine()
        _ = engine.addNode(label: .paper, properties: ["title": "Existing", "doi": "10.1/p1"])

        let items = [makePaper(key: "K1", title: "P1", doi: "10.1/p1", creators: ["A"], journal: nil)]
        let result = GraphImporter.importFromZotero(items: items, into: engine)

        XCTAssertEqual(result.papersCreated, 0)
        XCTAssertEqual(result.papersSkipped, 1)
    }
}

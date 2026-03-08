import Foundation

public enum GraphPersistenceError: LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt16)
    case corruptedData(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMagic: return "Not a valid graph file (bad magic bytes)"
        case .unsupportedVersion(let v): return "Unsupported graph file version: \(v)"
        case .corruptedData(let msg): return "Corrupted graph data: \(msg)"
        }
    }
}

/// Binary persistence for GraphEngine.
///
/// File layout:
/// - Header (32 bytes): magic "CHEG", version, counts, string table offset
/// - Node records (32 bytes each)
/// - Edge records (32 bytes each)
/// - Property records (24 bytes each)
/// - String table (variable length)
public enum GraphPersistence {

    private static let magic: [UInt8] = [0x43, 0x48, 0x45, 0x47] // "CHEG"
    private static let currentVersion: UInt16 = 1
    private static let headerSize = 32
    private static let nodeRecordSize = 32
    private static let edgeRecordSize = 32
    private static let propRecordSize = 24

    // MARK: - Save

    public static func save(engine: GraphEngine, to path: String) throws {
        var stringTable = StringTableBuilder()

        let sortedNodes = engine.allNodes.values.sorted { $0.id < $1.id }
        let sortedEdges = engine.allEdgesDict.values.sorted { $0.id < $1.id }

        struct PropRecord {
            let ownerId: UInt32
            let ownerType: UInt8 // 0=node, 1=edge
            let keyOff: UInt32
            let valOff: UInt32
        }

        var propRecords: [PropRecord] = []

        // Node properties
        var nodeFirstProp: [UInt32: Int32] = [:]
        for node in sortedNodes {
            let sorted = node.properties.sorted { $0.key < $1.key }
            if sorted.isEmpty {
                nodeFirstProp[node.id] = -1
                continue
            }
            nodeFirstProp[node.id] = Int32(propRecords.count)
            for kv in sorted {
                propRecords.append(PropRecord(
                    ownerId: node.id,
                    ownerType: 0,
                    keyOff: stringTable.add(kv.key),
                    valOff: stringTable.add(kv.value)
                ))
            }
        }

        // Edge properties
        var edgeFirstProp: [UInt32: Int32] = [:]
        for edge in sortedEdges {
            let sorted = edge.properties.sorted { $0.key < $1.key }
            if sorted.isEmpty {
                edgeFirstProp[edge.id] = -1
                continue
            }
            edgeFirstProp[edge.id] = Int32(propRecords.count)
            for kv in sorted {
                propRecords.append(PropRecord(
                    ownerId: edge.id,
                    ownerType: 1,
                    keyOff: stringTable.add(kv.key),
                    valOff: stringTable.add(kv.value)
                ))
            }
        }

        // Build edge linked lists for nodes
        var nodeFirstEdge: [UInt32: Int32] = [:]
        var edgeSrcNext: [UInt32: Int32] = [:]
        var edgeTgtNext: [UInt32: Int32] = [:]

        var srcChains: [UInt32: [UInt32]] = [:]
        var tgtChains: [UInt32: [UInt32]] = [:]
        for edge in sortedEdges {
            srcChains[edge.source.id, default: []].append(edge.id)
            tgtChains[edge.target.id, default: []].append(edge.id)
        }

        for node in sortedNodes {
            let srcFirst = srcChains[node.id]?.first
            let tgtFirst = tgtChains[node.id]?.first
            if let s = srcFirst {
                nodeFirstEdge[node.id] = Int32(s)
            } else if let t = tgtFirst {
                nodeFirstEdge[node.id] = Int32(t)
            } else {
                nodeFirstEdge[node.id] = -1
            }
        }

        for (_, chain) in srcChains {
            for (i, edgeId) in chain.enumerated() {
                edgeSrcNext[edgeId] = i + 1 < chain.count ? Int32(chain[i + 1]) : -1
            }
        }
        for (_, chain) in tgtChains {
            for (i, edgeId) in chain.enumerated() {
                edgeTgtNext[edgeId] = i + 1 < chain.count ? Int32(chain[i + 1]) : -1
            }
        }

        // Calculate offsets
        let nodeDataSize = sortedNodes.count * nodeRecordSize
        let edgeDataSize = sortedEdges.count * edgeRecordSize
        let propDataSize = propRecords.count * propRecordSize
        let strOffset = UInt64(headerSize + nodeDataSize + edgeDataSize + propDataSize)

        // Write binary data
        var data = Data()
        data.reserveCapacity(Int(strOffset) + stringTable.totalSize)

        // Header (32 bytes)
        data.append(contentsOf: magic)
        data.appendUInt16(currentVersion)
        data.appendUInt32(UInt32(sortedNodes.count))
        data.appendUInt32(UInt32(sortedEdges.count))
        data.appendUInt32(UInt32(propRecords.count))
        data.appendUInt64(strOffset)
        data.append(contentsOf: [UInt8](repeating: 0, count: 6)) // reserved

        // Node records (32 bytes each)
        for node in sortedNodes {
            data.appendUInt32(node.id)
            data.append(node.label.rawValue)
            data.appendInt32(nodeFirstEdge[node.id] ?? -1)
            data.appendInt32(nodeFirstProp[node.id] ?? -1)
            let nameOff = node.properties["name"].map { stringTable.offset(for: $0) } ?? 0
            data.appendUInt32(nameOff)
            data.append(contentsOf: [UInt8](repeating: 0, count: 15)) // reserved
        }

        // Edge records (32 bytes each)
        for edge in sortedEdges {
            data.appendUInt32(edge.id)
            data.appendUInt32(edge.source.id)
            data.appendUInt32(edge.target.id)
            data.append(edge.type.rawValue)
            data.appendInt32(edgeSrcNext[edge.id] ?? -1)
            data.appendInt32(edgeTgtNext[edge.id] ?? -1)
            data.appendInt32(edgeFirstProp[edge.id] ?? -1)
            data.append(contentsOf: [UInt8](repeating: 0, count: 7)) // reserved
        }

        // Property records (24 bytes each)
        var propsByOwner: [String: [Int]] = [:]
        for (i, prop) in propRecords.enumerated() {
            let key = "\(prop.ownerId)-\(prop.ownerType)"
            propsByOwner[key, default: []].append(i)
        }

        var nextPropLinks: [Int: Int32] = [:]
        for (_, indices) in propsByOwner {
            for (j, idx) in indices.enumerated() {
                nextPropLinks[idx] = j + 1 < indices.count ? Int32(indices[j + 1]) : -1
            }
        }

        for (i, prop) in propRecords.enumerated() {
            data.appendUInt32(prop.ownerId)
            data.append(prop.ownerType)
            data.appendUInt32(prop.keyOff)
            data.appendUInt32(prop.valOff)
            data.appendInt32(nextPropLinks[i] ?? -1)
            data.append(contentsOf: [UInt8](repeating: 0, count: 7)) // reserved
        }

        // String table
        data.append(stringTable.build())

        // Ensure directory exists
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        try data.write(to: URL(fileURLWithPath: path))
        engine.markClean()
    }

    // MARK: - Load

    public static func load(from path: String) throws -> GraphEngine {
        guard FileManager.default.fileExists(atPath: path) else {
            return GraphEngine()
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard data.count >= headerSize else {
            throw GraphPersistenceError.corruptedData("File too small for header")
        }

        guard data[0] == magic[0], data[1] == magic[1], data[2] == magic[2], data[3] == magic[3] else {
            throw GraphPersistenceError.invalidMagic
        }

        let version = data.readUInt16(at: 4)
        guard version == currentVersion else {
            throw GraphPersistenceError.unsupportedVersion(version)
        }

        let nodeCount = Int(data.readUInt32(at: 6))
        let edgeCount = Int(data.readUInt32(at: 10))
        let propCount = Int(data.readUInt32(at: 14))
        let strOffset = Int(data.readUInt64(at: 18))

        let stringTable = StringTableReader(data: data, offset: strOffset)

        // Parse property records
        let propBase = headerSize + nodeCount * nodeRecordSize + edgeCount * edgeRecordSize

        struct RawProp {
            let ownerId: UInt32
            let ownerType: UInt8
            let key: String
            let value: String
            let nextProp: Int32
        }

        var rawProps: [Int: RawProp] = [:]
        for i in 0..<propCount {
            let off = propBase + i * propRecordSize
            let ownerId = data.readUInt32(at: off)
            let ownerType = data[off + 4]
            let keyOff = data.readUInt32(at: off + 5)
            let valOff = data.readUInt32(at: off + 9)
            let nextProp = data.readInt32(at: off + 13)
            rawProps[i] = RawProp(
                ownerId: ownerId,
                ownerType: ownerType,
                key: stringTable.read(at: keyOff),
                value: stringTable.read(at: valOff),
                nextProp: nextProp
            )
        }

        func collectProperties(firstPropIndex: Int32) -> [String: String] {
            var props: [String: String] = [:]
            var idx = firstPropIndex
            while idx >= 0, let prop = rawProps[Int(idx)] {
                props[prop.key] = prop.value
                idx = prop.nextProp
            }
            return props
        }

        // Parse nodes
        let engine = GraphEngine()
        var nodeMap: [UInt32: GraphNode] = [:]
        var maxNodeId: UInt32 = 0

        for i in 0..<nodeCount {
            let off = headerSize + i * nodeRecordSize
            let id = data.readUInt32(at: off)
            let labelRaw = data[off + 4]
            let firstProp = data.readInt32(at: off + 9)

            guard let label = NodeLabel(rawValue: labelRaw) else {
                throw GraphPersistenceError.corruptedData("Invalid node label: \(labelRaw)")
            }

            let properties = collectProperties(firstPropIndex: firstProp)
            let node = engine.addNode(label: label, properties: properties)
            nodeMap[id] = node
            if id > maxNodeId { maxNodeId = id }
        }

        // Parse edges
        let edgeBase = headerSize + nodeCount * nodeRecordSize
        for i in 0..<edgeCount {
            let off = edgeBase + i * edgeRecordSize
            let id = data.readUInt32(at: off)
            let sourceId = data.readUInt32(at: off + 4)
            let targetId = data.readUInt32(at: off + 8)
            let typeRaw = data[off + 12]
            let firstProp = data.readInt32(at: off + 21)

            guard let edgeType = EdgeType(rawValue: typeRaw) else {
                throw GraphPersistenceError.corruptedData("Invalid edge type: \(typeRaw)")
            }
            guard let srcNode = nodeMap[sourceId], let tgtNode = nodeMap[targetId] else {
                throw GraphPersistenceError.corruptedData("Edge references missing node")
            }

            let properties = collectProperties(firstPropIndex: firstProp)
            _ = engine.addEdge(type: edgeType, source: srcNode, target: tgtNode, properties: properties)
        }

        engine.markClean()
        return engine
    }
}

// MARK: - String Table Builder

private class StringTableBuilder {
    private var strings: [String] = []
    private var offsets: [String: UInt32] = [:]
    private var currentOffset: UInt32 = 0

    func add(_ string: String) -> UInt32 {
        if let existing = offsets[string] {
            return existing
        }
        let offset = currentOffset
        offsets[string] = offset
        strings.append(string)
        let utf8 = Array(string.utf8)
        currentOffset += UInt32(2 + utf8.count)
        return offset
    }

    func offset(for string: String) -> UInt32 {
        offsets[string] ?? 0
    }

    var totalSize: Int { Int(currentOffset) }

    func build() -> Data {
        var data = Data()
        for string in strings {
            let utf8 = Array(string.utf8)
            data.appendUInt16(UInt16(utf8.count))
            data.append(contentsOf: utf8)
        }
        return data
    }
}

// MARK: - String Table Reader

private struct StringTableReader {
    let data: Data
    let baseOffset: Int

    init(data: Data, offset: Int) {
        self.data = data
        self.baseOffset = offset
    }

    func read(at offset: UInt32) -> String {
        let pos = baseOffset + Int(offset)
        guard pos + 2 <= data.count else { return "" }
        let length = Int(data.readUInt16(at: pos))
        guard pos + 2 + length <= data.count else { return "" }
        let bytes = data.subdata(in: (pos + 2)..<(pos + 2 + length))
        return String(data: bytes, encoding: .utf8) ?? ""
    }
}

// MARK: - Data Extensions for Binary I/O

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &v) { Array($0) })
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &v) { Array($0) })
    }

    mutating func appendInt32(_ value: Int32) {
        var v = value.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &v) { Array($0) })
    }

    mutating func appendUInt64(_ value: UInt64) {
        var v = value.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &v) { Array($0) })
    }

    func readUInt16(at offset: Int) -> UInt16 {
        subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }

    func readInt32(at offset: Int) -> Int32 {
        subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
    }

    func readUInt64(at offset: Int) -> UInt64 {
        subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
    }
}

// Sources/CheZoteroMCPCore/ConfigManager.swift
//
// Persistent key-value config stored at ~/.che-zotero-mcp/config.json
// Supports arbitrary keys; some keys have special behavior in other tools.

import Foundation

public class ConfigManager {
    private let configDir: String
    private let configPath: String
    private var config: [String: String]

    public init() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configDir = "\(home)/.che-zotero-mcp"
        self.configPath = "\(configDir)/config.json"
        self.config = try Self.load(from: configPath)
    }

    // MARK: - Read

    public func get(_ key: String) -> String? {
        config[key]
    }

    public func getAll() -> [String: String] {
        config
    }

    // MARK: - Write

    public func set(_ key: String, value: String) throws {
        config[key] = value
        try save()
    }

    public func remove(_ key: String) throws {
        config.removeValue(forKey: key)
        try save()
    }

    // MARK: - Private

    private static func load(from path: String) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: path) else {
            return [:]
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func save() throws {
        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: configDir) {
            try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: configPath))
    }
}

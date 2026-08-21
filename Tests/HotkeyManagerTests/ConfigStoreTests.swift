import Foundation
import XCTest
@testable import HotkeyManager

final class ConfigStoreTests: XCTestCase {
    private func makeStore() throws -> (ConfigStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HotkeyManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return (ConfigStore(fileURL: directory.appendingPathComponent("config.json")), directory)
    }

    func testSaveAndLoadRoundTrip() throws {
        let (store, _) = try makeStore()
        var entry = HotkeyEntry()
        entry.key = "cmd+1"
        entry.bundleId = "com.example.App"
        var config = AppConfig()
        config.hotkeys = [entry]

        XCTAssertTrue(store.save(config))
        XCTAssertEqual(store.load(), config)
    }

    func testInvalidJSONDoesNotProduceEmptyConfiguration() throws {
        let (store, _) = try makeStore()
        try Data("{ invalid".utf8).write(to: store.fileURL)

        XCTAssertNil(store.load())
    }

    func testDefaultTemplateIsValid() throws {
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(ConfigStore.defaultTemplate.utf8))

        XCTAssertFalse(decoded.hotkeys.isEmpty)
        XCTAssertTrue(decoded.hotkeys.allSatisfy { KeyCodeMap.parse($0.key) != nil })
        XCTAssertTrue(decoded.hotkeys.allSatisfy { !$0.bundleId.isEmpty })
    }

    func testRepositoryTemplateMatchesBuiltInTemplate() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryData = try Data(contentsOf: repositoryRoot.appendingPathComponent("config.json"))
        let repositoryConfig = try JSONDecoder().decode(AppConfig.self, from: repositoryData)
        let builtInConfig = try JSONDecoder().decode(
            AppConfig.self,
            from: Data(ConfigStore.defaultTemplate.utf8)
        )

        XCTAssertEqual(repositoryConfig, builtInConfig)
    }
}

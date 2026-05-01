//
//  BlompieTVTests.swift
//  BlompieTVTests
//
//  Unit tests for BlompieTV text adventure game
//  Created by Jordan Koch
//  Copyright 2026 Jordan Koch. All rights reserved.
//

import XCTest
@testable import BlompieTV

// MARK: - Model Tests

final class GameMessageTests: XCTestCase {

    func testGameMessageInitialization() {
        let message = GameMessage(text: "Hello, adventurer!")
        XCTAssertEqual(message.text, "Hello, adventurer!")
        XCTAssertNotNil(message.id)
        XCTAssertNotNil(message.timestamp)
    }

    func testGameMessageUniqueIDs() {
        let msg1 = GameMessage(text: "First")
        let msg2 = GameMessage(text: "Second")
        XCTAssertNotEqual(msg1.id, msg2.id)
    }

    func testGameMessageCodable() throws {
        let original = GameMessage(text: "Test message")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameMessage.self, from: data)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.id, original.id)
    }
}

final class SaveSlotTests: XCTestCase {

    func testSaveSlotInitialization() {
        let slot = SaveSlot(id: "slot1", name: "My Save", savedDate: Date(), messageCount: 42)
        XCTAssertEqual(slot.id, "slot1")
        XCTAssertEqual(slot.name, "My Save")
        XCTAssertEqual(slot.messageCount, 42)
    }

    func testSaveSlotCodable() throws {
        let original = SaveSlot(id: "test", name: "Test Save", savedDate: Date(), messageCount: 10)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SaveSlot.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.messageCount, original.messageCount)
    }
}

final class GameSnapshotTests: XCTestCase {

    func testGameSnapshotCodable() throws {
        let messages = [GameMessage(text: "Hello")]
        let history = [OllamaMessage(role: "user", content: "test")]
        let actions = ["Look around", "Go north"]

        let snapshot = GameSnapshot(
            messages: messages,
            conversationHistory: history,
            currentActions: actions
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: data)

        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.conversationHistory.count, 1)
        XCTAssertEqual(decoded.currentActions, ["Look around", "Go north"])
    }
}

final class AchievementTests: XCTestCase {

    func testAchievementInitialization() {
        let achievement = Achievement(id: "first_step", title: "First Steps", description: "Take your first action", isUnlocked: false, unlockDate: nil)
        XCTAssertEqual(achievement.id, "first_step")
        XCTAssertFalse(achievement.isUnlocked)
        XCTAssertNil(achievement.unlockDate)
    }

    func testUnlockedAchievement() {
        let now = Date()
        let achievement = Achievement(id: "explorer", title: "Explorer", description: "Visit 5 locations", isUnlocked: true, unlockDate: now)
        XCTAssertTrue(achievement.isUnlocked)
        XCTAssertEqual(achievement.unlockDate, now)
    }

    func testAchievementCodable() throws {
        let original = Achievement(id: "test", title: "Test", description: "A test achievement", isUnlocked: true, unlockDate: Date())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Achievement.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.isUnlocked, original.isUnlocked)
    }
}

final class DetailLevelTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(DetailLevel.allCases.count, 3)
        XCTAssertEqual(DetailLevel.brief.rawValue, "Brief")
        XCTAssertEqual(DetailLevel.normal.rawValue, "Normal")
        XCTAssertEqual(DetailLevel.detailed.rawValue, "Detailed")
    }

    func testCodable() throws {
        for level in DetailLevel.allCases {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(DetailLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }
}

final class ToneStyleTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(ToneStyle.allCases.count, 3)
        XCTAssertEqual(ToneStyle.serious.rawValue, "Serious")
        XCTAssertEqual(ToneStyle.balanced.rawValue, "Balanced")
        XCTAssertEqual(ToneStyle.whimsical.rawValue, "Whimsical")
    }
}

// MARK: - OllamaService Model Tests

final class OllamaMessageTests: XCTestCase {

    func testOllamaMessageCodable() throws {
        let msg = OllamaMessage(role: "user", content: "Hello")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(OllamaMessage.self, from: data)
        XCTAssertEqual(decoded.role, "user")
        XCTAssertEqual(decoded.content, "Hello")
    }

    func testOllamaChatRequestCodable() throws {
        let messages = [OllamaMessage(role: "system", content: "You are helpful")]
        let request = OllamaChatRequest(
            model: "mistral",
            messages: messages,
            stream: false,
            options: OllamaOptions(temperature: 0.7, num_predict: 2048)
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(OllamaChatRequest.self, from: data)
        XCTAssertEqual(decoded.model, "mistral")
        XCTAssertFalse(decoded.stream)
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.options?.temperature, 0.7)
    }
}

final class OllamaChatResponseTests: XCTestCase {

    func testTokensPerSecondCalculation() {
        // Manually construct via JSON decoding since struct has no memberwise init we can easily use
        let json = """
        {
            "message": {"role": "assistant", "content": "Hello!"},
            "done": true,
            "eval_count": 100,
            "eval_duration": 2000000000
        }
        """
        let data = json.data(using: .utf8)!
        let response = try! JSONDecoder().decode(OllamaChatResponse.self, from: data)

        XCTAssertNotNil(response.tokensPerSecond)
        XCTAssertEqual(response.tokensPerSecond!, 50.0, accuracy: 0.01) // 100 tokens / 2 seconds
    }

    func testTokensPerSecondNilWhenMissing() {
        let json = """
        {
            "message": {"role": "assistant", "content": "Hello!"},
            "done": true
        }
        """
        let data = json.data(using: .utf8)!
        let response = try! JSONDecoder().decode(OllamaChatResponse.self, from: data)
        XCTAssertNil(response.tokensPerSecond)
    }

    func testTokensPerSecondZeroDuration() {
        let json = """
        {
            "message": {"role": "assistant", "content": "Hello!"},
            "done": true,
            "eval_count": 100,
            "eval_duration": 0
        }
        """
        let data = json.data(using: .utf8)!
        let response = try! JSONDecoder().decode(OllamaChatResponse.self, from: data)
        XCTAssertNil(response.tokensPerSecond)
    }
}

final class OllamaErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertNotNil(OllamaError.invalidURL.errorDescription)
        XCTAssertNotNil(OllamaError.noServerConfigured.errorDescription)
        XCTAssertNotNil(OllamaError.serverUnreachable.errorDescription)

        let networkError = OllamaError.networkError(NSError(domain: "test", code: -1))
        XCTAssertNotNil(networkError.errorDescription)

        let invalidResponse = OllamaError.invalidResponse(statusCode: 500, body: "error")
        XCTAssertTrue(invalidResponse.errorDescription!.contains("500"))

        let invalidResponseNoCode = OllamaError.invalidResponse(statusCode: nil, body: nil)
        XCTAssertNotNil(invalidResponseNoCode.errorDescription)
    }
}

// MARK: - AI Backend Tests

final class AIBackendTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(AIBackend.allCases.count, 5)
    }

    func testIcons() {
        for backend in AIBackend.allCases {
            XCTAssertFalse(backend.icon.isEmpty, "\(backend.rawValue) should have an icon")
        }
    }

    func testDescriptions() {
        for backend in AIBackend.allCases {
            XCTAssertFalse(backend.description.isEmpty, "\(backend.rawValue) should have a description")
        }
    }

    func testAttribution() {
        XCTAssertNotNil(AIBackend.tinyLLM.attribution)
        XCTAssertNotNil(AIBackend.tinyChat.attribution)
        XCTAssertNotNil(AIBackend.openWebUI.attribution)
        XCTAssertNil(AIBackend.ollama.attribution)
        XCTAssertNil(AIBackend.auto.attribution)
    }

    func testCodable() throws {
        for backend in AIBackend.allCases {
            let data = try JSONEncoder().encode(backend)
            let decoded = try JSONDecoder().decode(AIBackend.self, from: data)
            XCTAssertEqual(decoded, backend)
        }
    }
}

final class AIBackendSettingsTests: XCTestCase {

    func testSettingsCodable() throws {
        let settings = AIBackendSettings(
            selectedBackend: .ollama,
            ollamaBaseURL: "http://localhost:11434",
            selectedOllamaModel: "mistral:latest",
            tinyLLMServerURL: "http://localhost:8000",
            tinyChatServerURL: "http://localhost:8000",
            openWebUIServerURL: "http://localhost:8080"
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AIBackendSettings.self, from: data)

        XCTAssertEqual(decoded.selectedBackend, .ollama)
        XCTAssertEqual(decoded.ollamaBaseURL, "http://localhost:11434")
        XCTAssertEqual(decoded.selectedOllamaModel, "mistral:latest")
    }
}

final class AIBackendErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertNotNil(AIBackendError.noBackendAvailable.errorDescription)
        XCTAssertNotNil(AIBackendError.invalidConfiguration.errorDescription)
        XCTAssertNotNil(AIBackendError.invalidState.errorDescription)
        XCTAssertNotNil(AIBackendError.generationFailed("test").errorDescription)
        XCTAssertTrue(AIBackendError.generationFailed("test failure").errorDescription!.contains("test failure"))
    }
}

// MARK: - Server Discovery Model Tests

final class DiscoveredServerTests: XCTestCase {

    func testEquality() {
        let server1 = DiscoveredServer(name: "Ollama on 192.168.1.5", host: "192.168.1.5", port: 11434, type: .ollama)
        let server2 = DiscoveredServer(name: "Different Name", host: "192.168.1.5", port: 11434, type: .ollama)
        XCTAssertEqual(server1, server2, "Servers with same host and port should be equal")
    }

    func testInequality() {
        let server1 = DiscoveredServer(name: "Ollama", host: "192.168.1.5", port: 11434, type: .ollama)
        let server2 = DiscoveredServer(name: "OpenWebUI", host: "192.168.1.5", port: 8080, type: .openwebui)
        XCTAssertNotEqual(server1, server2, "Servers with different ports should not be equal")
    }

    func testHashable() {
        let server1 = DiscoveredServer(name: "A", host: "192.168.1.5", port: 11434, type: .ollama)
        let server2 = DiscoveredServer(name: "B", host: "192.168.1.5", port: 11434, type: .ollama)

        var set = Set<DiscoveredServer>()
        set.insert(server1)
        set.insert(server2)
        XCTAssertEqual(set.count, 1, "Duplicate servers should be deduplicated in Set")
    }
}

// MARK: - AIServerType Tests

final class AIServerTypeTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(AIServerType.allCases.count, 2)
        XCTAssertEqual(AIServerType.ollama.rawValue, "Ollama")
        XCTAssertEqual(AIServerType.openwebui.rawValue, "OpenWebUI")
    }
}

// MARK: - Security Tests

final class SecurityTests: XCTestCase {

    func testNoHardcodedAPIKeys() {
        // Scan all Swift source files for common API key patterns
        let patterns = [
            "sk-[a-zA-Z0-9]{20,}",
            "AKIA[A-Z0-9]{16}",
            "ghp_[a-zA-Z0-9]{36}",
            "xox[bpoas]-[a-zA-Z0-9-]+",
            "Bearer [a-zA-Z0-9._-]{20,}",
        ]

        let sourceFiles = findSwiftFiles(in: "/Volumes/Data/xcode/BlompieTV/BlompieTV")

        for file in sourceFiles {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for pattern in patterns {
                let regex = try? NSRegularExpression(pattern: pattern)
                let matches = regex?.matches(in: content, range: NSRange(content.startIndex..., in: content)) ?? []
                XCTAssertEqual(matches.count, 0, "Potential hardcoded secret found in \(file) matching pattern: \(pattern)")
            }
        }
    }

    func testNovaAPIServerBindsToLoopback() {
        // The Nova API server should only bind to 127.0.0.1
        let serverFile = "/Volumes/Data/xcode/BlompieTV/BlompieTV/NovaAPIServer.swift"
        guard let content = try? String(contentsOfFile: serverFile, encoding: .utf8) else {
            XCTFail("Could not read NovaAPIServer.swift")
            return
        }

        XCTAssertTrue(content.contains("127.0.0.1"), "Nova API server should bind to loopback only")
        XCTAssertFalse(content.contains("0.0.0.0"), "Nova API server must NOT bind to all interfaces")
    }

    func testServerPortIsCorrect() {
        // BlompieTV should use port 37427
        let serverFile = "/Volumes/Data/xcode/BlompieTV/BlompieTV/NovaAPIServer.swift"
        guard let content = try? String(contentsOfFile: serverFile, encoding: .utf8) else {
            XCTFail("Could not read NovaAPIServer.swift")
            return
        }

        XCTAssertTrue(content.contains("37427"), "BlompieTV should use designated port 37427")
    }

    func testNoSensitiveDataInUserDefaults() {
        // Verify no passwords or tokens are stored with obvious key names
        let sensitiveKeyPatterns = ["password", "token", "secret", "apiKey", "api_key"]

        let sourceFiles = findSwiftFiles(in: "/Volumes/Data/xcode/BlompieTV/BlompieTV")

        for file in sourceFiles {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            // Only check UserDefaults key strings
            let userDefaultsPattern = try? NSRegularExpression(pattern: "UserDefaults.*forKey:\\s*\"([^\"]+)\"")
            let matches = userDefaultsPattern?.matches(in: content, range: NSRange(content.startIndex..., in: content)) ?? []

            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    let key = String(content[range]).lowercased()
                    for sensitive in sensitiveKeyPatterns {
                        XCTAssertFalse(key.contains(sensitive), "UserDefaults key '\(key)' in \(file) may contain sensitive data - use Keychain instead")
                    }
                }
            }
        }
    }

    // MARK: - Helper

    private func findSwiftFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return [] }
        var files: [String] = []
        while let path = enumerator.nextObject() as? String {
            if path.hasSuffix(".swift") {
                files.append("\(directory)/\(path)")
            }
        }
        return files
    }
}

// MARK: - GameState Codable Tests

final class GameStateTests: XCTestCase {

    func testGameStateCodable() throws {
        let messages = [GameMessage(text: "Welcome")]
        let history = [OllamaMessage(role: "system", content: "You are a game master")]
        let state = GameState(
            messages: messages,
            conversationHistory: history,
            currentActions: ["Look", "Go north"],
            slotName: "autosave",
            savedDate: Date()
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)

        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.conversationHistory.count, 1)
        XCTAssertEqual(decoded.currentActions, ["Look", "Go north"])
        XCTAssertEqual(decoded.slotName, "autosave")
    }
}

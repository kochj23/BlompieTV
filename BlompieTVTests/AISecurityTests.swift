//
//  AISecurityTests.swift
//  BlompieTVTests
//
//  Security: API keys live only in the Keychain under BlompieTV's own service
//  names, are never written to UserDefaults, are never sent over http, and are
//  never sent to backends that don't need them. Source scans for env-var keys.
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import XCTest
@testable import BlompieTV

@MainActor
final class AISecurityTests: XCTestCase {

    func testKeychainServicesBelongToBlompieTV() {
        XCTAssertEqual(OpenRouterProvider.keychainService, "com.jordankoch.BlompieTV.openrouter")
        XCTAssertFalse(OpenRouterProvider.keychainService.contains("aistudio"))
        XCTAssertEqual(LLMBalancerManager.shared.openRouterKeychain.service, "com.jordankoch.BlompieTV.openrouter")
        XCTAssertEqual(LLMBalancerManager.shared.openAIKeychain.service, "com.jordankoch.BlompieTV.openai")
        XCTAssertEqual(OpenRouterProvider.title, "BlompieTV")
        XCTAssertTrue(OpenRouterProvider.referer.hasSuffix("/BlompieTV"))
    }

    func testKeychainRoundTripUnderTestService() {
        let store = KeychainStore(service: "com.jordankoch.BlompieTV.tests.\(UUID().uuidString)")
        defer { store.delete() }
        XCTAssertNil(store.get())
        XCTAssertTrue(store.set("first"))
        XCTAssertEqual(store.get(), "first")
        XCTAssertTrue(store.set("second"), "update in place")
        XCTAssertEqual(store.get(), "second")
        XCTAssertTrue(store.delete())
        XCTAssertFalse(store.hasValue)
        XCTAssertTrue(store.delete(), "deleting nothing is fine")
    }

    func testKeysNeverReachUserDefaults() throws {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        let secret = "sk-test-\(UUID().uuidString)"
        f.manager.setAPIKey(secret, for: .openRouter)
        f.manager.setAPIKey(secret, for: .openAI)
        f.manager.selectedBackend = .openRouter
        f.manager.saveSettings()
        let everything = "\(f.defaults.dictionaryRepresentation())"
        XCTAssertFalse(everything.contains(secret))
        let blob = String(data: try JSONEncoder().encode(f.manager.persisted), encoding: .utf8)!
        XCTAssertFalse(blob.contains(secret))
        XCTAssertTrue(f.manager.hasOpenRouterKey)
    }

    func testClearingAKeyDeletesIt() {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        f.manager.setAPIKey("abc", for: .openAI)
        XCTAssertTrue(f.manager.hasOpenAIKey)
        f.manager.setAPIKey("   ", for: .openAI)
        XCTAssertFalse(f.manager.hasOpenAIKey)
        XCTAssertNil(f.manager.openAIKeychain.get())
    }

    func testKeyIsNeverSentOverHTTP() async {
        let f = AIFixture { _ in (200, Reply.openAI("x")) }
        defer { f.tearDown() }
        f.manager.setAPIKey("secret-key", for: .openAI)
        f.manager.openAIBaseURL = "http://api.example.com/v1"
        f.manager.selectedBackend = .openAI
        XCTAssertFalse(f.manager.isConfigured(.openAI))
        _ = try? await f.manager.generate(messages: [], prompt: "x")
        XCTAssertTrue(f.http.requests.isEmpty, "nothing sent")
        XCTAssertThrowsError(try f.manager.buildRequest(
            backend: .openAI, model: "m", messages: [], systemPrompt: nil, prompt: "x", temperature: 0.5, maxTokens: 10)) {
            XCTAssertEqual($0 as? LLMError, .insecureEndpoint)
        }
    }

    func testRequestBuilderRefusesAuthorizationOverHTTP() {
        XCTAssertThrowsError(try OpenAICompatibleRequest.build(
            endpoint: "http://evil.example/v1/chat/completions", model: "m", messages: [],
            temperature: 0.1, maxTokens: 1, stream: false, headers: ["Authorization": "Bearer k"])) {
            XCTAssertEqual($0 as? LLMError, .insecureEndpoint)
        }
        XCTAssertNoThrow(try OpenAICompatibleRequest.build(
            endpoint: "http://192.168.1.5:8000/v1/chat/completions", model: "m", messages: [],
            temperature: 0.1, maxTokens: 1, stream: false, headers: [:]), "LAN without a key is fine")
    }

    func testLocalBackendsNeverReceiveKeys() throws {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        f.manager.setAPIKey("or-key", for: .openRouter)
        f.manager.setAPIKey("oa-key", for: .openAI)
        for b in [LLMBackendType.ollama, .tinyLLM, .tinyChat, .openWebUI, .novaGateway] {
            let r = try f.manager.buildRequest(backend: b, model: "m", messages: [], systemPrompt: nil,
                                               prompt: "x", temperature: 0.5, maxTokens: 10)
            XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"), b.rawValue)
            let body = String(data: r.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertFalse(body.contains("or-key") || body.contains("oa-key"), b.rawValue)
        }
    }

    func testStatusProbesNeverSpendCloudKeys() async {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        f.manager.setAPIKey("or-key", for: .openRouter)
        await f.manager.refreshStatus()
        XCTAssertFalse(f.http.requests.contains { $0.url?.host == "openrouter.ai" })
    }

    func testAIOffSendsNoGameTextAnywhere() async {
        let f = AIFixture(handler: ollamaUp())
        defer { f.tearDown() }
        let e = f.engine(aiEnabled: false)
        e.startNewGame()
        await e.finishTurn()
        e.performAction("Follow the bell")
        await e.finishTurn()
        XCTAssertTrue(f.http.requests.isEmpty)
    }

    func testNoKeysFromEnvironmentOrDefaultsInSource() throws {
        let files = try FileManager.default.subpathsOfDirectory(atPath: SecurityTests.appSourceDir)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOfFile: "\(SecurityTests.appSourceDir)/\(file)", encoding: .utf8)
            XCTAssertFalse(text.contains("processInfo.environment"), "\(file) reads the environment")
            XCTAssertFalse(text.contains("com.jkoch.aistudio") && !file.hasSuffix("OpenRouterProvider.swift"),
                           "\(file) uses AIStudio's Keychain service")
            XCTAssertNil(text.range(of: #"(?i)defaults\.set\([^)]*(apikey|api_key|secret|token)"#, options: .regularExpression),
                         "\(file) writes a secret-looking value to UserDefaults")
        }
    }
}

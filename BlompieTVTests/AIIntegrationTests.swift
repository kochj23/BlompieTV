//
//  AIIntegrationTests.swift
//  BlompieTVTests
//
//  Integration: LLMBalancerManager end to end over a stub HTTP transport
//  (auto failover order, explicit backends, cloud auth, status, model lists,
//  balancer pool, Keychain migration). No real network.
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import XCTest
@testable import BlompieTV

@MainActor
final class AIIntegrationTests: XCTestCase {

    func testAutoPicksFirstReachableBackendInOrder() async throws {
        // Ollama down; TinyChat (next in order) up.
        let f = AIFixture { request in
            switch request.url?.path {
            case "/api/health": return (200, Reply.ok)
            case "/api/chat/stream": return (200, Data("You arrive at a quiet pier.".utf8))
            default: throw URLError(.cannotConnectToHost)
            }
        }
        defer { f.tearDown() }
        let text = try await f.manager.generate(messages: [], prompt: "look")
        XCTAssertEqual(text, "You arrive at a quiet pier.")
        XCTAssertEqual(f.manager.activeBackend, .tinyChat)
        XCTAssertEqual(f.manager.backendHealth[.ollama], false)
        // Ollama was probed before TinyChat was used.
        let paths = f.http.requests.compactMap { $0.url?.path }
        XCTAssertLessThan(paths.firstIndex(of: "/api/tags")!, paths.firstIndex(of: "/api/chat/stream")!)
    }

    func testAutoFailsOverWhenAReachableBackendErrors() async throws {
        let f = AIFixture { request in
            switch request.url?.path {
            case "/api/tags": return (200, Reply.tags(["mistral"]))
            case "/api/chat": return (500, Data())
            case "/api/health": return (200, Reply.ok)
            case "/api/chat/stream": return (200, Reply.openAI("A gnome greets you."))
            default: throw URLError(.cannotConnectToHost)
            }
        }
        defer { f.tearDown() }
        let text = try await f.manager.generate(messages: [], prompt: "look")
        XCTAssertEqual(text, "A gnome greets you.")
        XCTAssertEqual(f.http.count(path: "/api/chat"), 2, "bounded retry on Ollama, then failover")
        XCTAssertEqual(f.manager.activeBackend, .tinyChat)
        XCTAssertEqual(f.manager.backendHealth[.ollama], false)
    }

    func testExplicitBackendNeverFailsOver() async {
        let f = AIFixture { request in
            if request.url?.path == "/api/health" { return (200, Reply.ok) }
            return (500, Data())
        }
        defer { f.tearDown() }
        f.manager.selectedBackend = .ollama
        do { _ = try await f.manager.generate(messages: [], prompt: "x"); XCTFail("expected throw") } catch {}
        XCTAssertTrue(f.http.requests.allSatisfy { $0.url?.port == 11434 }, "only Ollama was contacted")
        XCTAssertNil(f.manager.activeBackend)
        XCTAssertEqual(f.manager.statusText, "Ollama unreachable")
    }

    func testNothingReachableThrowsAndReportsOffline() async {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        do {
            _ = try await f.manager.generate(messages: [], prompt: "x")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? LLMError, .noBackendAvailable)
        }
        XCTAssertNil(f.manager.activeBackend)
        XCTAssertEqual(f.manager.statusText, "No backend reachable")
        XCTAssertEqual(f.http.count(path: "/api/chat"), 0, "unreachable backends are skipped, not called")
    }

    func testHealthIsCachedBetweenTurns() async throws {
        let f = AIFixture(handler: ollamaUp("You walk on."))
        defer { f.tearDown() }
        _ = try await f.manager.generate(messages: [], prompt: "a")
        _ = try await f.manager.generate(messages: [], prompt: "b")
        XCTAssertEqual(f.http.count(path: "/api/tags"), 1)
        XCTAssertEqual(f.http.count(path: "/api/chat"), 2)
    }

    func testEachBackendHitsItsEndpoint() async throws {
        let expected: [LLMBackendType: String] = [
            .ollama: "/api/chat", .tinyLLM: "/v1/chat/completions", .tinyChat: "/api/chat/stream",
            .openWebUI: "/api/chat/completions", .novaGateway: "/v1/chat/completions"
        ]
        for (backend, path) in expected {
            let f = AIFixture { _ in (200, backend == .ollama ? Reply.ollama("Ok then.") : Reply.openAI("Ok then.")) }
            f.manager.selectedBackend = backend
            let text = try await f.manager.generate(messages: [], prompt: "x")
            XCTAssertEqual(text, "Ok then.", backend.rawValue)
            XCTAssertEqual(f.http.requests.last?.url?.path, path, backend.rawValue)
            XCTAssertNil(f.http.requests.last?.value(forHTTPHeaderField: "Authorization"), backend.rawValue)
            f.tearDown()
        }
    }

    func testOpenRouterSendsBearerAndBlompieAttribution() async throws {
        let f = AIFixture { _ in (200, Reply.openAI("Frontier says hi.")) }
        defer { f.tearDown() }
        XCTAssertTrue(f.manager.setAPIKey("test-or-key", for: .openRouter))
        f.manager.selectedBackend = .openRouter
        f.manager.setModel("anthropic/claude-sonnet-4.5", for: .openRouter)
        let text = try await f.manager.generate(messages: [], prompt: "x")
        XCTAssertEqual(text, "Frontier says hi.")
        let req = try XCTUnwrap(f.http.requests.last)
        XCTAssertEqual(req.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-or-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Title"), "BlompieTV")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "anthropic/claude-sonnet-4.5")
    }

    func testOpenAIUsesConfiguredHTTPSBase() async throws {
        let f = AIFixture { _ in (200, Reply.openAI("Sure.")) }
        defer { f.tearDown() }
        f.manager.setAPIKey("test-oa-key", for: .openAI)
        f.manager.openAIBaseURL = "https://llm.example.com/v1"
        f.manager.selectedBackend = .openAI
        _ = try await f.manager.generate(messages: [], prompt: "x")
        XCTAssertEqual(f.http.requests.last?.url?.absoluteString, "https://llm.example.com/v1/chat/completions")
        XCTAssertEqual(f.http.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer test-oa-key")
    }

    func testSelectedCloudBackendWithoutKeyThrowsMissingKey() async {
        let f = AIFixture { _ in (200, Reply.openAI("x")) }
        defer { f.tearDown() }
        f.manager.selectedBackend = .openRouter
        do {
            _ = try await f.manager.generate(messages: [], prompt: "x")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? LLMError, .missingAPIKey)
        }
        XCTAssertTrue(f.http.requests.isEmpty)
    }

    func testRefreshStatusFindsFirstReachable() async {
        let f = AIFixture(handler: ollamaUp())
        defer { f.tearDown() }
        let active = await f.manager.refreshStatus()
        XCTAssertEqual(active, .ollama)
        XCTAssertEqual(f.manager.statusText, "Ollama online")
        XCTAssertEqual(f.manager.backendHealth[.ollama], true)
        XCTAssertEqual(f.manager.backendHealth[.tinyLLM], false)
        XCTAssertEqual(f.manager.backendHealth[.openRouter], false, "no key")
    }

    func testRefreshAvailableModels() async {
        let f = AIFixture(handler: ollamaUp())
        defer { f.tearDown() }
        await f.manager.refreshAvailableModels()
        XCTAssertEqual(f.manager.availableModels, ["mistral", "llama3.2"])

        f.http.handler = everythingDown
        await f.manager.refreshAvailableModels()
        XCTAssertEqual(f.manager.availableModels, ["mistral"], "never empty: falls back to the current model")
    }

    func testNovaGatewayBalancerPoolAnswersFirst() async throws {
        let f = AIFixture { request in
            if request.url?.port == 18792 {
                return request.url?.path == "/v1/models" ? (200, Reply.modelList(["nova"])) : (200, Reply.openAI("Nova narrates."))
            }
            throw URLError(.cannotConnectToHost)
        }
        defer { f.tearDown() }
        f.manager.useNovaGateway = true
        let text = try await f.manager.generate(messages: [], prompt: "x")
        XCTAssertEqual(text, "Nova narrates.")
        XCTAssertEqual(f.manager.activeBackend, .novaGateway)
    }

    func testBalancerPoolFailureFallsBackToChain() async throws {
        // Nova pool member is down; Ollama in the Auto chain answers.
        let f = AIFixture(handler: ollamaUp("Back on solid ground."))
        defer { f.tearDown() }
        f.manager.useNovaGateway = true
        let text = try await f.manager.generate(messages: [], prompt: "x")
        XCTAssertEqual(text, "Back on solid ground.")
        XCTAssertEqual(f.manager.activeBackend, .ollama)
    }

    func testOpenRouterKeyMigratesFromLegacyServiceOnce() {
        let legacyService = "com.jordankoch.BlompieTV.tests.legacy.\(UUID().uuidString)"
        let legacy = KeychainStore(service: legacyService)
        XCTAssertTrue(legacy.set("legacy-key"))
        let f = AIFixture(legacyOpenRouterService: legacyService, handler: everythingDown)
        defer { f.tearDown(); legacy.delete() }
        XCTAssertTrue(f.manager.hasOpenRouterKey)
        XCTAssertEqual(f.manager.openRouterAPIKey(), "legacy-key")
        XCTAssertNil(legacy.get(), "legacy item removed after the copy")

        // A key already stored under the new service is never overwritten.
        XCTAssertTrue(legacy.set("older"))
        XCTAssertFalse(f.manager.openRouterKeychain.migrate(from: legacy))
        XCTAssertEqual(f.manager.openRouterAPIKey(), "legacy-key")
    }
}

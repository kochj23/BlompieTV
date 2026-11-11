//
//  AIPerformanceTests.swift
//  BlompieTVTests
//
//  Performance: the per-turn AI work stays cheap, and a dead network costs a
//  bounded amount of time (timeouts on every request, bounded retries/backoff).
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import XCTest
@testable import BlompieTV

final class AIPerformanceTests: XCTestCase {

    private static let bigReply: String = {
        let story = (0..<120).map { "Line \($0): you enter a hall where a merchant named Bram waves at you. " }.joined(separator: "\n")
        return "<think>\(String(repeating: "hmm ", count: 500))</think>\n" + story + "\nACTIONS: Wave back | Trade | Leave | Look around"
    }()

    func testParseAndValidateLargeReplyIsFast() {
        let start = Date()
        for _ in 0..<200 {
            let clean = NarrationValidator.sanitize(Self.bigReply)!
            let parsed = GameEngine.parseResponse(clean)
            _ = NarrationValidator.sanitizeActions(parsed.actions)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3.0, "200 large replies")
    }

    func testParseMeasure() {
        measure { _ = GameEngine.parseResponse(NarrationValidator.sanitize(Self.bigReply)!) }
    }

    func testScriptedNarratorIsFast() {
        let start = Date()
        var scene = ScriptedNarrator.startSceneID
        for i in 0..<20_000 {
            let actions = ScriptedNarrator.scene(scene).actions
            scene = ScriptedNarrator.respond(to: actions[i % actions.count], in: scene).sceneID
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testBalancerSelectionScales() {
        let pool = (0..<2000).map { DiscoveredModel(modelName: "m\($0)", backend: .ollama, endpoint: "e") }
        let lb = LoadBalancer()
        let start = Date()
        for _ in 0..<500 { _ = lb.next(pool: pool, policy: .leastBusy) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }

    @MainActor
    func testEveryRequestCarriesATimeout() async {
        let f = AIFixture(handler: ollamaUp())
        defer { f.tearDown() }
        _ = try? await f.manager.generate(messages: [], prompt: "x")
        await f.manager.refreshStatus()
        XCTAssertFalse(f.http.requests.isEmpty)
        for r in f.http.requests {
            XCTAssertGreaterThan(r.timeoutInterval, 0)
            if r.httpMethod == "POST" {
                XCTAssertLessThanOrEqual(r.timeoutInterval, f.manager.requestTimeout)
            } else {
                XCTAssertLessThanOrEqual(r.timeoutInterval, f.manager.probeTimeout, "probes are short")
            }
        }
    }

    @MainActor
    func testDeadNetworkCostIsBounded() async {
        // Every backend "reachable" but failing with 503: each is tried at most
        // maxAttempts times and the total backoff is bounded.
        let f = AIFixture { _ in (503, Data()) }
        defer { f.tearDown() }
        f.manager.setAPIKey("k", for: .openRouter)
        f.manager.setAPIKey("k", for: .openAI)
        _ = try? await f.manager.generate(messages: [], prompt: "x")
        let posts = f.http.requests.filter { $0.httpMethod == "POST" }.count
        let configured = f.manager.candidateChain.filter { f.manager.isConfigured($0) }.count
        XCTAssertLessThanOrEqual(posts, configured * f.manager.retryPolicy.maxAttempts)
        XCTAssertLessThanOrEqual(f.sleeps.sleeps.reduce(0, +),
                                 Double(configured) * f.manager.retryPolicy.worstCaseSleep + 0.001)
    }

    @MainActor
    func testScriptedFallbackTurnIsImmediate() async {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        let e = f.engine()
        let start = Date()
        e.startNewGame()
        await e.finishTurn()
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
        XCTAssertEqual(e.lastNarrationSource, .scriptedFallback)
    }
}

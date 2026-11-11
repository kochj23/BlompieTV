//
//  RetryTests.swift
//  BlompieTVTests (ported from Blompie/BlompieTests/RetryTests.swift)
//
//  Retry / failover tests: the balancer's `firstSuccess` dispatch loop (drop a
//  failing model, retry the next healthy one, rethrow only when all fail),
//  in-flight bookkeeping across failed attempts, and round-robin fairness
//  after a failover.
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import XCTest
@testable import BlompieTV

private struct InjectedFailure: Error, Equatable { let model: String }

final class RetryTests: XCTestCase {

    private func pool(_ names: [String]) -> [DiscoveredModel] {
        names.map { DiscoveredModel(modelName: $0, backend: .ollama, endpoint: "http://localhost:11434/api/chat") }
    }

    func testFirstAttemptSuccessDoesNotRetry() async throws {
        let lb = LoadBalancer()
        var tried: [String] = []
        let result = try await lb.firstSuccess(pool: pool(["a", "b", "c"]), policy: .roundRobin) { m -> String in
            tried.append(m.modelName); return "ok-\(m.modelName)"
        }
        XCTAssertEqual(result, "ok-a")
        XCTAssertEqual(tried, ["a"])
    }

    func testFailingModelIsDroppedAndNextIsTried() async throws {
        let lb = LoadBalancer()
        var tried: [String] = []
        let result = try await lb.firstSuccess(pool: pool(["a", "b", "c"]), policy: .leastBusy) { m -> String in
            tried.append(m.modelName)
            if m.modelName != "c" { throw InjectedFailure(model: m.modelName) }
            return "ok-c"
        }
        XCTAssertEqual(result, "ok-c")
        XCTAssertEqual(tried, ["a", "b", "c"], "each model tried exactly once, in order")
    }

    func testAllFailRethrowsLastError() async {
        let lb = LoadBalancer()
        var attempts = 0
        do {
            _ = try await lb.firstSuccess(pool: pool(["a", "b"]), policy: .leastBusy) { m -> String in
                attempts += 1; throw InjectedFailure(model: m.modelName)
            }
            XCTFail("expected rethrow")
        } catch {
            XCTAssertEqual(error as? InjectedFailure, InjectedFailure(model: "b"))
        }
        XCTAssertEqual(attempts, 2, "bounded: no model retried twice")
    }

    func testUnhealthyModelsAreNeverAttempted() async throws {
        let lb = LoadBalancer()
        let p = pool(["a", "b", "c"])
        var tried: [String] = []
        let health = [p[0].id: false, p[1].id: false]
        let result = try await lb.firstSuccess(pool: p, health: health, policy: .roundRobin) { m -> String in
            tried.append(m.modelName); return m.modelName
        }
        XCTAssertEqual(result, "c")
        XCTAssertEqual(tried, ["c"])
    }

    func testNoHealthyModelReturnsNilWithoutAttempting() async throws {
        let lb = LoadBalancer()
        let p = pool(["a"])
        var attempts = 0
        let result = try await lb.firstSuccess(pool: p, health: [p[0].id: false], policy: .leastBusy) { _ -> String in
            attempts += 1; return "x"
        }
        XCTAssertNil(result)
        XCTAssertEqual(attempts, 0)
        let empty: String? = try await lb.firstSuccess(pool: [], policy: .roundRobin) { _ in "x" }
        XCTAssertNil(empty)
    }

    func testInFlightCountsReturnToZeroAfterFailures() async throws {
        let lb = LoadBalancer()
        _ = try? await lb.firstSuccess(pool: pool(["a", "b"]), policy: .leastBusy) { m -> String in
            throw InjectedFailure(model: m.modelName)
        }
        XCTAssertTrue(lb.inFlight.values.allSatisfy { $0 == 0 }, "failed attempts must be checked back in")
        _ = try await lb.firstSuccess(pool: pool(["a"]), policy: .leastBusy) { _ in "ok" }
        XCTAssertTrue(lb.inFlight.values.allSatisfy { $0 == 0 })
    }

    func testModelIsCheckedOutDuringAttempt() async throws {
        let lb = LoadBalancer()
        let p = pool(["a"])
        _ = try await lb.firstSuccess(pool: p, policy: .leastBusy) { m -> Int in
            XCTAssertEqual(lb.inFlight[m.id], 1)
            return 1
        }
        XCTAssertEqual(lb.inFlight[p[0].id], 0)
    }

    func testRoundRobinContinuesFairlyAfterFailover() async throws {
        let lb = LoadBalancer()
        let p = pool(["a", "b", "c"])
        var first: [String] = []
        // First call: "a" fails, "b" succeeds.
        _ = try await lb.firstSuccess(pool: p, policy: .roundRobin) { m -> String in
            first.append(m.modelName)
            if m.modelName == "a" { throw InjectedFailure(model: "a") }
            return m.modelName
        }
        XCTAssertEqual(first.count, 2)
        // Subsequent independent calls keep cycling the full pool (a failure is not permanent).
        var seen = Set<String>()
        for _ in 0..<3 {
            if let r = try await lb.firstSuccess(pool: p, policy: .roundRobin, attempt: { m in m.modelName }) { seen.insert(r) }
        }
        XCTAssertEqual(seen, ["a", "b", "c"])
    }

    // MARK: - Retry helper (GTNW Retry.swift)

    func testRetryPolicyBackoffIsBoundedAndExponential() {
        let p = RetryPolicy(maxAttempts: 4, baseDelay: 0.5, multiplier: 2, maxDelay: 1.5)
        XCTAssertEqual(p.delay(afterAttempt: 1), 0.5)
        XCTAssertEqual(p.delay(afterAttempt: 2), 1.0)
        XCTAssertEqual(p.delay(afterAttempt: 3), 1.5, "capped at maxDelay")
        XCTAssertEqual(p.worstCaseSleep, 3.0)
        XCTAssertEqual(RetryPolicy.none.worstCaseSleep, 0)
    }

    func testRetryRunStopsAfterMaxAttempts() async {
        var attempts = 0
        let recorder = SleepRecorder()
        do {
            _ = try await Retry.run("t", policy: RetryPolicy(maxAttempts: 3, baseDelay: 0.1), sleep: recorder.sleeper) { () async throws -> Int in
                attempts += 1; throw InjectedFailure(model: "x")
            }
            XCTFail("expected throw")
        } catch {}
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(recorder.sleeps.count, 2)
    }

    func testRetryRunFailsFastOnNonRetryable() async {
        var attempts = 0
        do {
            _ = try await Retry.run("t", sleep: { _ in }, shouldRetry: { _ in false }) { () async throws -> Int in
                attempts += 1; throw InjectedFailure(model: "x")
            }
        } catch {}
        XCTAssertEqual(attempts, 1)
    }

    func testRetryRunSucceedsAfterTransientFailure() async throws {
        var attempts = 0
        let v = try await Retry.run("t", sleep: { _ in }) { () async throws -> Int in
            attempts += 1
            if attempts == 1 { throw URLError(.timedOut) }
            return 7
        }
        XCTAssertEqual(v, 7)
        XCTAssertEqual(attempts, 2)
    }

    // MARK: - Manager retry classification and bounded retries

    func testRetryableClassification() {
        XCTAssertTrue(LLMBalancerManager.isRetryable(LLMError.httpError(500)))
        XCTAssertTrue(LLMBalancerManager.isRetryable(LLMError.httpError(429)))
        XCTAssertTrue(LLMBalancerManager.isRetryable(LLMError.httpError(408)))
        XCTAssertFalse(LLMBalancerManager.isRetryable(LLMError.httpError(401)))
        XCTAssertFalse(LLMBalancerManager.isRetryable(LLMError.httpError(404)))
        XCTAssertFalse(LLMBalancerManager.isRetryable(LLMError.insecureEndpoint))
        XCTAssertFalse(LLMBalancerManager.isRetryable(LLMError.missingAPIKey))
        XCTAssertFalse(LLMBalancerManager.isRetryable(LLMError.invalidURL))
        XCTAssertTrue(LLMBalancerManager.isRetryable(URLError(.timedOut)))
        XCTAssertFalse(LLMBalancerManager.isRetryable(URLError(.cancelled)))
        XCTAssertFalse(LLMBalancerManager.isRetryable(CancellationError()))
    }

    @MainActor
    func testTransient5xxIsRetriedThenSucceeds() async throws {
        let calls = StubCounter()
        let f = AIFixture { request in
            guard request.url?.path == "/api/chat" else { throw URLError(.cannotConnectToHost) }
            return calls.next() == 1 ? (503, Data()) : (200, Reply.ollama("You enter a hall."))
        }
        defer { f.tearDown() }
        f.manager.selectedBackend = .ollama
        let text = try await f.manager.generate(messages: [], prompt: "go")
        XCTAssertEqual(text, "You enter a hall.")
        XCTAssertEqual(f.http.count(path: "/api/chat"), 2)
        XCTAssertEqual(f.sleeps.sleeps, [0.5])
    }

    @MainActor
    func test4xxIsNotRetried() async {
        let f = AIFixture { _ in (404, Data()) }
        defer { f.tearDown() }
        f.manager.selectedBackend = .ollama
        do {
            _ = try await f.manager.generate(messages: [], prompt: "go")
            XCTFail("expected throw")
        } catch {
            if case LLMError.httpError(let code) = error { XCTAssertEqual(code, 404) } else { XCTFail("\(error)") }
        }
        XCTAssertEqual(f.http.count(path: "/api/chat"), 1)
        XCTAssertTrue(f.sleeps.sleeps.isEmpty)
    }

    @MainActor
    func testRetriesAreBoundedPerBackend() async {
        let f = AIFixture { _ in (500, Data()) }
        defer { f.tearDown() }
        f.manager.selectedBackend = .ollama
        _ = try? await f.manager.generate(messages: [], prompt: "go")
        XCTAssertEqual(f.http.count(path: "/api/chat"), f.manager.retryPolicy.maxAttempts)
    }
}

/// Thread-safe counter for stub handlers.
final class StubCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}

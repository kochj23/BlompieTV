//
//  AITestSupport.swift
//  BlompieTVTests
//
//  Shared fixtures for the AI test suites: a recording stub HTTP transport (no
//  network), isolated UserDefaults suites and per-test Keychain service names.
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import XCTest
@testable import BlompieTV

/// Recording stub for `HTTPTransport`. The handler returns (status, body) or throws.
final class StubHTTP: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var handlerStorage: Handler

    init(_ handler: @escaping Handler) { handlerStorage = handler }

    var handler: Handler {
        get { lock.lock(); defer { lock.unlock() }; return handlerStorage }
        set { lock.lock(); handlerStorage = newValue; lock.unlock() }
    }

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }

    func count(path: String) -> Int { requests.filter { $0.url?.path == path }.count }

    var transport: HTTPTransport {
        { [self] request in
            lock.lock(); recorded.append(request); let h = handlerStorage; lock.unlock()
            let (code, data) = try h(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }
}

enum Reply {
    static func ollama(_ text: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": text], "done": true])
    }
    static func openAI(_ text: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": text]]]])
    }
    static func tags(_ names: [String]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["models": names.map { ["name": $0] }])
    }
    static func modelList(_ ids: [String]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["data": ids.map { ["id": $0] }])
    }
    static let ok = Data("{}".utf8)
    static let story = """
    You step through the door into a forest clearing. An old wizard named Marrow sits by a fire.
    ACTIONS: Greet the wizard | Sit by the fire | Look around
    """
}

/// Records the backoff sleeps instead of sleeping.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []
    var sleeps: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return values }
    var sleeper: RetrySleeper { { [self] s in lock.lock(); values.append(s); lock.unlock() } }
}

@MainActor
struct AIFixture {
    let manager: LLMBalancerManager
    let http: StubHTTP
    let defaults: UserDefaults
    let suiteName: String
    let keychainPrefix: String
    let sleeps: SleepRecorder

    /// A manager wired to a stub transport, its own defaults suite and its own Keychain services.
    init(legacyOpenRouterService: String? = nil, keychainPrefix: String? = nil, handler: @escaping StubHTTP.Handler) {
        suiteName = "BlompieTVTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        self.keychainPrefix = keychainPrefix ?? "com.jordankoch.BlompieTV.tests.\(UUID().uuidString)"
        http = StubHTTP(handler)
        sleeps = SleepRecorder()
        manager = LLMBalancerManager(
            settingsKey: "AITestSettings",
            defaults: defaults,
            keychainServicePrefix: self.keychainPrefix,
            legacyOpenRouterService: legacyOpenRouterService,
            transport: http.transport,
            sleep: sleeps.sleeper
        )
    }

    func engine(aiEnabled: Bool = true) -> GameEngine {
        let engine = GameEngine(ai: manager, defaults: defaults, checkBackendsOnLaunch: false)
        engine.streamingEnabled = false // streaming uses URLSession directly; tests stay offline
        engine.aiEnabled = aiEnabled
        return engine
    }

    func tearDown() {
        manager.setAPIKey("", for: .openRouter)
        manager.setAPIKey("", for: .openAI)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Handler where nothing is reachable.
let everythingDown: StubHTTP.Handler = { _ in throw URLError(.cannotConnectToHost) }

/// Handler for a healthy Ollama that answers `text` (everything else down).
func ollamaUp(_ text: String = Reply.story) -> StubHTTP.Handler {
    { request in
        switch request.url?.path {
        case "/api/tags": return (200, Reply.tags(["mistral", "llama3.2"]))
        case "/api/chat": return (200, Reply.ollama(text))
        default: throw URLError(.cannotConnectToHost)
        }
    }
}

extension GameEngine {
    /// Wait for the current turn to finish.
    func finishTurn() async { await turnTask?.value }
}

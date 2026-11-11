//
//  LLMBalancerManager.swift
//  BlompieTV
//
//  The canonical standalone LLM manager for Jordan's games (copy this file plus
//  LLMBalancerTypes / ModelRegistry / OpenRouterProvider / KeychainStore / Retry).
//  It is game-agnostic: no prompts, no game state, no game UI.
//
//  What it does:
//   • Backend picker over the canonical `LLMBackendType`, including `.auto`,
//     which tries every configured, reachable backend in the fixed
//     `LLMBackendType.autoOrder` (health cached for `healthTTL` seconds).
//   • Per-backend editable endpoint URLs and per-backend model choice, persisted
//     as one Codable blob in UserDefaults (no secrets in it).
//   • API keys (OpenRouter, OpenAI) only in the Keychain under this app's own
//     service names; a request that carries a key is refused unless it is https.
//   • Timeouts on every request, bounded retries (`Retry`, 2 attempts by default,
//     transient errors only), failover to the next backend.
//   • Optional multi-model balancer (all local Ollama models, all OpenRouter
//     frontier models, Nova Gateway) via the pure `LoadBalancer.firstSuccess`.
//     All toggles default OFF. Nova is never required.
//   • Status for the UI: `activeBackend`, per-backend `backendHealth`, `statusText`.
//
//  `generate` throws when nothing answers; the game decides what to do then
//  (BlompieTV falls back to its scripted narrator).
//
//  Author: Jordan Koch
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class LLMBalancerManager: ObservableObject {
    static let shared = LLMBalancerManager()

    // MARK: - Backend choice (persisted)

    /// The backend to use. `.auto` fails over across `LLMBackendType.autoOrder`.
    @Published var selectedBackend: LLMBackendType = .auto {
        didSet { saveSettings(); if oldValue != selectedBackend { activeBackend = nil } }
    }

    // MARK: - Balancer toggles (persisted)

    /// Balance across ALL local models discovered from Ollama `/api/tags`.
    @Published var useAllLocalModels = false {
        didSet { saveSettings() }
    }
    /// Include ALL OpenRouter frontier models (requires a stored API key).
    @Published var enableAllFrontierModels = false {
        didSet { saveSettings() }
    }
    /// Route through Nova Gateway (optional; dropped when unhealthy).
    @Published var useNovaGateway = false {
        didSet { saveSettings() }
    }

    // MARK: - Endpoints (persisted, all editable)

    @Published var ollamaBaseURL = LLMBackendType.ollama.defaultURL {
        didSet { endpointChanged(.ollama) }
    }
    @Published var tinyLLMURL = LLMBackendType.tinyLLM.defaultURL {
        didSet { endpointChanged(.tinyLLM) }
    }
    @Published var tinyChatURL = LLMBackendType.tinyChat.defaultURL {
        didSet { endpointChanged(.tinyChat) }
    }
    @Published var openWebUIURL = LLMBackendType.openWebUI.defaultURL {
        didSet { endpointChanged(.openWebUI) }
    }
    @Published var novaGatewayURL = LLMBackendType.novaGateway.defaultURL {
        didSet { endpointChanged(.novaGateway) }
    }
    /// OpenAI-compatible base URL including `/v1`. Must be https (it carries a key).
    @Published var openAIBaseURL = LLMBackendType.openAI.defaultURL {
        didSet { endpointChanged(.openAI) }
    }

    /// Chosen model per backend (raw value → model id). Missing → `defaultModel`.
    @Published private(set) var models: [String: String] = [:]

    // MARK: - Discovered state (for the settings UI)

    /// The models currently in the enabled, de-duplicated balancer pool.
    @Published private(set) var discoveredModels: [DiscoveredModel] = []
    /// OpenRouter model ids fetched from `/models` (falls back to a popular set).
    @Published private(set) var openRouterModels: [String] = OpenRouterProvider.fallbackModels
    /// Models offered by `modelPickerBackend` (filled by `refreshAvailableModels`).
    @Published private(set) var availableModels: [String] = []
    /// Whether a non-empty OpenRouter key is stored in the Keychain.
    @Published private(set) var hasOpenRouterKey = false
    /// Whether a non-empty OpenAI key is stored in the Keychain.
    @Published private(set) var hasOpenAIKey = false
    /// Live availability of Nova Gateway (kept for the Cloud tab).
    @Published private(set) var isNovaGatewayAvailable = false

    // MARK: - Status

    /// The backend that answered last (or the first reachable one after
    /// `refreshStatus`). `nil` = nothing reachable / not checked yet.
    @Published private(set) var activeBackend: LLMBackendType?
    /// Last probe/call result per backend.
    @Published private(set) var backendHealth: [LLMBackendType: Bool] = [:]
    /// Short human-readable status for the indicator.
    @Published private(set) var statusText = "Not checked"
    @Published private(set) var isCheckingStatus = false

    // MARK: - Balancer

    /// Pure, network-free balancer that spreads work across the enabled pool.
    let balancer = LoadBalancer()
    /// Least-busy mirrors how Nova's gateway spreads load.
    var balancerPolicy: BalancerPolicy = .leastBusy

    /// Keychain-backed store for the OpenRouter API key.
    let openRouterKeychain: KeychainStore
    /// Keychain-backed store for the OpenAI API key.
    let openAIKeychain: KeychainStore

    /// True when any load-balancing toggle is on, so a request is first tried
    /// across the balanced pool.
    var isBalancingEnabled: Bool {
        useAllLocalModels || enableAllFrontierModels || useNovaGateway
    }

    // MARK: - Timeouts / retry (injectable for tests)

    /// Per-request timeout for generation (local models can take a while to load).
    var requestTimeout: TimeInterval = 120
    /// Per-request timeout for health probes and model listing.
    var probeTimeout: TimeInterval = 4
    /// How long a health probe result is trusted by `.auto`.
    var healthTTL: TimeInterval = 30
    /// Bounded retries per backend (transient errors only).
    var retryPolicy = RetryPolicy(maxAttempts: 2, baseDelay: 0.5, multiplier: 2, maxDelay: 2)

    private let transport: HTTPTransport
    private let sleep: RetrySleeper
    private let defaults: UserDefaults
    private let settingsKey: String
    private var healthCheckedAt: [LLMBackendType: Date] = [:]
    private var isLoading = false

    /// - Parameters:
    ///   - settingsKey/defaults: where the (secret-free) settings blob lives.
    ///   - keychainServicePrefix: per-app Keychain prefix; keys live at
    ///     `<prefix>.openrouter` and `<prefix>.openai`.
    ///   - legacyOpenRouterService: an older service to migrate the OpenRouter key from (once).
    ///   - transport/sleep: injectable HTTP + backoff sleep (tests pass stubs).
    init(
        settingsKey: String = "BlompieTVLLMBalancerSettings",
        defaults: UserDefaults = .standard,
        keychainServicePrefix: String = "com.jordankoch.BlompieTV",
        legacyOpenRouterService: String? = OpenRouterProvider.legacyKeychainService,
        transport: HTTPTransport? = nil,
        sleep: @escaping RetrySleeper = Retry.realSleep
    ) {
        self.settingsKey = settingsKey
        self.defaults = defaults
        self.sleep = sleep
        if let transport {
            self.transport = transport
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 300
            let session = URLSession(configuration: config)
            self.transport = { request in try await session.data(for: request) }
        }
        openRouterKeychain = KeychainStore(service: "\(keychainServicePrefix).openrouter")
        openAIKeychain = KeychainStore(service: "\(keychainServicePrefix).openai")
        if let legacyOpenRouterService {
            openRouterKeychain.migrate(from: KeychainStore(service: legacyOpenRouterService))
        }
        loadSettings()
        hasOpenRouterKey = openRouterKeychain.hasValue
        hasOpenAIKey = openAIKeychain.hasValue
    }

    // MARK: - Settings persistence

    struct Persisted: Codable, Equatable {
        var useAllLocalModels: Bool
        var enableAllFrontierModels: Bool
        var useNovaGateway: Bool
        var ollamaBaseURL: String
        var novaGatewayURL: String
        // Added 2026-11 (optional so older blobs still decode).
        var selectedBackend: LLMBackendType?
        var tinyLLMURL: String?
        var tinyChatURL: String?
        var openWebUIURL: String?
        var openAIBaseURL: String?
        var models: [String: String]?
    }

    func loadSettings() {
        isLoading = true
        defer { isLoading = false }
        guard let data = defaults.data(forKey: settingsKey),
              let s = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        useAllLocalModels = s.useAllLocalModels
        enableAllFrontierModels = s.enableAllFrontierModels
        useNovaGateway = s.useNovaGateway
        ollamaBaseURL = s.ollamaBaseURL
        novaGatewayURL = s.novaGatewayURL
        selectedBackend = s.selectedBackend ?? .auto
        tinyLLMURL = s.tinyLLMURL ?? LLMBackendType.tinyLLM.defaultURL
        tinyChatURL = s.tinyChatURL ?? LLMBackendType.tinyChat.defaultURL
        openWebUIURL = s.openWebUIURL ?? LLMBackendType.openWebUI.defaultURL
        openAIBaseURL = s.openAIBaseURL ?? LLMBackendType.openAI.defaultURL
        models = s.models ?? [:]
    }

    var persisted: Persisted {
        Persisted(
            useAllLocalModels: useAllLocalModels,
            enableAllFrontierModels: enableAllFrontierModels,
            useNovaGateway: useNovaGateway,
            ollamaBaseURL: ollamaBaseURL,
            novaGatewayURL: novaGatewayURL,
            selectedBackend: selectedBackend,
            tinyLLMURL: tinyLLMURL,
            tinyChatURL: tinyChatURL,
            openWebUIURL: openWebUIURL,
            openAIBaseURL: openAIBaseURL,
            models: models
        )
    }

    func saveSettings() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(persisted) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private func endpointChanged(_ backend: LLMBackendType) {
        backendHealth[backend] = nil
        healthCheckedAt[backend] = nil
        saveSettings()
    }

    // MARK: - Endpoints and models

    /// The configured base URL for `backend` (trimmed, no trailing slash).
    func url(for backend: LLMBackendType) -> String {
        let raw: String
        switch backend {
        case .ollama: raw = ollamaBaseURL
        case .tinyLLM: raw = tinyLLMURL
        case .tinyChat: raw = tinyChatURL
        case .openWebUI: raw = openWebUIURL
        case .novaGateway: raw = novaGatewayURL
        case .openAI: raw = openAIBaseURL
        case .openRouter: raw = OpenRouterProvider.baseURL
        case .auto, .mlx: raw = ""
        }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func setURL(_ value: String, for backend: LLMBackendType) {
        switch backend {
        case .ollama: ollamaBaseURL = value
        case .tinyLLM: tinyLLMURL = value
        case .tinyChat: tinyChatURL = value
        case .openWebUI: openWebUIURL = value
        case .novaGateway: novaGatewayURL = value
        case .openAI: openAIBaseURL = value
        case .auto, .mlx, .openRouter: break
        }
    }

    /// True for a usable http(s) URL with a host. Cloud backends (which carry a key) require https.
    nonisolated static func isValidEndpoint(_ urlString: String, requireHTTPS: Bool) -> Bool {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else { return false }
        return requireHTTPS ? scheme == "https" : (scheme == "http" || scheme == "https")
    }

    func model(for backend: LLMBackendType) -> String {
        let m = models[backend.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return m.isEmpty ? backend.defaultModel : m
    }

    func setModel(_ model: String, for backend: LLMBackendType) {
        models[backend.rawValue] = model.trimmingCharacters(in: .whitespacesAndNewlines)
        saveSettings()
    }

    /// The backend whose models the model picker edits: the selected backend, or
    /// in Auto the active one (Ollama until something answered).
    var modelPickerBackend: LLMBackendType {
        if selectedBackend != .auto { return selectedBackend }
        return activeBackend ?? .ollama
    }

    /// The model the next turn will most likely use.
    var currentModel: String { model(for: modelPickerBackend) }

    /// Whether `backend` has everything it needs (valid URL, key if needed, platform).
    func isConfigured(_ backend: LLMBackendType) -> Bool {
        guard backend != .auto, backend.isSupportedOnThisPlatform else { return false }
        switch backend {
        case .mlx:
            return false // dispatch is not implemented in this manager (tvOS/iOS have no MLX)
        case .openRouter:
            return hasOpenRouterKey
        case .openAI:
            return hasOpenAIKey && Self.isValidEndpoint(url(for: .openAI), requireHTTPS: true)
        default:
            return Self.isValidEndpoint(url(for: backend), requireHTTPS: false)
        }
    }

    /// Backends to try for a turn, in order.
    var candidateChain: [LLMBackendType] {
        selectedBackend == .auto ? LLMBackendType.autoOrder.filter { $0.isSupportedOnThisPlatform } : [selectedBackend]
    }

    // MARK: - API keys (Keychain only)

    /// Store (or clear, when empty) the OpenRouter API key. Keychain only.
    @discardableResult
    func setOpenRouterKey(_ key: String) -> Bool { setAPIKey(key, for: .openRouter) }

    func openRouterAPIKey() -> String? { openRouterKeychain.get() }

    /// Store (or clear, when empty) a cloud backend's API key. Keychain only.
    @discardableResult
    func setAPIKey(_ key: String, for backend: LLMBackendType) -> Bool {
        guard let store = keychain(for: backend) else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = trimmed.isEmpty ? store.delete() : store.set(trimmed)
        hasOpenRouterKey = openRouterKeychain.hasValue
        hasOpenAIKey = openAIKeychain.hasValue
        backendHealth[backend] = nil
        healthCheckedAt[backend] = nil
        return ok
    }

    func hasAPIKey(for backend: LLMBackendType) -> Bool {
        switch backend {
        case .openRouter: return hasOpenRouterKey
        case .openAI: return hasOpenAIKey
        default: return false
        }
    }

    private func keychain(for backend: LLMBackendType) -> KeychainStore? {
        switch backend {
        case .openRouter: return openRouterKeychain
        case .openAI: return openAIKeychain
        default: return nil
        }
    }

    private func authHeaders(for backend: LLMBackendType) throws -> [String: String] {
        switch backend {
        case .openRouter:
            guard let key = openRouterKeychain.get(), !key.isEmpty else { throw LLMError.missingAPIKey }
            return OpenRouterProvider.authHeaders(apiKey: key)
        case .openAI:
            guard let key = openAIKeychain.get(), !key.isEmpty else { throw LLMError.missingAPIKey }
            return ["Authorization": "Bearer \(key)"]
        default:
            return [:]
        }
    }

    // MARK: - Health probing and status

    /// The URL probed to decide whether `backend` is up.
    func probeURL(for backend: LLMBackendType) -> URL? {
        let base = url(for: backend)
        switch backend {
        case .ollama: return URL(string: "\(base)/api/tags")
        case .tinyLLM, .novaGateway: return URL(string: "\(base)/v1/models")
        case .tinyChat: return URL(string: "\(base)/api/health")
        case .openWebUI: return URL(string: "\(base)/api/models")
        case .openAI, .openRouter: return URL(string: "\(base)/models")
        case .auto, .mlx: return nil
        }
    }

    /// Probe a single backend's health. Never throws: unreachable → false.
    /// Cloud backends are "available" when a key is stored and the URL is https
    /// (no network call, so status checks never spend cloud quota).
    func checkAvailability(_ backend: LLMBackendType) async -> Bool {
        let ok: Bool
        if !isConfigured(backend) {
            ok = false
        } else if backend.requiresAPIKey {
            ok = true
        } else if let url = probeURL(for: backend) {
            ok = await isReachable(url)
        } else {
            ok = false
        }
        recordHealth(backend, ok)
        if backend == .novaGateway { isNovaGatewayAvailable = ok }
        return ok
    }

    /// Cached health for `.auto`: re-probes only after `healthTTL`.
    func isHealthy(_ backend: LLMBackendType) async -> Bool {
        if let at = healthCheckedAt[backend], let h = backendHealth[backend],
           Date().timeIntervalSince(at) < healthTTL {
            return h
        }
        return await checkAvailability(backend)
    }

    private func recordHealth(_ backend: LLMBackendType, _ ok: Bool) {
        backendHealth[backend] = ok
        healthCheckedAt[backend] = Date()
    }

    /// Record the outcome of a call made outside `generate` (e.g. a streaming call).
    func recordResult(_ backend: LLMBackendType, ok: Bool) {
        recordHealth(backend, ok)
        if ok { activeBackend = backend } else if activeBackend == backend { activeBackend = nil }
        updateStatusText()
    }

    private func isReachable(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = probeTimeout
        do {
            let (_, response) = try await transport(request)
            return (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    /// "Test connection": probe the candidate chain and set `activeBackend` to the
    /// first reachable backend (or nil).
    @discardableResult
    func refreshStatus() async -> LLMBackendType? {
        isCheckingStatus = true
        defer { isCheckingStatus = false }
        var first: LLMBackendType?
        for backend in candidateChain {
            if await checkAvailability(backend), first == nil { first = backend }
        }
        activeBackend = first
        updateStatusText()
        return first
    }

    private func updateStatusText() {
        if let active = activeBackend {
            statusText = "\(active.displayName) online"
        } else if selectedBackend == .auto {
            statusText = "No backend reachable"
        } else {
            statusText = "\(selectedBackend.displayName) unreachable"
        }
    }

    // MARK: - Model listing

    /// Parse model ids from an OpenAI-style (`data[].id`), OpenWebUI (`models[].id`)
    /// or Ollama (`models[].name`) listing. Pure; `[]` on garbage.
    nonisolated static func parseModelIDs(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let list = (json["data"] as? [[String: Any]]) ?? (json["models"] as? [[String: Any]]) ?? []
        return list.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }.filter { !$0.isEmpty }
    }

    /// Fetch the model list for `backend`. Never throws: unreachable → `[]`.
    func fetchModels(for backend: LLMBackendType) async -> [String] {
        switch backend {
        case .openRouter:
            await refreshOpenRouterModels()
            return openRouterModels
        case .tinyChat, .auto, .mlx:
            return []
        default:
            guard isConfigured(backend), let url = probeURL(for: backend) else { return [] }
            var request = URLRequest(url: url)
            request.timeoutInterval = probeTimeout
            if let headers = try? authHeaders(for: backend) {
                for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            }
            guard case let (data, response)? = try? await transport(request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return Self.parseModelIDs(data)
        }
    }

    /// Refresh `availableModels` for `modelPickerBackend`. Falls back to the
    /// current model so the picker is never empty.
    func refreshAvailableModels() async {
        let backend = modelPickerBackend
        var list = await fetchModels(for: backend)
        let current = model(for: backend)
        if list.isEmpty, !current.isEmpty { list = [current] }
        availableModels = list
    }

    /// Refresh the OpenRouter model list (resilient: falls back to the popular
    /// set on any failure). Only hits the network when a key is present.
    func refreshOpenRouterModels() async {
        guard let key = openRouterAPIKey(), !key.isEmpty,
              let url = URL(string: OpenRouterProvider.modelsURL) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = probeTimeout
        for (k, v) in OpenRouterProvider.authHeaders(apiKey: key) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (data, response) = try await transport(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let ids = OpenRouterProvider.parseModels(data)
            if !ids.isEmpty { openRouterModels = ids }
        } catch {
            // Keep the existing/fallback list.
        }
    }

    // MARK: - Balancer pool discovery

    /// Discover the enabled balancer pool honoring the three toggles. Resilient:
    /// any unreachable source contributes zero models.
    @discardableResult
    func discoverEnabledPool() async -> [DiscoveredModel] {
        var ollama: [DiscoveredModel] = []
        var frontier: [DiscoveredModel] = []

        if useAllLocalModels, let tagsURL = probeURL(for: .ollama) {
            var request = URLRequest(url: tagsURL)
            request.timeoutInterval = probeTimeout
            if case let (data, response)? = try? await transport(request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                ollama = ModelRegistry.parseOllamaTags(data, baseURL: url(for: .ollama))
            }
        }
        if enableAllFrontierModels {
            frontier = ModelRegistry.frontierModels(from: openRouterModels)
        }
        let nova = useNovaGateway ? ModelRegistry.novaGatewayModel(url: url(for: .novaGateway)) : nil

        let pool = ModelRegistry.assemblePool(
            ollama: ollama,
            mlx: [], // MLX dispatch isn't implemented here
            frontier: frontier,
            novaGateway: nova,
            useAllLocalModels: useAllLocalModels,
            enableAllFrontierModels: enableAllFrontierModels,
            useNovaGateway: useNovaGateway
        )
        discoveredModels = pool
        return pool
    }

    /// Build a `[modelId: Bool]` health map for `pool` by probing each distinct backend once.
    private func healthMap(for pool: [DiscoveredModel]) async -> [String: Bool] {
        var backendHealth: [LLMBackendType: Bool] = [:]
        for backend in Set(pool.map { $0.backend }) {
            backendHealth[backend] = await isHealthy(backend)
        }
        var map: [String: Bool] = [:]
        for model in pool {
            map[model.id] = backendHealth[model.backend] ?? false
        }
        return map
    }

    // MARK: - Generation

    /// Generate one reply.
    ///
    /// 1. If a balancer toggle is on, try the healthy pool (`firstSuccess`).
    /// 2. Then the selected backend, or in Auto every configured + reachable
    ///    backend in `autoOrder`, each with bounded retries.
    ///
    /// Throws the last error (or `LLMError.noBackendAvailable`) when nothing answers.
    func generate(
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        prompt: String,
        temperature: Float = 0.7,
        maxTokens: Int = 2048
    ) async throws -> String {
        if isBalancingEnabled,
           let balanced = try? await generateBalanced(
               messages: messages, systemPrompt: systemPrompt, prompt: prompt,
               temperature: temperature, maxTokens: maxTokens) {
            return balanced
        }

        var lastError: Error = LLMError.noBackendAvailable
        for backend in candidateChain {
            guard isConfigured(backend) else {
                if backend.requiresAPIKey, selectedBackend == backend { lastError = LLMError.missingAPIKey }
                continue
            }
            if selectedBackend == .auto, !(await isHealthy(backend)) { continue }
            do {
                let model = model(for: backend)
                let text = try await withRetry(backend.rawValue) {
                    try await self.dispatch(
                        backend: backend, model: model, messages: messages, systemPrompt: systemPrompt,
                        prompt: prompt, temperature: temperature, maxTokens: maxTokens)
                }
                recordResult(backend, ok: true)
                return text
            } catch {
                lastError = error
                recordResult(backend, ok: false)
            }
        }
        activeBackend = nil
        updateStatusText()
        throw lastError
    }

    /// Balanced dispatch over the enabled pool. Returns `nil` when balancing is
    /// off or nothing healthy exists; throws when every healthy model failed.
    func generateBalanced(
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        prompt: String,
        temperature: Float = 0.7,
        maxTokens: Int = 2048
    ) async throws -> String? {
        guard isBalancingEnabled else { return nil }
        let pool = await discoverEnabledPool()
        guard !pool.isEmpty else { return nil }
        let health = await healthMap(for: pool)
        var answered: LLMBackendType?
        let result = try await balancer.firstSuccess(pool: pool, health: health, policy: balancerPolicy) { choice in
            let text = try await self.withRetry(choice.id) {
                try await self.dispatch(
                    backend: choice.backend, model: choice.modelName, messages: messages,
                    systemPrompt: systemPrompt, prompt: prompt, temperature: temperature, maxTokens: maxTokens)
            }
            answered = choice.backend
            return text
        }
        if let answered { recordResult(answered, ok: true) }
        return result
    }

    /// Retry transient failures (network errors, 408/429/5xx); fail fast on config errors and 4xx.
    nonisolated static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let llm = error as? LLMError {
            switch llm {
            case .httpError(let code): return HTTP.isRetryableStatus(code)
            case .noResponse, .invalidResponse: return true
            default: return false
            }
        }
        if let url = error as? URLError { return url.code != .cancelled && url.code != .unsupportedURL }
        if error is DecodingError { return false }
        return true
    }

    private func withRetry(_ label: String, _ op: () async throws -> String) async throws -> String {
        try await Retry.run(label, policy: retryPolicy, sleep: sleep, shouldRetry: Self.isRetryable, operation: op)
    }

    /// Build the HTTP request for one generation call. Exposed for tests (no network).
    func buildRequest(
        backend: LLMBackendType,
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        prompt: String,
        temperature: Float,
        maxTokens: Int
    ) throws -> URLRequest {
        let base = url(for: backend)
        let chat = OpenAICompatibleRequest.chatMessages(prompt: prompt, systemPrompt: systemPrompt, history: messages)
        var request: URLRequest
        switch backend {
        case .ollama:
            guard Self.isValidEndpoint(base, requireHTTPS: false), let url = URL(string: "\(base)/api/chat") else {
                throw LLMError.invalidURL
            }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": model, "messages": chat, "stream": false,
                "options": ["temperature": temperature, "num_predict": maxTokens]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        case .tinyLLM, .tinyChat, .openWebUI, .novaGateway, .openRouter, .openAI:
            let endpoint: String
            switch backend {
            case .tinyLLM, .novaGateway: endpoint = "\(base)/v1/chat/completions"
            case .tinyChat: endpoint = "\(base)/api/chat/stream"
            case .openWebUI: endpoint = "\(base)/api/chat/completions"
            case .openRouter: endpoint = OpenRouterProvider.chatCompletionsURL
            default: endpoint = "\(base)/chat/completions" // openAI base already ends in /v1
            }
            guard Self.isValidEndpoint(endpoint, requireHTTPS: backend.requiresAPIKey) else {
                throw backend.requiresAPIKey && Self.isValidEndpoint(endpoint, requireHTTPS: false)
                    ? LLMError.insecureEndpoint : LLMError.invalidURL
            }
            request = try OpenAICompatibleRequest.build(
                endpoint: endpoint, model: model, messages: chat, temperature: temperature,
                maxTokens: maxTokens, stream: false, headers: try authHeaders(for: backend))
        case .auto, .mlx:
            throw LLMError.noBackendAvailable
        }
        request.timeoutInterval = requestTimeout
        return request
    }

    /// One call to one backend (no retry here).
    private func dispatch(
        backend: LLMBackendType,
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        prompt: String,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        let request = try buildRequest(
            backend: backend, model: model, messages: messages, systemPrompt: systemPrompt,
            prompt: prompt, temperature: temperature, maxTokens: maxTokens)
        let (data, response) = try await transport(request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LLMError.httpError(http.statusCode)
        }
        guard let text = Self.extractContent(data, allowPlainText: backend == .tinyChat) else {
            throw LLMError.noResponse
        }
        return text
    }

    /// Pull the assistant text out of an OpenAI (`choices[0].message.content`) or
    /// Ollama (`message.content`) reply. TinyChat may answer with plain text.
    /// Returns nil for empty/unreadable bodies. Pure.
    nonisolated static func extractContent(_ data: Data, allowPlainText: Bool = false) -> String? {
        var text: String?
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any] {
                text = message["content"] as? String
            } else if let message = json["message"] as? [String: Any] {
                text = message["content"] as? String
            } else if let response = json["response"] as? String {
                text = response
            }
        } else if allowPlainText {
            text = String(data: data, encoding: .utf8)
        }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

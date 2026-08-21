//
//  LLMBalancerManager.swift
//  BlompieTV
//
//  Shared multi-model LLM load balancer for BlompieTV (tvOS).
//
//  Mirrors AIStudio's `LLMBackendManager` balanced-dispatch: it discovers every
//  model the three toggles enable — all local Ollama models, all OpenRouter
//  frontier models, and the optional Nova Gateway — normalizes them into a flat
//  pool via `ModelRegistry`, and spreads work across the healthy subset with the
//  pure `LoadBalancer`.
//
//  HARD INVARIANTS honored here:
//   • Local-only keeps working with zero cloud. All toggles default OFF →
//     `isBalancingEnabled == false` → the game's existing OllamaService path is
//     used unchanged. This manager is purely additive.
//   • Nova is NEVER required. A failed Nova health check simply drops it from the
//     pool; there is no hard dependency and no error surfaced to the player.
//   • All backends are plain HTTP calls, so everything works inside the tvOS
//     platform sandbox (which cannot be disabled and is not touched here).
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

    // MARK: - Toggles (persisted)

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

    // MARK: - Endpoints (persisted)

    @Published var ollamaBaseURL = ModelRegistry.ollamaBaseURL {
        didSet { saveSettings() }
    }
    @Published var novaGatewayURL = ModelRegistry.novaGatewayDefaultURL {
        didSet { saveSettings() }
    }

    // MARK: - Discovered state (for the settings UI)

    /// The models currently in the enabled, de-duplicated pool.
    @Published private(set) var discoveredModels: [DiscoveredModel] = []
    /// OpenRouter model ids fetched from `/models` (falls back to a popular set).
    @Published private(set) var openRouterModels: [String] = OpenRouterProvider.fallbackModels
    /// Whether a non-empty OpenRouter key is stored in the Keychain.
    @Published private(set) var hasOpenRouterKey = false
    /// Live availability flags used by the status surface.
    @Published private(set) var isNovaGatewayAvailable = false

    // MARK: - Balancer

    /// Pure, network-free balancer that spreads work across the enabled pool.
    let balancer = LoadBalancer()
    /// Least-busy mirrors how Nova's gateway spreads load.
    var balancerPolicy: BalancerPolicy = .leastBusy

    /// Keychain-backed store for the OpenRouter API key.
    let openRouterKeychain = KeychainStore()

    /// True when any load-balancing toggle is on, so a request should be
    /// dispatched through the balanced path rather than the default local path.
    var isBalancingEnabled: Bool {
        useAllLocalModels || enableAllFrontierModels || useNovaGateway
    }

    private let settingsKey = "BlompieTVLLMBalancerSettings"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        loadSettings()
        hasOpenRouterKey = openRouterKeychain.hasValue
    }

    // MARK: - Settings persistence

    private struct Persisted: Codable {
        var useAllLocalModels: Bool
        var enableAllFrontierModels: Bool
        var useNovaGateway: Bool
        var ollamaBaseURL: String
        var novaGatewayURL: String
    }

    private var isLoading = false

    func loadSettings() {
        isLoading = true
        defer { isLoading = false }
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let s = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        useAllLocalModels = s.useAllLocalModels
        enableAllFrontierModels = s.enableAllFrontierModels
        useNovaGateway = s.useNovaGateway
        ollamaBaseURL = s.ollamaBaseURL
        novaGatewayURL = s.novaGatewayURL
    }

    func saveSettings() {
        guard !isLoading else { return }
        let s = Persisted(
            useAllLocalModels: useAllLocalModels,
            enableAllFrontierModels: enableAllFrontierModels,
            useNovaGateway: useNovaGateway,
            ollamaBaseURL: ollamaBaseURL,
            novaGatewayURL: novaGatewayURL
        )
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    // MARK: - OpenRouter API key (Keychain)

    /// Store (or clear, when empty) the OpenRouter API key. Never persisted to
    /// UserDefaults — Keychain only.
    @discardableResult
    func setOpenRouterKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok: Bool
        if trimmed.isEmpty {
            ok = openRouterKeychain.delete()
        } else {
            ok = openRouterKeychain.set(trimmed)
        }
        hasOpenRouterKey = openRouterKeychain.hasValue
        return ok
    }

    func openRouterAPIKey() -> String? { openRouterKeychain.get() }

    // MARK: - Discovery

    /// Refresh the OpenRouter model list (resilient: falls back to the popular
    /// set on any failure). Only hits the network when a key is present.
    func refreshOpenRouterModels() async {
        guard let key = openRouterAPIKey(), !key.isEmpty,
              let url = URL(string: OpenRouterProvider.modelsURL) else { return }
        var request = URLRequest(url: url)
        for (k, v) in OpenRouterProvider.authHeaders(apiKey: key) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let ids = OpenRouterProvider.parseModels(data)
            if !ids.isEmpty { openRouterModels = ids }
        } catch {
            // Keep the existing/fallback list.
        }
    }

    /// Discover the enabled balancer pool honoring the three toggles. Resilient:
    /// any unreachable source contributes zero models.
    @discardableResult
    func discoverEnabledPool() async -> [DiscoveredModel] {
        var ollama: [DiscoveredModel] = []
        var mlx: [DiscoveredModel] = []
        var frontier: [DiscoveredModel] = []

        if useAllLocalModels {
            ollama = await ModelRegistry.discoverOllama(baseURL: ollamaBaseURL, session: session)
            mlx = ModelRegistry.discoverMLX() // empty on tvOS (no HF cache) — harmless
        }
        if enableAllFrontierModels {
            frontier = ModelRegistry.frontierModels(from: openRouterModels)
        }
        let nova = useNovaGateway ? ModelRegistry.novaGatewayModel(url: novaGatewayURL) : nil

        let pool = ModelRegistry.assemblePool(
            ollama: ollama,
            mlx: mlx,
            frontier: frontier,
            novaGateway: nova,
            useAllLocalModels: useAllLocalModels,
            enableAllFrontierModels: enableAllFrontierModels,
            useNovaGateway: useNovaGateway
        )
        discoveredModels = pool
        return pool
    }

    // MARK: - Health probing

    /// Probe a single backend's health. Never throws — unreachable → false.
    func checkAvailability(_ backend: LLMBackendType) async -> Bool {
        switch backend {
        case .ollama:
            guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else { return false }
            return await isReachable(url)
        case .openRouter:
            // A stored key is the gate; the live request path handles auth errors.
            return hasOpenRouterKey
        case .novaGateway:
            guard let url = URL(string: "\(novaGatewayURL)/v1/models") else { return false }
            let ok = await isReachable(url)
            isNovaGatewayAvailable = ok
            return ok
        case .mlx:
            return false // MLX is not used on tvOS
        default:
            return false
        }
    }

    private func isReachable(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    /// Build a `[modelId: Bool]` health map for `pool` by probing each distinct
    /// backend once.
    private func healthMap(for pool: [DiscoveredModel]) async -> [String: Bool] {
        var backendHealth: [LLMBackendType: Bool] = [:]
        for backend in Set(pool.map { $0.backend }) {
            backendHealth[backend] = await checkAvailability(backend)
        }
        var map: [String: Bool] = [:]
        for model in pool {
            map[model.id] = backendHealth[model.backend] ?? false
        }
        return map
    }

    // MARK: - Balanced generation

    /// Balanced dispatch: discover the enabled pool, gate to healthy models, then
    /// pick via the `LoadBalancer`, falling through to the next model on failure.
    ///
    /// Returns `nil` when balancing is off or nothing healthy exists, so the
    /// caller can fall back cleanly to the default local path.
    func generate(
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
        var remaining = pool
        var lastError: Error?

        while let choice = balancer.next(pool: remaining, health: health, policy: balancerPolicy) {
            balancer.checkOut(choice.id)
            do {
                let result = try await dispatch(
                    model: choice, messages: messages, systemPrompt: systemPrompt,
                    prompt: prompt, temperature: temperature, maxTokens: maxTokens
                )
                balancer.checkIn(choice.id)
                return result
            } catch {
                balancer.checkIn(choice.id)
                lastError = error
                remaining.removeAll { $0.id == choice.id }
                continue
            }
        }

        if let lastError { throw lastError }
        return nil
    }

    /// Route a single balancer-selected model to the appropriate backend. All
    /// backends here are OpenAI-compatible HTTP endpoints.
    private func dispatch(
        model: DiscoveredModel,
        messages: [ChatMessage],
        systemPrompt: String?,
        prompt: String,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        switch model.backend {
        case .ollama:
            return try await generateOllamaChat(
                model: model.modelName, baseURL: ollamaBaseURL,
                messages: messages, systemPrompt: systemPrompt, prompt: prompt,
                temperature: temperature, maxTokens: maxTokens
            )
        case .openRouter:
            guard let key = openRouterAPIKey(), !key.isEmpty else { throw LLMError.noBackendAvailable }
            return try await generateOpenAICompatible(
                endpoint: model.endpoint, model: model.modelName,
                headers: OpenRouterProvider.authHeaders(apiKey: key),
                messages: messages, systemPrompt: systemPrompt, prompt: prompt,
                temperature: temperature, maxTokens: maxTokens
            )
        case .novaGateway:
            return try await generateOpenAICompatible(
                endpoint: model.endpoint, model: model.modelName, headers: [:],
                messages: messages, systemPrompt: systemPrompt, prompt: prompt,
                temperature: temperature, maxTokens: maxTokens
            )
        default:
            throw LLMError.noBackendAvailable
        }
    }

    // MARK: - Backend request paths

    /// Generic OpenAI-compatible `/v1/chat/completions` call (OpenRouter + Nova).
    private func generateOpenAICompatible(
        endpoint: String,
        model: String,
        headers: [String: String],
        messages: [ChatMessage],
        systemPrompt: String?,
        prompt: String,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        let chatMessages = OpenAICompatibleRequest.chatMessages(
            prompt: prompt, systemPrompt: systemPrompt, history: messages
        )
        let request = try OpenAICompatibleRequest.build(
            endpoint: endpoint, model: model, messages: chatMessages,
            temperature: temperature, maxTokens: maxTokens, stream: false, headers: headers
        )
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LLMError.httpError(http.statusCode)
        }
        struct OAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(OAIResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else { throw LLMError.noResponse }
        return content
    }

    /// Ollama `/api/chat` for a specific local model.
    private func generateOllamaChat(
        model: String,
        baseURL: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        prompt: String,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/chat") else { throw LLMError.invalidURL }

        // Ollama /api/chat uses the same {role,content} message shape; the builder
        // always includes the trailing user prompt.
        let msgs = OpenAICompatibleRequest.chatMessages(
            prompt: prompt, systemPrompt: systemPrompt, history: messages
        )

        let body: [String: Any] = [
            "model": model,
            "messages": msgs,
            "stream": false,
            "options": ["temperature": temperature, "num_predict": maxTokens]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LLMError.httpError(http.statusCode)
        }
        struct OllamaChat: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let decoded = try JSONDecoder().decode(OllamaChat.self, from: data)
        return decoded.message.content
    }
}

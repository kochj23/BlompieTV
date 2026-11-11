//
//  LLMBalancerTypes.swift
//  BlompieTV
//
//  Supporting value types shared by the multi-model load balancer
//  (ModelRegistry / OpenRouterProvider / KeychainStore).
//
//  Originally copied from AIStudio's pure/network-free layer. `LLMBackendType`
//  is the canonical backend id set for Jordan's games. All types here are
//  platform-neutral Foundation value types, no macOS/AppKit dependencies.
//
//  Author: Jordan Koch
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation

// MARK: - LLM backend type

/// Canonical LLM backend identifier shared by Jordan's games (stable lowercase
/// raw values, safe to persist). Claude is reached through `.novaGateway` or
/// `.openRouter` (e.g. `anthropic/claude-*`); there is no direct Anthropic case.
///
/// Google Cloud / Azure / AWS / IBM Watson are deliberately absent: in the other
/// apps they were stubs or broken and never worked.
enum LLMBackendType: String, CaseIterable, Codable, Sendable {
    case auto = "auto"
    case ollama = "ollama"
    case mlx = "mlx"
    case tinyLLM = "tinyllm"
    case tinyChat = "tinychat"
    case openWebUI = "openwebui"
    case novaGateway = "novagateway"
    case openRouter = "openrouter"
    case openAI = "openai"

    /// Fixed failover order used by `.auto`: local first, then Nova, then cloud.
    static let autoOrder: [LLMBackendType] = [
        .ollama, .mlx, .tinyChat, .tinyLLM, .openWebUI, .novaGateway, .openRouter, .openAI
    ]

    /// MLX runs `mlx_lm` in-process on Apple Silicon Macs only; hidden elsewhere.
    var isSupportedOnThisPlatform: Bool {
        #if os(macOS)
        return true
        #else
        return self != .mlx
        #endif
    }

    /// Backends offered in the picker on this platform (Auto first).
    static var pickerCases: [LLMBackendType] { allCases.filter { $0.isSupportedOnThisPlatform } }

    /// Cloud backends that need an API key (stored in the Keychain, sent over https only).
    var requiresAPIKey: Bool { self == .openRouter || self == .openAI }

    /// Backends whose base URL the player can edit.
    var hasEditableURL: Bool {
        switch self {
        case .ollama, .tinyLLM, .tinyChat, .openWebUI, .novaGateway, .openAI: return true
        case .auto, .mlx, .openRouter: return false
        }
    }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .ollama: return "Ollama"
        case .mlx: return "MLX Native"
        case .tinyLLM: return "TinyLLM"
        case .tinyChat: return "TinyChat"
        case .openWebUI: return "OpenWebUI"
        case .novaGateway: return "Nova Gateway"
        case .openRouter: return "OpenRouter (Frontier Models)"
        case .openAI: return "OpenAI"
        }
    }

    var icon: String {
        switch self {
        case .auto: return "sparkles"
        case .ollama: return "network"
        case .mlx: return "cpu"
        case .tinyLLM: return "cube"
        case .tinyChat: return "bubble.left.and.bubble.right.fill"
        case .openWebUI: return "globe"
        case .novaGateway: return "sparkle.magnifyingglass"
        case .openRouter: return "cloud"
        case .openAI: return "brain"
        }
    }

    var defaultURL: String {
        switch self {
        case .auto: return ""
        case .ollama: return "http://localhost:11434"
        case .mlx: return ""
        case .tinyLLM: return "http://localhost:8000"
        case .tinyChat: return "http://localhost:8000"
        case .openWebUI: return "http://localhost:8080"
        case .novaGateway: return ModelRegistry.novaGatewayDefaultURL
        case .openRouter: return OpenRouterProvider.baseURL
        case .openAI: return "https://api.openai.com/v1"
        }
    }

    /// Model used when the player hasn't picked one for this backend.
    var defaultModel: String {
        switch self {
        case .auto, .mlx: return ""
        case .ollama: return "mistral"
        case .tinyLLM: return "tinyllm"
        case .tinyChat: return "tinychat"
        case .openWebUI: return "llama3.2"
        case .novaGateway: return "nova"
        case .openRouter: return OpenRouterProvider.defaultModel
        case .openAI: return "gpt-4o-mini"
        }
    }

    var description: String {
        switch self {
        case .auto: return "Try each reachable backend in a fixed order: Ollama, TinyChat, TinyLLM, OpenWebUI, Nova Gateway, OpenRouter, OpenAI"
        case .ollama: return "Ollama HTTP API on your Mac or LAN (port 11434)"
        case .mlx: return "Apple Silicon native inference via MLX (macOS only)"
        case .tinyLLM: return "TinyLLM lightweight OpenAI-compatible server (port 8000)"
        case .tinyChat: return "TinyChat by Jason Cox (port 8000)"
        case .openWebUI: return "Self-hosted OpenWebUI (port 8080 or 3000)"
        case .novaGateway: return "Nova's gateway: OpenAI-compatible, inherits Nova's routing (port 18792); also the Claude route"
        case .openRouter: return "Frontier cloud models via OpenRouter (bring your own key; https only)"
        case .openAI: return "OpenAI API (bring your own key; https only)"
        }
    }

    var attribution: String? {
        switch self {
        case .tinyLLM: return "TinyLLM by Jason Cox (https://github.com/jasonacox/TinyLLM)"
        case .tinyChat: return "TinyChat by Jason Cox (https://github.com/jasonacox/tinychat)"
        case .openWebUI: return "OpenWebUI Community Project (https://github.com/open-webui/open-webui)"
        default: return nil
        }
    }
}

// MARK: - Chat message

/// Role in a chat conversation.
enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

/// A single chat message consumed by the OpenAI-compatible request builder.
struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - LLM errors

enum LLMError: LocalizedError, Sendable, Equatable {
    case noBackendAvailable
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noResponse
    case mlxNotAvailable
    /// A request carrying an API key was aimed at a non-https URL; refused.
    case insecureEndpoint
    /// A cloud backend was selected but no key is stored in the Keychain.
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .noBackendAvailable:
            return "No LLM backend is available. Start Ollama locally, or enable OpenRouter / Nova Gateway."
        case .invalidURL:
            return "Invalid backend URL configuration."
        case .invalidResponse:
            return "Received invalid response from LLM backend."
        case .httpError(let code):
            return "HTTP error \(code) from LLM backend."
        case .noResponse:
            return "No response received from LLM backend."
        case .mlxNotAvailable:
            return "MLX not available on this platform."
        case .insecureEndpoint:
            return "Refusing to send an API key over plain http. Use an https:// URL."
        case .missingAPIKey:
            return "This backend needs an API key. Add one in Settings > Cloud."
        }
    }
}

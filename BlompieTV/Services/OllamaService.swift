//
//  OllamaService.swift
//  BlompieTV
//
//  Ollama wire types (also used by saved games) and the streaming client used
//  when the active backend is Ollama. Endpoints, backend choice, failover and
//  non-streaming calls live in LLMBalancerManager.
//  Created by Jordan Koch on 2/2/2026.
//  Copyright 2026 Jordan Koch. All rights reserved.
//

import Foundation

struct OllamaMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let options: OllamaOptions?
}

struct OllamaOptions: Codable {
    let temperature: Double?
    let num_predict: Int?
}

struct OllamaChatResponse: Codable {
    let message: OllamaMessage
    let done: Bool
    let eval_count: Int?
    let eval_duration: Int64?
    let prompt_eval_count: Int?
    let prompt_eval_duration: Int64?

    var tokensPerSecond: Double? {
        guard let count = eval_count, let duration = eval_duration, duration > 0 else {
            return nil
        }
        let seconds = Double(duration) / 1_000_000_000.0
        return Double(count) / seconds
    }
}

struct OllamaModel: Codable {
    let name: String
    let size: Int64?
    let modified_at: String?
}

struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

// OpenWebUI API response structures
struct OpenWebUIModelsResponse: Codable {
    let data: [OpenWebUIModel]?
    let models: [OpenWebUIModel]?

    var allModels: [OpenWebUIModel] {
        return data ?? models ?? []
    }
}

struct OpenWebUIModel: Codable {
    let id: String
    let name: String?
    let owned_by: String?
}

enum OllamaError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse(statusCode: Int?, body: String?)
    case decodingError(Error, responseBody: String?)
    case noServerConfigured
    case serverUnreachable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let statusCode, let body):
            if let statusCode = statusCode {
                return "Invalid response (HTTP \(statusCode)): \(body ?? "No details")"
            }
            return "Invalid response: \(body ?? "No details")"
        case .decodingError(let error, let body):
            return "Failed to decode response: \(error.localizedDescription)\nResponse: \(body ?? "Unknown")"
        case .noServerConfigured:
            return "No AI server configured. Go to Settings to configure Ollama or OpenWebUI server."
        case .serverUnreachable:
            return "Cannot reach the AI server. Make sure it's running and the address is correct."
        }
    }
}

/// Server kind found by `ServerDiscovery` on the LAN.
enum AIServerType: String, Codable, CaseIterable {
    case ollama = "Ollama"
    case openwebui = "OpenWebUI"

    /// The canonical backend this server is configured as.
    var backend: LLMBackendType {
        switch self {
        case .ollama: return .ollama
        case .openwebui: return .openWebUI
        }
    }
}

/// Streams an Ollama `/api/chat` reply; `onChunk` gets the text so far and the
/// full reply is returned. Stateless: the caller
/// passes the base URL and model from `LLMBalancerManager`.
struct OllamaService {
    var timeout: TimeInterval = 120

    func chatStreaming(
        baseURL: String,
        model: String,
        temperature: Double,
        maxTokens: Int? = nil,
        messages: [OllamaMessage],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Double?) -> Void
    ) async throws -> String {
        guard LLMBalancerManager.isValidEndpoint(baseURL, requireHTTPS: false),
              let url = URL(string: "\(baseURL)/api/chat") else {
            throw OllamaError.noServerConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaChatRequest(
            model: model,
            messages: messages,
            stream: true,
            options: OllamaOptions(temperature: temperature, num_predict: maxTokens)
        ))

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse(statusCode: nil, body: nil)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw OllamaError.invalidResponse(statusCode: httpResponse.statusCode, body: nil)
            }

            var lastResponse: OllamaChatResponse?
            var full = ""
            for try await line in asyncBytes.lines {
                if let data = line.data(using: .utf8),
                   let chunk = try? JSONDecoder().decode(OllamaChatResponse.self, from: data) {
                    full += chunk.message.content
                    onChunk(full)
                    lastResponse = chunk
                }
            }
            onComplete(lastResponse?.tokensPerSecond)
            return full
        } catch let error as OllamaError {
            throw error
        } catch {
            throw OllamaError.networkError(error)
        }
    }
}

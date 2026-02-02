//
//  OllamaService.swift
//  BlompieTV
//
//  Network service for communicating with Ollama and OpenWebUI
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

enum AIServerType: String, Codable, CaseIterable {
    case ollama = "Ollama"
    case openwebui = "OpenWebUI"
}

@MainActor
class OllamaService: ObservableObject {
    @Published var serverAddress: String = "" {
        didSet {
            UserDefaults.standard.set(serverAddress, forKey: "BlompieTVServerAddress")
        }
    }
    @Published var serverPort: Int = 11434 {
        didSet {
            UserDefaults.standard.set(serverPort, forKey: "BlompieTVServerPort")
        }
    }
    @Published var serverType: AIServerType = .ollama {
        didSet {
            UserDefaults.standard.set(serverType.rawValue, forKey: "BlompieTVServerType")
        }
    }
    @Published var isConnected: Bool = false
    @Published var connectionStatus: String = "Not configured"

    var model: String = "mistral"
    var temperature: Double = 0.7
    var maxTokens: Int? = nil

    var baseURL: String {
        guard !serverAddress.isEmpty else { return "" }
        return "http://\(serverAddress):\(serverPort)"
    }

    // Custom URLSession with extended timeout for model loading
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes for request
        config.timeoutIntervalForResource = 600 // 10 minutes for resource
        return URLSession(configuration: config)
    }()

    init() {
        loadSettings()
    }

    private func loadSettings() {
        if let address = UserDefaults.standard.string(forKey: "BlompieTVServerAddress") {
            serverAddress = address
        }
        serverPort = UserDefaults.standard.integer(forKey: "BlompieTVServerPort")
        if serverPort == 0 { serverPort = 11434 }

        if let typeString = UserDefaults.standard.string(forKey: "BlompieTVServerType"),
           let type = AIServerType(rawValue: typeString) {
            serverType = type
        }

        if !serverAddress.isEmpty {
            Task {
                await checkConnection()
            }
        }
    }

    func checkConnection() async {
        guard !serverAddress.isEmpty else {
            connectionStatus = "Not configured"
            isConnected = false
            return
        }

        connectionStatus = "Connecting..."

        do {
            let _ = try await fetchInstalledModels()
            isConnected = true
            connectionStatus = "Connected to \(serverType.rawValue)"
        } catch {
            isConnected = false
            connectionStatus = "Connection failed"
        }
    }

    func fetchInstalledModels() async throws -> [String] {
        guard !baseURL.isEmpty else {
            throw OllamaError.noServerConfigured
        }

        let endpoint: String
        switch serverType {
        case .ollama:
            endpoint = "\(baseURL)/api/tags"
        case .openwebui:
            endpoint = "\(baseURL)/api/models"
        }

        guard let url = URL(string: endpoint) else {
            throw OllamaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse(statusCode: nil, body: nil)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw OllamaError.invalidResponse(statusCode: httpResponse.statusCode, body: nil)
            }

            switch serverType {
            case .ollama:
                let modelsResponse = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
                return modelsResponse.models.map { $0.name }
            case .openwebui:
                let modelsResponse = try JSONDecoder().decode(OpenWebUIModelsResponse.self, from: data)
                return modelsResponse.allModels.map { $0.id }
            }

        } catch let error as OllamaError {
            throw error
        } catch {
            throw OllamaError.networkError(error)
        }
    }

    func chatStreaming(messages: [OllamaMessage], onChunk: @escaping (String) -> Void, onComplete: @escaping (Double?) -> Void) async throws {
        guard !baseURL.isEmpty else {
            throw OllamaError.noServerConfigured
        }

        let endpoint: String
        switch serverType {
        case .ollama:
            endpoint = "\(baseURL)/api/chat"
        case .openwebui:
            endpoint = "\(baseURL)/api/chat/completions"
        }

        guard let url = URL(string: endpoint) else {
            throw OllamaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let chatRequest = OllamaChatRequest(
            model: model,
            messages: messages,
            stream: true,
            options: OllamaOptions(temperature: temperature, num_predict: maxTokens)
        )

        request.httpBody = try JSONEncoder().encode(chatRequest)

        do {
            let (asyncBytes, response) = try await urlSession.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse(statusCode: nil, body: nil)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw OllamaError.invalidResponse(statusCode: httpResponse.statusCode, body: nil)
            }

            var buffer = ""
            var lastResponse: OllamaChatResponse?
            for try await byte in asyncBytes {
                let char = Character(UnicodeScalar(byte))
                buffer.append(char)

                if char == "\n" {
                    if let data = buffer.data(using: .utf8),
                       let streamResponse = try? JSONDecoder().decode(OllamaChatResponse.self, from: data) {
                        onChunk(streamResponse.message.content)
                        lastResponse = streamResponse
                    }
                    buffer = ""
                }
            }

            // Call completion handler with token/second metrics
            onComplete(lastResponse?.tokensPerSecond)

        } catch let error as OllamaError {
            throw error
        } catch {
            throw OllamaError.networkError(error)
        }
    }

    func chat(messages: [OllamaMessage]) async throws -> String {
        guard !baseURL.isEmpty else {
            throw OllamaError.noServerConfigured
        }

        let endpoint: String
        switch serverType {
        case .ollama:
            endpoint = "\(baseURL)/api/chat"
        case .openwebui:
            endpoint = "\(baseURL)/api/chat/completions"
        }

        guard let url = URL(string: endpoint) else {
            throw OllamaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let chatRequest = OllamaChatRequest(
            model: model,
            messages: messages,
            stream: false,
            options: OllamaOptions(temperature: temperature, num_predict: maxTokens)
        )

        request.httpBody = try JSONEncoder().encode(chatRequest)

        do {
            let (data, response) = try await urlSession.data(for: request)
            let bodyString = String(data: data, encoding: .utf8)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse(statusCode: nil, body: bodyString)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw OllamaError.invalidResponse(statusCode: httpResponse.statusCode, body: bodyString)
            }

            do {
                let chatResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
                return chatResponse.message.content
            } catch let decodingError as DecodingError {
                throw OllamaError.decodingError(decodingError, responseBody: bodyString)
            }

        } catch let error as OllamaError {
            throw error
        } catch {
            throw OllamaError.networkError(error)
        }
    }
}

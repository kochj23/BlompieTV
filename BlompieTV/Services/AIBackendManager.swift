//
//  AIBackendManager.swift
//  BlompieTV
//
//  Standardized AI Backend Manager for local LLM services
//  Supports: Ollama, TinyLLM, TinyChat, OpenWebUI, MLX
//
//  Author: Jordan Koch
//  Date: 2026-02-05
//
//  THIRD-PARTY INTEGRATIONS:
//  - TinyLLM by Jason Cox (https://github.com/jasonacox/TinyLLM)
//  - TinyChat by Jason Cox (https://github.com/jasonacox/tinychat)
//  - OpenWebUI Community (https://github.com/open-webui/open-webui)
//

import Foundation
import SwiftUI
import Combine

// MARK: - AI Backend Type

enum AIBackend: String, CaseIterable, Codable {
    case ollama = "Ollama"
    case tinyLLM = "TinyLLM"
    case tinyChat = "TinyChat"
    case openWebUI = "OpenWebUI"
    case auto = "Auto (Prefer Ollama)"

    var icon: String {
        switch self {
        case .ollama: return "network"
        case .tinyLLM: return "cube"
        case .tinyChat: return "bubble.left.and.bubble.right.fill"
        case .openWebUI: return "globe"
        case .auto: return "sparkles"
        }
    }

    var description: String {
        switch self {
        case .ollama:
            return "HTTP-based API (Ollama running on localhost:11434)"
        case .tinyLLM:
            return "TinyLLM lightweight server by Jason Cox (localhost:8000)"
        case .tinyChat:
            return "TinyChat fast chatbot interface by Jason Cox (localhost:8000)"
        case .openWebUI:
            return "OpenWebUI self-hosted AI platform (localhost:8080)"
        case .auto:
            return "Automatically choose best available backend"
        }
    }

    var attribution: String? {
        switch self {
        case .tinyLLM:
            return "TinyLLM by Jason Cox (https://github.com/jasonacox/TinyLLM)"
        case .tinyChat:
            return "TinyChat by Jason Cox (https://github.com/jasonacox/tinychat)"
        case .openWebUI:
            return "OpenWebUI Community Project (https://github.com/open-webui/open-webui)"
        default:
            return nil
        }
    }
}

// MARK: - AI Backend Manager

@MainActor
class AIBackendManager: ObservableObject {
    static let shared = AIBackendManager()

    // MARK: - Published Properties

    @Published var selectedBackend: AIBackend = .auto
    @Published var activeBackend: AIBackend?

    // Backend availability
    @Published var isOllamaAvailable = false
    @Published var isTinyLLMAvailable = false
    @Published var isTinyChatAvailable = false
    @Published var isOpenWebUIAvailable = false

    // Ollama configuration
    @Published var ollamaBaseURL = "http://localhost:11434"
    @Published var ollamaModels: [String] = []
    @Published var selectedOllamaModel = "mistral:latest"

    // Server URLs
    @Published var tinyLLMServerURL = "http://localhost:8000"
    @Published var tinyChatServerURL = "http://localhost:8000"
    @Published var openWebUIServerURL = "http://localhost:8080"

    // Settings keys
    private let settingsKey = "BlompieTVAIBackendSettings"

    // MARK: - Initialization

    private init() {
        loadSettings()
        Task {
            await checkBackendAvailability()
        }
    }

    // MARK: - Settings Persistence

    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let settings = try? JSONDecoder().decode(AIBackendSettings.self, from: data) {
            selectedBackend = settings.selectedBackend
            ollamaBaseURL = settings.ollamaBaseURL
            selectedOllamaModel = settings.selectedOllamaModel
            tinyLLMServerURL = settings.tinyLLMServerURL
            tinyChatServerURL = settings.tinyChatServerURL
            openWebUIServerURL = settings.openWebUIServerURL
        }
    }

    func saveSettings() {
        let settings = AIBackendSettings(
            selectedBackend: selectedBackend,
            ollamaBaseURL: ollamaBaseURL,
            selectedOllamaModel: selectedOllamaModel,
            tinyLLMServerURL: tinyLLMServerURL,
            tinyChatServerURL: tinyChatServerURL,
            openWebUIServerURL: openWebUIServerURL
        )
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    // MARK: - Backend Availability

    func checkBackendAvailability() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.checkOllama() }
            group.addTask { await self.checkTinyLLM() }
            group.addTask { await self.checkTinyChat() }
            group.addTask { await self.checkOpenWebUI() }
        }

        // Determine active backend
        determineActiveBackend()
    }

    private func checkOllama() async {
        guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else {
            isOllamaAvailable = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                isOllamaAvailable = false
                return
            }

            struct ModelsResponse: Codable {
                struct Model: Codable {
                    let name: String
                }
                let models: [Model]
            }

            let decoder = JSONDecoder()
            let modelsResponse = try decoder.decode(ModelsResponse.self, from: data)
            ollamaModels = modelsResponse.models.map { $0.name }
            isOllamaAvailable = true

            if !ollamaModels.contains(selectedOllamaModel) && !ollamaModels.isEmpty {
                selectedOllamaModel = ollamaModels[0]
            }
        } catch {
            isOllamaAvailable = false
        }
    }

    private func checkTinyLLM() async {
        guard let url = URL(string: "\(tinyLLMServerURL)/v1/models") else {
            isTinyLLMAvailable = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                isTinyLLMAvailable = true
            } else {
                isTinyLLMAvailable = false
            }
        } catch {
            isTinyLLMAvailable = false
        }
    }

    private func checkTinyChat() async {
        guard let url = URL(string: "\(tinyChatServerURL)/api/health") else {
            isTinyChatAvailable = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                isTinyChatAvailable = true
            } else {
                isTinyChatAvailable = false
            }
        } catch {
            isTinyChatAvailable = false
        }
    }

    private func checkOpenWebUI() async {
        guard let url = URL(string: "\(openWebUIServerURL)/api/models") else {
            isOpenWebUIAvailable = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                isOpenWebUIAvailable = true
            } else {
                isOpenWebUIAvailable = false
            }
        } catch {
            isOpenWebUIAvailable = false
        }
    }

    private func determineActiveBackend() {
        switch selectedBackend {
        case .auto:
            if isOllamaAvailable {
                activeBackend = .ollama
            } else if isTinyLLMAvailable {
                activeBackend = .tinyLLM
            } else if isTinyChatAvailable {
                activeBackend = .tinyChat
            } else if isOpenWebUIAvailable {
                activeBackend = .openWebUI
            } else {
                activeBackend = nil
            }
        case .ollama:
            activeBackend = isOllamaAvailable ? .ollama : nil
        case .tinyLLM:
            activeBackend = isTinyLLMAvailable ? .tinyLLM : nil
        case .tinyChat:
            activeBackend = isTinyChatAvailable ? .tinyChat : nil
        case .openWebUI:
            activeBackend = isOpenWebUIAvailable ? .openWebUI : nil
        }
    }

    // MARK: - Generation

    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Float = 0.7,
        maxTokens: Int = 2048
    ) async throws -> String {
        guard let backend = activeBackend else {
            throw AIBackendError.noBackendAvailable
        }

        switch backend {
        case .ollama:
            return try await generateWithOllama(prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .tinyLLM:
            return try await generateWithTinyLLM(prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .tinyChat:
            return try await generateWithTinyChat(prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .openWebUI:
            return try await generateWithOpenWebUI(prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .auto:
            throw AIBackendError.invalidState
        }
    }

    // MARK: - Ollama Implementation

    private func generateWithOllama(
        prompt: String,
        systemPrompt: String?,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: "\(ollamaBaseURL)/api/generate") else {
            throw AIBackendError.invalidConfiguration
        }

        var fullPrompt = ""
        if let systemPrompt = systemPrompt {
            fullPrompt = "System: \(systemPrompt)\n\nUser: \(prompt)"
        } else {
            fullPrompt = prompt
        }

        let requestBody: [String: Any] = [
            "model": selectedOllamaModel,
            "prompt": fullPrompt,
            "stream": false,
            "options": [
                "temperature": temperature,
                "num_predict": maxTokens
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct OllamaResponse: Codable {
            let response: String
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(OllamaResponse.self, from: data)
        return response.response
    }

    // MARK: - TinyLLM Implementation

    private func generateWithTinyLLM(
        prompt: String,
        systemPrompt: String?,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: "\(tinyLLMServerURL)/v1/chat/completions") else {
            throw AIBackendError.invalidConfiguration
        }

        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let requestBody: [String: Any] = [
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct TinyLLMResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(TinyLLMResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    // MARK: - TinyChat Implementation

    private func generateWithTinyChat(
        prompt: String,
        systemPrompt: String?,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: "\(tinyChatServerURL)/api/chat/stream") else {
            throw AIBackendError.invalidConfiguration
        }

        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let requestBody: [String: Any] = [
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct TinyChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(TinyChatResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    // MARK: - OpenWebUI Implementation

    private func generateWithOpenWebUI(
        prompt: String,
        systemPrompt: String?,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: "\(openWebUIServerURL)/api/chat/completions") else {
            throw AIBackendError.invalidConfiguration
        }

        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let requestBody: [String: Any] = [
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct OpenWebUIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(OpenWebUIResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }
}

// MARK: - Settings Model

struct AIBackendSettings: Codable {
    var selectedBackend: AIBackend
    var ollamaBaseURL: String
    var selectedOllamaModel: String
    var tinyLLMServerURL: String
    var tinyChatServerURL: String
    var openWebUIServerURL: String
}

// MARK: - Errors

enum AIBackendError: LocalizedError {
    case noBackendAvailable
    case invalidConfiguration
    case invalidState
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noBackendAvailable:
            return "No AI backend available. Check that Ollama, TinyLLM, TinyChat, or OpenWebUI is running."
        case .invalidConfiguration:
            return "AI backend configuration is invalid."
        case .invalidState:
            return "AI backend is in an invalid state."
        case .generationFailed(let message):
            return "AI generation failed: \(message)"
        }
    }
}

// MARK: - Settings View

struct AIBackendSettingsView: View {
    @ObservedObject var manager = AIBackendManager.shared
    @State private var isChecking = false

    var body: some View {
        Form {
            Section(header: Text("AI Backend Selection")) {
                Picker("Backend", selection: $manager.selectedBackend) {
                    ForEach(AIBackend.allCases, id: \.self) { backend in
                        HStack {
                            Image(systemName: backend.icon)
                            Text(backend.rawValue)
                        }
                        .tag(backend)
                    }
                }
                .onChange(of: manager.selectedBackend) { _ in
                    manager.saveSettings()
                    Task {
                        await manager.checkBackendAvailability()
                    }
                }

                Text(manager.selectedBackend.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Backend Status")) {
                HStack {
                    Circle()
                        .fill(manager.activeBackend != nil ? .green : .red)
                        .frame(width: 10, height: 10)

                    if let active = manager.activeBackend {
                        Text("Active: \(active.rawValue)")
                            .foregroundColor(.green)
                    } else {
                        Text("No backend available")
                            .foregroundColor(.red)
                    }
                }

                StatusRow(name: "Ollama", icon: "network", isAvailable: manager.isOllamaAvailable)
                StatusRow(name: "TinyLLM", icon: "cube", isAvailable: manager.isTinyLLMAvailable)
                StatusRow(name: "TinyChat", icon: "bubble.left.and.bubble.right.fill", isAvailable: manager.isTinyChatAvailable)
                StatusRow(name: "OpenWebUI", icon: "globe", isAvailable: manager.isOpenWebUIAvailable)

                Button("Refresh Status") {
                    isChecking = true
                    Task {
                        await manager.checkBackendAvailability()
                        isChecking = false
                    }
                }
                .disabled(isChecking)
            }

            if manager.isOllamaAvailable {
                Section(header: Text("Ollama Configuration")) {
                    Picker("Model", selection: $manager.selectedOllamaModel) {
                        ForEach(manager.ollamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .onChange(of: manager.selectedOllamaModel) { _ in
                        manager.saveSettings()
                    }
                }
            }

            Section(header: Text("Server URLs")) {
                TextField("Ollama URL", text: $manager.ollamaBaseURL)
                    .onChange(of: manager.ollamaBaseURL) { _ in manager.saveSettings() }

                TextField("TinyLLM URL", text: $manager.tinyLLMServerURL)
                    .onChange(of: manager.tinyLLMServerURL) { _ in manager.saveSettings() }

                TextField("TinyChat URL", text: $manager.tinyChatServerURL)
                    .onChange(of: manager.tinyChatServerURL) { _ in manager.saveSettings() }

                TextField("OpenWebUI URL", text: $manager.openWebUIServerURL)
                    .onChange(of: manager.openWebUIServerURL) { _ in manager.saveSettings() }
            }

            Section(header: Text("Credits")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Third-Party Integrations:")
                        .font(.headline)

                    Link("TinyLLM by Jason Cox", destination: URL(string: "https://github.com/jasonacox/TinyLLM")!)
                    Link("TinyChat by Jason Cox", destination: URL(string: "https://github.com/jasonacox/tinychat")!)
                    Link("OpenWebUI Community", destination: URL(string: "https://github.com/open-webui/open-webui")!)
                }
                .font(.caption)
            }
        }
    }
}

struct StatusRow: View {
    let name: String
    let icon: String
    let isAvailable: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(name)
            Spacer()
            Text(isAvailable ? "Available" : "Unavailable")
                .foregroundColor(isAvailable ? .green : .secondary)
        }
    }
}

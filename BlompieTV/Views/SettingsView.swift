//
//  SettingsView.swift
//  BlompieTV
//
//  Settings and server configuration view for tvOS
//  Created by Jordan Koch on 2/2/2026.
//  Copyright 2026 Jordan Koch. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var gameEngine: GameEngine
    @Binding var isPresented: Bool
    @StateObject private var serverDiscovery = ServerDiscovery()
    @State private var selectedTab: Int
    @State private var openRouterKeyInput: String = ""
    @State private var openAIKeyInput: String = ""

    private var balancer: LLMBalancerManager { gameEngine.ai }

    /// Tabs: 0 AI, 1 Game, 2 Model, 3 Cloud.
    init(gameEngine: GameEngine, isPresented: Binding<Bool>, initialTab: Int = 0) {
        self.gameEngine = gameEngine
        self._isPresented = isPresented
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            content
        }
    }

    /// Everything inside the navigation container (rendered directly by frame tests).
    var content: some View {
            ZStack {
                TVBackground()
                    .ignoresSafeArea()

                VStack(spacing: 40) {
                    // Header
                    Text("Settings")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    // Tab picker
                    Picker("Settings Section", selection: $selectedTab) {
                        Text("AI").tag(0)
                        Text("Game").tag(1)
                        Text("Model").tag(2)
                        Text("Cloud").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 200)

                    ScrollView {
                        section(for: selectedTab)
                            .padding(40)
                    }

                    // Done button
                    Button("Done") {
                        isPresented = false
                    }
                    .buttonStyle(TVPrimaryButtonStyle())
                    .padding(.bottom, 40)
                }
            }
    }

    /// The cards of one tab (0 AI, 1 Game, 2 Model, 3 Cloud).
    @ViewBuilder
    func section(for tab: Int) -> some View {
        VStack(spacing: 30) {
            switch tab {
            case 0: aiSettingsSection
            case 1: gameSettingsSection
            case 2: modelSettingsSection
            default: cloudSettingsSection
            }
        }
    }

    // MARK: - AI Settings

    private var aiSettingsSection: some View {
        VStack(spacing: 30) {
            // Global AI switch
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Use AI narrator", isOn: $gameEngine.aiEnabled)
                    .font(.system(size: 26, design: .monospaced))
                    .tint(TVColors.cyan)
                    .onChange(of: gameEngine.aiEnabled) { _, _ in
                        gameEngine.saveSettings()
                    }
                Text("Off: every turn is told by the built-in scripted narrator and nothing is sent over the network. On: if no backend answers, the scripted narrator steps in for that turn.")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .foregroundColor(.white)
            .padding(30)
            .background(settingsCardBackground)

            // Status + test
            HStack(spacing: 20) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text(gameEngine.aiEnabled ? balancer.statusText : "AI off")
                        .font(.system(size: 28, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Backend: \(balancer.selectedBackend.displayName)")
                        .font(.system(size: 20, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Button(balancer.isCheckingStatus ? "Testing..." : "Test Connection") {
                    Task {
                        await balancer.refreshStatus()
                        await gameEngine.refreshAvailableModels()
                    }
                }
                .buttonStyle(TVSecondaryButtonStyle())
                .disabled(balancer.isCheckingStatus)
            }
            .padding(30)
            .background(settingsCardBackground)

            // Backend picker
            VStack(alignment: .leading, spacing: 16) {
                Text("Backend")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                ForEach(LLMBackendType.pickerCases, id: \.self) { backend in
                    Button(action: {
                        balancer.selectedBackend = backend
                        Task {
                            await balancer.refreshStatus()
                            await gameEngine.refreshAvailableModels()
                        }
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: backend.icon)
                                .foregroundColor(TVColors.cyan)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(backend.displayName)
                                    .font(.system(size: 24, design: .monospaced))
                                    .foregroundColor(.white)
                                Text(backend.description)
                                    .font(.system(size: 17, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.55))
                                    .lineLimit(2)
                            }
                            Spacer()
                            if backend != .auto {
                                Circle()
                                    .fill(healthColor(backend))
                                    .frame(width: 14, height: 14)
                            }
                            if backend == balancer.selectedBackend {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(TVColors.cyan)
                                    .font(.system(size: 28))
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(backend == balancer.selectedBackend ? TVColors.cyan.opacity(0.2) : Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(TVButtonStyle())
                }
            }
            .padding(30)
            .background(settingsCardBackground)

            // Endpoint URLs
            VStack(alignment: .leading, spacing: 16) {
                Text("Endpoints")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("Use your Mac's or server's LAN address, e.g. http://192.168.1.20:11434. localhost means the Apple TV itself.")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                endpointField("Ollama", text: binding(for: .ollama))
                endpointField("TinyLLM", text: binding(for: .tinyLLM))
                endpointField("TinyChat", text: binding(for: .tinyChat))
                endpointField("OpenWebUI", text: binding(for: .openWebUI))
                endpointField("Nova Gateway", text: binding(for: .novaGateway))
                endpointField("OpenAI (https)", text: binding(for: .openAI))

                if !LLMBalancerManager.isValidEndpoint(balancer.url(for: .openAI), requireHTTPS: true) {
                    Text("The OpenAI URL must start with https:// - keys are never sent over http.")
                        .font(.system(size: 20, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
            .padding(30)
            .background(settingsCardBackground)

            // Auto-Discovery
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Discover Servers")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()

                    Button(serverDiscovery.isSearching ? "Searching..." : "Scan Network") {
                        serverDiscovery.startDiscovery()
                    }
                    .buttonStyle(TVSecondaryButtonStyle())
                    .disabled(serverDiscovery.isSearching)
                }

                if serverDiscovery.isSearching {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: TVColors.cyan))
                        Text("Scanning network for AI servers...")
                            .font(.system(size: 22, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                if !serverDiscovery.discoveredServers.isEmpty {
                    Text("Found Servers:")
                        .font(.system(size: 24, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))

                    ForEach(serverDiscovery.discoveredServers) { server in
                        Button(action: {
                            balancer.setURL("http://\(server.host):\(server.port)", for: server.type.backend)
                            balancer.selectedBackend = server.type.backend
                            Task {
                                await balancer.refreshStatus()
                                await gameEngine.refreshAvailableModels()
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(server.name)
                                        .font(.system(size: 24, design: .monospaced))
                                        .foregroundColor(.white)

                                    Text("\(server.host):\(server.port) - \(server.type.rawValue)")
                                        .font(.system(size: 20, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                }

                                Spacer()

                                Text("Use")
                                    .foregroundColor(TVColors.cyan)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(TVButtonStyle())
                    }
                } else if !serverDiscovery.isSearching {
                    Text("No servers found yet. Scan finds Ollama and OpenWebUI on your network.")
                        .font(.system(size: 20, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(30)
            .background(settingsCardBackground)
        }
    }

    private var statusColor: Color {
        guard gameEngine.aiEnabled else { return .gray }
        return balancer.activeBackend != nil ? .green : .orange
    }

    private func healthColor(_ backend: LLMBackendType) -> Color {
        switch balancer.backendHealth[backend] {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .gray
        }
    }

    private func binding(for backend: LLMBackendType) -> Binding<String> {
        Binding(get: { balancer.url(for: backend) }, set: { balancer.setURL($0, for: backend) })
    }

    private func endpointField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 20) {
            Text(label)
                .font(.system(size: 22, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 260, alignment: .leading)
            TextField(label, text: text)
                .textFieldStyle(TVTextFieldStyle())
        }
    }

    // MARK: - Game Settings

    private var gameSettingsSection: some View {
        VStack(spacing: 30) {
            // Font Size - using buttons instead of slider for tvOS
            VStack(alignment: .leading, spacing: 20) {
                Text("Font Size: \(Int(gameEngine.fontSize))pt")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                HStack(spacing: 30) {
                    Button("Smaller") {
                        if gameEngine.fontSize > 20 {
                            gameEngine.fontSize -= 2
                            gameEngine.saveSettings()
                        }
                    }
                    .buttonStyle(TVSecondaryButtonStyle())

                    // Font size indicator
                    Text("\(Int(gameEngine.fontSize))pt")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(TVColors.cyan)
                        .frame(width: 100)

                    Button("Larger") {
                        if gameEngine.fontSize < 48 {
                            gameEngine.fontSize += 2
                            gameEngine.saveSettings()
                        }
                    }
                    .buttonStyle(TVSecondaryButtonStyle())
                }
            }
            .padding(30)
            .background(settingsCardBackground)

            // Response Style
            VStack(alignment: .leading, spacing: 20) {
                Text("Response Style")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("Detail Level")
                    .font(.system(size: 24, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Picker("Detail Level", selection: $gameEngine.detailLevel) {
                    ForEach(DetailLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: gameEngine.detailLevel) { _, _ in
                    gameEngine.saveSettings()
                }

                Text("Tone")
                    .font(.system(size: 24, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.top, 10)

                Picker("Tone", selection: $gameEngine.toneStyle) {
                    ForEach(ToneStyle.allCases, id: \.self) { tone in
                        Text(tone.rawValue).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: gameEngine.toneStyle) { _, _ in
                    gameEngine.saveSettings()
                }
            }
            .padding(30)
            .background(settingsCardBackground)

            // Toggles
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Enable Streaming", isOn: $gameEngine.streamingEnabled)
                    .font(.system(size: 26, design: .monospaced))
                    .tint(TVColors.cyan)
                    .onChange(of: gameEngine.streamingEnabled) { _, _ in
                        gameEngine.saveSettings()
                    }

                Toggle("Auto-Save", isOn: $gameEngine.autoSaveEnabled)
                    .font(.system(size: 26, design: .monospaced))
                    .tint(TVColors.cyan)
                    .onChange(of: gameEngine.autoSaveEnabled) { _, _ in
                        gameEngine.saveSettings()
                    }
            }
            .foregroundColor(.white)
            .padding(30)
            .background(settingsCardBackground)

            // Reset
            VStack(alignment: .leading, spacing: 20) {
                Text("Reset")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Button("Reset All Settings") {
                    gameEngine.resetSettings()
                }
                .buttonStyle(TVDestructiveButtonStyle())
            }
            .padding(30)
            .background(settingsCardBackground)
        }
    }

    // MARK: - Model Settings

    private var modelSettingsSection: some View {
        VStack(spacing: 30) {
            // Model Selection
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("AI Model (\(balancer.modelPickerBackend.displayName))")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()

                    Button("Refresh") {
                        Task {
                            await gameEngine.refreshAvailableModels()
                        }
                    }
                    .buttonStyle(TVSecondaryButtonStyle())
                }

                if gameEngine.availableModels.isEmpty {
                    Text("Test the connection in the AI tab to list models")
                        .font(.system(size: 22, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    ForEach(gameEngine.availableModels, id: \.self) { model in
                        Button(action: {
                            gameEngine.selectedModel = model
                            gameEngine.saveSettings()
                        }) {
                            HStack {
                                Text(model)
                                    .font(.system(size: 24, design: .monospaced))
                                    .foregroundColor(.white)

                                Spacer()

                                if model == gameEngine.selectedModel {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(TVColors.cyan)
                                        .font(.system(size: 28))
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(model == gameEngine.selectedModel ? TVColors.cyan.opacity(0.2) : Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(TVButtonStyle())
                    }
                }
            }
            .padding(30)
            .background(settingsCardBackground)

            // Temperature - using buttons instead of slider for tvOS
            VStack(alignment: .leading, spacing: 20) {
                Text("Creativity: \(String(format: "%.1f", gameEngine.temperature))")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("Higher values = more creative, lower = more focused")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                HStack(spacing: 30) {
                    Button("Less Creative") {
                        if gameEngine.temperature > 0.1 {
                            gameEngine.temperature -= 0.1
                            gameEngine.saveSettings()
                        }
                    }
                    .buttonStyle(TVSecondaryButtonStyle())

                    Text(String(format: "%.1f", gameEngine.temperature))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(TVColors.cyan)
                        .frame(width: 80)

                    Button("More Creative") {
                        if gameEngine.temperature < 2.0 {
                            gameEngine.temperature += 0.1
                            gameEngine.saveSettings()
                        }
                    }
                    .buttonStyle(TVSecondaryButtonStyle())
                }
            }
            .padding(30)
            .background(settingsCardBackground)

            // Random Model Mode
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Random Model Mode", isOn: $gameEngine.randomModelMode)
                    .font(.system(size: 26, design: .monospaced))
                    .tint(TVColors.cyan)
                    .onChange(of: gameEngine.randomModelMode) { _, _ in
                        gameEngine.saveSettings()
                    }

                Text("Automatically switch between models for varied storytelling")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                if gameEngine.randomModelMode {
                    HStack {
                        Text("Switch every")
                            .font(.system(size: 22, design: .monospaced))

                        Picker("", selection: $gameEngine.actionsUntilModelSwitch) {
                            Text("3").tag(3)
                            Text("5").tag(5)
                            Text("10").tag(10)
                            Text("15").tag(15)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: gameEngine.actionsUntilModelSwitch) { _, _ in
                            gameEngine.saveSettings()
                        }

                        Text("actions")
                            .font(.system(size: 22, design: .monospaced))
                    }
                    .foregroundColor(.white)
                }
            }
            .foregroundColor(.white)
            .padding(30)
            .background(settingsCardBackground)
        }
    }

    // MARK: - Cloud / Multi-Model Balancer Settings

    private var cloudSettingsSection: some View {
        VStack(spacing: 30) {
            // Three balancer toggles
            VStack(alignment: .leading, spacing: 20) {
                Text("Load Balancing")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("Off by default. Turn these on to spread each turn across more models. If the pool fails, the backend chosen in the AI tab is used, then the scripted narrator.")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Toggle("All Local Models (Ollama)", isOn: Binding(get: { balancer.useAllLocalModels }, set: { balancer.useAllLocalModels = $0 }))
                    .font(.system(size: 26, design: .monospaced))
                    .tint(TVColors.cyan)

                Toggle("All Frontier Models (OpenRouter)", isOn: Binding(get: { balancer.enableAllFrontierModels }, set: { balancer.enableAllFrontierModels = $0 }))
                    .font(.system(size: 26, design: .monospaced))
                    .tint(TVColors.cyan)

                if balancer.enableAllFrontierModels && !balancer.hasOpenRouterKey {
                    Text("Add your OpenRouter key below to enable frontier models.")
                        .font(.system(size: 20, design: .monospaced))
                        .foregroundColor(.orange)
                }

                Toggle("Nova Gateway (optional)", isOn: Binding(get: { balancer.useNovaGateway }, set: { balancer.useNovaGateway = $0 }))
                    .font(.system(size: 26, design: .monospaced))
                    .tint(TVColors.cyan)

                Text("Nova is never required. If its health check fails it is simply dropped from the pool.")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .foregroundColor(.white)
            .padding(30)
            .background(settingsCardBackground)

            // API keys (Keychain-backed)
            apiKeyCard(
                title: "OpenRouter API Key",
                placeholder: "sk-or-...",
                backend: .openRouter,
                input: $openRouterKeyInput
            )
            apiKeyCard(
                title: "OpenAI API Key",
                placeholder: "sk-...",
                backend: .openAI,
                input: $openAIKeyInput
            )

            // Nova Gateway status
            VStack(alignment: .leading, spacing: 20) {
                Text("Nova Gateway")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text(balancer.url(for: .novaGateway))
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                HStack {
                    Circle()
                        .fill(balancer.isNovaGatewayAvailable ? Color.green : Color.gray)
                        .frame(width: 20, height: 20)

                    Text(balancer.isNovaGatewayAvailable ? "Reachable" : "Unknown / unreachable")
                        .font(.system(size: 22, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    Button("Refresh Pool") {
                        Task {
                            _ = await balancer.checkAvailability(.novaGateway)
                            await balancer.discoverEnabledPool()
                        }
                    }
                    .buttonStyle(TVSecondaryButtonStyle())
                }
            }
            .padding(30)
            .background(settingsCardBackground)

            // Discovered pool preview
            VStack(alignment: .leading, spacing: 20) {
                Text("Discovered Pool (\(balancer.discoveredModels.count))")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                if balancer.discoveredModels.isEmpty {
                    Text("Enable a toggle and refresh to see the balanced model pool.")
                        .font(.system(size: 20, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    ForEach(balancer.discoveredModels) { model in
                        HStack {
                            Image(systemName: model.backend.icon)
                                .foregroundColor(TVColors.cyan)
                            Text(model.displayName)
                                .font(.system(size: 22, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                            Text(model.backend.displayName)
                                .font(.system(size: 18, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(30)
            .background(settingsCardBackground)
        }
    }

    /// Key entry on tvOS: selecting the SecureField opens the system on-screen
    /// keyboard; with an iPhone signed in to the same Apple Account, the
    /// "Apple TV Keyboard" notification lets you type or paste the key on the phone.
    private func apiKeyCard(title: String, placeholder: String, backend: LLMBackendType, input: Binding<String>) -> some View {
        let stored = balancer.hasAPIKey(for: backend)
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                Circle()
                    .fill(stored ? Color.green : Color.gray)
                    .frame(width: 20, height: 20)

                Text(stored ? "Stored" : "Not set")
                    .font(.system(size: 22, design: .monospaced))
                    .foregroundColor(stored ? .green : .white.opacity(0.5))
            }

            HStack(spacing: 20) {
                SecureField(placeholder, text: input)
                    .textFieldStyle(TVTextFieldStyle())

                Button("Save") {
                    balancer.setAPIKey(input.wrappedValue, for: backend)
                    input.wrappedValue = ""
                    if backend == .openRouter {
                        Task { await balancer.refreshOpenRouterModels() }
                    }
                }
                .buttonStyle(TVSecondaryButtonStyle())

                Button("Clear") {
                    balancer.setAPIKey("", for: backend)
                    input.wrappedValue = ""
                }
                .buttonStyle(TVDestructiveButtonStyle())
            }

            Text("Select the field to open the on-screen keyboard. Easier: an iPhone on the same Apple Account shows an Apple TV Keyboard notification, so you can type or paste the key there. Stored only in the Apple TV Keychain, sent only over https.")
                .font(.system(size: 20, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(30)
        .background(settingsCardBackground)
    }

    private var settingsCardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.black.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - TV Button Styles for Settings

struct TVPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 28, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 48)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(TVColors.cyan)
            )
            .scaleEffect(configuration.isPressed ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TVCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 32, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 60, height: 60)
            .background(
                Circle()
                    .fill(TVColors.cyan.opacity(0.3))
            )
            .scaleEffect(configuration.isPressed ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TVDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.6))
            )
            .scaleEffect(configuration.isPressed ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TVTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 24, design: .monospaced))
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
    }
}

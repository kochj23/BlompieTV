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
    @State private var manualAddress: String = ""
    @State private var manualPort: String = ""
    @State private var selectedTab = 0
    @State private var selectedServerType: AIServerType = .ollama

    var body: some View {
        NavigationStack {
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
                        Text("Server").tag(0)
                        Text("Game").tag(1)
                        Text("Model").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 200)

                    ScrollView {
                        VStack(spacing: 30) {
                            if selectedTab == 0 {
                                serverSettingsSection
                            } else if selectedTab == 1 {
                                gameSettingsSection
                            } else {
                                modelSettingsSection
                            }
                        }
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
        .onAppear {
            manualAddress = gameEngine.ollamaService.serverAddress
            manualPort = String(gameEngine.ollamaService.serverPort)
            selectedServerType = gameEngine.ollamaService.serverType
        }
    }

    // MARK: - Server Settings

    private var serverSettingsSection: some View {
        VStack(spacing: 30) {
            // Connection status
            HStack(spacing: 20) {
                Circle()
                    .fill(gameEngine.ollamaService.isConnected ? Color.green : Color.red)
                    .frame(width: 24, height: 24)

                Text(gameEngine.ollamaService.connectionStatus)
                    .font(.system(size: 28, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                Button("Test Connection") {
                    Task {
                        await gameEngine.ollamaService.checkConnection()
                    }
                }
                .buttonStyle(TVSecondaryButtonStyle())
            }
            .padding(30)
            .background(settingsCardBackground)

            // Server Type
            VStack(alignment: .leading, spacing: 20) {
                Text("Server Type")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Picker("Server Type", selection: $selectedServerType) {
                    ForEach(AIServerType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedServerType) { _, newValue in
                    gameEngine.ollamaService.serverType = newValue
                }
            }
            .padding(30)
            .background(settingsCardBackground)

            // Manual Configuration
            VStack(alignment: .leading, spacing: 20) {
                Text("Server Address")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                HStack(spacing: 20) {
                    TextField("IP Address (e.g., 192.168.1.100)", text: $manualAddress)
                        .textFieldStyle(TVTextFieldStyle())

                    Text(":")
                        .font(.system(size: 28, design: .monospaced))
                        .foregroundColor(.white)

                    TextField("Port", text: $manualPort)
                        .textFieldStyle(TVTextFieldStyle())
                        .frame(width: 150)

                    Button("Save") {
                        gameEngine.ollamaService.serverAddress = manualAddress
                        gameEngine.ollamaService.serverPort = Int(manualPort) ?? 11434
                        Task {
                            await gameEngine.ollamaService.checkConnection()
                            await gameEngine.refreshAvailableModels()
                        }
                    }
                    .buttonStyle(TVSecondaryButtonStyle())
                }

                Text("Default ports: Ollama = 11434, OpenWebUI = 3000 or 8080")
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
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
                            gameEngine.ollamaService.serverAddress = server.host
                            gameEngine.ollamaService.serverPort = server.port
                            gameEngine.ollamaService.serverType = server.type
                            manualAddress = server.host
                            manualPort = String(server.port)
                            selectedServerType = server.type
                            Task {
                                await gameEngine.ollamaService.checkConnection()
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

                                Text("Select")
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
                    Text("No servers found. Make sure Ollama or OpenWebUI is running on your network.")
                        .font(.system(size: 20, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(30)
            .background(settingsCardBackground)
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
                    Text("AI Model")
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
                    Text("Connect to a server to see available models")
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

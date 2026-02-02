//
//  ContentView.swift
//  BlompieTV
//
//  Main UI adapted for tvOS with focus-based navigation
//  Created by Jordan Koch on 2/2/2026.
//  Copyright 2026 Jordan Koch. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var gameEngine = GameEngine()
    @State private var showSettings = false
    @State private var showSaveLoad = false
    @State private var showStats = false

    var body: some View {
        NavigationStack {
            ZStack {
                TVBackground()
                    .ignoresSafeArea()

                mainContent
            }
            .onAppear {
                handleOnAppear()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(gameEngine: gameEngine, isPresented: $showSettings)
            }
            .sheet(isPresented: $showSaveLoad) {
                SaveLoadView(gameEngine: gameEngine, isPresented: $showSaveLoad)
            }
            .sheet(isPresented: $showStats) {
                StatsView(gameEngine: gameEngine, isPresented: $showStats)
            }
            .alert("Error", isPresented: $gameEngine.showError) {
                Button("OK", role: .cancel) {}
                Button("Open Settings") {
                    showSettings = true
                }
            } message: {
                Text(gameEngine.errorMessage)
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 40) {
            HeaderView(gameEngine: gameEngine)

            HStack(spacing: 40) {
                StoryPanel(gameEngine: gameEngine)
                ActionsPanel(gameEngine: gameEngine)
            }
            .padding(.horizontal, 60)

            ToolbarView(
                gameEngine: gameEngine,
                showSettings: $showSettings,
                showSaveLoad: $showSaveLoad,
                showStats: $showStats
            )
        }
    }

    private func handleOnAppear() {
        gameEngine.loadGame(fromSlot: "autosave")
        if gameEngine.messages.isEmpty {
            if gameEngine.ollamaService.serverAddress.isEmpty {
                showSettings = true
            } else {
                gameEngine.startNewGame()
            }
        }
    }
}

// MARK: - Header View

struct HeaderView: View {
    @ObservedObject var gameEngine: GameEngine

    var body: some View {
        HStack {
            Text("BLOMPIE")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Spacer()

            connectionStatus
            tokenSpeed
        }
        .padding(.horizontal, 60)
        .padding(.top, 40)
    }

    private var connectionStatus: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(gameEngine.ollamaService.isConnected ? Color.green : Color.red)
                .frame(width: 16, height: 16)

            Text(gameEngine.ollamaService.connectionStatus)
                .font(.system(size: 24, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    @ViewBuilder
    private var tokenSpeed: some View {
        if gameEngine.lastTokensPerSecond > 0 {
            Text(String(format: "%.1f t/s", gameEngine.lastTokensPerSecond))
                .font(.system(size: 24, design: .monospaced))
                .foregroundColor(TVColors.cyan)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(TVColors.cyan.opacity(0.2))
                .cornerRadius(12)
        }
    }
}

// MARK: - Story Panel

struct StoryPanel: View {
    @ObservedObject var gameEngine: GameEngine

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    storyContent
                }
                .onChange(of: gameEngine.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: gameEngine.streamingText) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
        }
        .background(storyBackground)
        .frame(maxWidth: .infinity)
    }

    private var storyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(gameEngine.messages) { message in
                Text(message.text)
                    .font(.system(size: gameEngine.fontSize, design: .monospaced))
                    .foregroundColor(.white)
                    .id(message.id)
            }

            streamingTextView
            loadingView
        }
        .padding(30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var streamingTextView: some View {
        if !gameEngine.streamingText.isEmpty {
            Text(gameEngine.streamingText)
                .font(.system(size: gameEngine.fontSize, design: .monospaced))
                .foregroundColor(TVColors.cyan)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        if gameEngine.isLoading && gameEngine.streamingText.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: TVColors.cyan))
                Text("Thinking...")
                    .font(.system(size: gameEngine.fontSize, design: .monospaced))
                    .foregroundColor(TVColors.cyan.opacity(0.7))
            }
        }
    }

    private var storyBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.black.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(TVColors.cyan.opacity(0.3), lineWidth: 2)
            )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = gameEngine.messages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Actions Panel

struct ActionsPanel: View {
    @ObservedObject var gameEngine: GameEngine

    var body: some View {
        VStack(spacing: 24) {
            Text("Actions")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            actionsContent

            Spacer()

            quickActions
        }
        .padding(30)
        .frame(width: 500)
        .background(actionsPanelBackground)
    }

    @ViewBuilder
    private var actionsContent: some View {
        if !gameEngine.currentActions.isEmpty && !gameEngine.isLoading {
            ForEach(Array(gameEngine.currentActions.enumerated()), id: \.element) { index, action in
                ActionButton(index: index, action: action, gameEngine: gameEngine)
            }
        } else if gameEngine.isLoading {
            Text("Generating story...")
                .font(.system(size: 24, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(40)
        } else {
            Text("No actions available")
                .font(.system(size: 24, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(40)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 20) {
            Button("New Game") {
                gameEngine.startNewGame()
            }
            .buttonStyle(TVSecondaryButtonStyle())

            Button("Undo") {
                gameEngine.undoLastAction()
            }
            .buttonStyle(TVSecondaryButtonStyle())
            .disabled(gameEngine.stateHistory.isEmpty)
        }
    }

    private var actionsPanelBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.black.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let index: Int
    let action: String
    @ObservedObject var gameEngine: GameEngine

    var body: some View {
        Button(action: {
            gameEngine.performAction(action)
        }) {
            HStack {
                Text("[\(index + 1)]")
                    .foregroundColor(TVColors.cyan)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))

                Text(action)
                    .font(.system(size: 28, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(actionBackground)
        }
        .buttonStyle(TVButtonStyle())
    }

    private var actionBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(TVColors.cyan.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(TVColors.cyan.opacity(0.5), lineWidth: 2)
            )
    }
}

// MARK: - Toolbar View

struct ToolbarView: View {
    @ObservedObject var gameEngine: GameEngine
    @Binding var showSettings: Bool
    @Binding var showSaveLoad: Bool
    @Binding var showStats: Bool

    var body: some View {
        HStack(spacing: 40) {
            Button("Settings") {
                showSettings = true
            }
            .buttonStyle(TVToolbarButtonStyle())

            Button("Save/Load") {
                showSaveLoad = true
            }
            .buttonStyle(TVToolbarButtonStyle())

            Button("Stats") {
                showStats = true
            }
            .buttonStyle(TVToolbarButtonStyle())

            Spacer()

            modelIndicator
            achievementsIndicator
        }
        .padding(.horizontal, 60)
        .padding(.bottom, 40)
    }

    private var modelIndicator: some View {
        Text("Model: \(gameEngine.selectedModel)")
            .font(.system(size: 22, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
    }

    private var achievementsIndicator: some View {
        Text("Achievements: \(gameEngine.achievements.filter { $0.isUnlocked }.count)/\(gameEngine.achievements.count)")
            .font(.system(size: 22, design: .monospaced))
            .foregroundColor(TVColors.yellow)
    }
}

// MARK: - TV Color Scheme

struct TVColors {
    static let cyan = Color(red: 0.3, green: 0.85, blue: 0.95)
    static let yellow = Color(red: 1.0, green: 0.85, blue: 0.3)
    static let green = Color(red: 0.3, green: 0.9, blue: 0.6)
    static let orange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let purple = Color(red: 0.6, green: 0.4, blue: 0.95)

    static let gradientStart = Color(red: 0.05, green: 0.08, blue: 0.15)
    static let gradientEnd = Color(red: 0.1, green: 0.15, blue: 0.25)
}

// MARK: - TV Background

struct TVBackground: View {
    var body: some View {
        LinearGradient(
            colors: [TVColors.gradientStart, TVColors.gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(gridPattern)
    }

    private var gridPattern: some View {
        GeometryReader { geometry in
            Path { path in
                let spacing: CGFloat = 60
                for x in stride(from: 0, through: geometry.size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
                for y in stride(from: 0, through: geometry.size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.03), lineWidth: 1)
        }
    }
}

// MARK: - TV Button Styles

struct TVButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.05 : 1.0)
            .brightness(configuration.isPressed ? 0.1 : 0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TVSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(secondaryBackground)
            .scaleEffect(configuration.isPressed ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }

    private var secondaryBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
}

struct TVToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(toolbarBackground)
            .scaleEffect(configuration.isPressed ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }

    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(TVColors.cyan.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(TVColors.cyan.opacity(0.5), lineWidth: 1)
            )
    }
}

#Preview {
    ContentView()
}

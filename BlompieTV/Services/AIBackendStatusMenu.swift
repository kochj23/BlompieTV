import SwiftUI

//
//  AIBackendStatusMenu.swift
//  BlompieTV
//
//  AI Backend Status Menu for BlompieTV
//  Shows backend status, model selection, and quick settings access
//
//  Author: Jordan Koch
//  Date: 2026-01-26
//

struct AIBackendStatusMenu: View {
    @ObservedObject var manager = AIBackendManager.shared
    @State private var showSettings = false
    @State private var isRefreshing = false

    // Theme customization
    var accentColor: Color = .blue
    var compact: Bool = false
    var showModelPicker: Bool = true

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            // Status Indicator
            backendStatusIndicator

            // Backend Selector
            if !compact {
                backendSelector
            }

            // Model Selector (for Ollama)
            if showModelPicker && manager.activeBackend == .ollama && !manager.ollamaModels.isEmpty {
                modelSelector
            }

            // Action Buttons
            actionButtons
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
        .sheet(isPresented: $showSettings) {
            AIBackendSettingsView()
        }
    }

    // MARK: - Status Indicator

    private var backendStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                        .scaleEffect(isRefreshing ? 1.5 : 1.0)
                        .opacity(isRefreshing ? 0 : 1)
                        .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: isRefreshing)
                )

            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusColor)

                    if let backend = manager.activeBackend {
                        Text(backend.rawValue)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        if manager.activeBackend != nil {
            return .green
        } else if hasAnyConfigured {
            return .gray
        } else {
            return .red
        }
    }

    private var statusText: String {
        if manager.activeBackend != nil {
            return "Connected"
        } else if hasAnyConfigured {
            return "Configured"
        } else {
            return "Offline"
        }
    }

    private var hasAnyConfigured: Bool {
        manager.isOllamaAvailable || manager.isTinyLLMAvailable ||
        manager.isTinyChatAvailable || manager.isOpenWebUIAvailable
    }

    // MARK: - Backend Selector

    private var backendSelector: some View {
        Menu {
            ForEach(AIBackend.allCases, id: \.self) { backend in
                Button(action: {
                    manager.selectedBackend = backend
                    manager.saveSettings()
                    Task {
                        await manager.checkBackendAvailability()
                    }
                }) {
                    HStack {
                        Image(systemName: backend.icon)
                        Text(backend.rawValue)
                        Spacer()
                        if isBackendAvailable(backend) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            Divider()

            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gear")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text("Backend")
                    .font(.system(size: 11))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(accentColor)
        }
        .menuStyle(.borderlessButton)
        .frame(height: 24)
    }

    // MARK: - Model Selector

    private var modelSelector: some View {
        Menu {
            ForEach(manager.ollamaModels, id: \.self) { model in
                Button(action: {
                    manager.selectedOllamaModel = model
                    manager.saveSettings()
                }) {
                    HStack {
                        Text(model)
                        Spacer()
                        if manager.selectedOllamaModel == model {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                Text(truncateModelName(manager.selectedOllamaModel))
                    .font(.system(size: 11))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(accentColor)
        }
        .menuStyle(.borderlessButton)
        .frame(height: 24)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button(action: {
                isRefreshing = true
                Task {
                    await manager.checkBackendAvailability()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    isRefreshing = false
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(accentColor)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Refresh backend status")

            Button(action: { showSettings = true }) {
                Image(systemName: "gear")
                    .font(.system(size: 11))
                    .foregroundColor(accentColor)
            }
            .buttonStyle(.plain)
            .help("Configure AI backends")
        }
    }

    // MARK: - Helpers

    private func isBackendAvailable(_ backend: AIBackend) -> Bool {
        switch backend {
        case .ollama: return manager.isOllamaAvailable
        case .tinyLLM: return manager.isTinyLLMAvailable
        case .tinyChat: return manager.isTinyChatAvailable
        case .openWebUI: return manager.isOpenWebUIAvailable
        case .auto: return manager.activeBackend != nil
        }
    }

    private func truncateModelName(_ name: String) -> String {
        let parts = name.split(separator: ":")
        return String(parts.first ?? Substring(name))
    }
}

// MARK: - Compact Variant

struct AIBackendStatusMenuCompact: View {
    var body: some View {
        AIBackendStatusMenu(compact: true, showModelPicker: false)
    }
}

// MARK: - Preview

#if DEBUG
struct AIBackendStatusMenu_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AIBackendStatusMenu()
            AIBackendStatusMenu(accentColor: .green)
            AIBackendStatusMenu(compact: true)
        }
        .padding()
    }
}
#endif

//
//  SaveLoadView.swift
//  BlompieTV
//
//  Save and load game state view for tvOS
//  Created by Jordan Koch on 2/2/2026.
//  Copyright 2026 Jordan Koch. All rights reserved.
//

import SwiftUI

struct SaveLoadView: View {
    @ObservedObject var gameEngine: GameEngine
    @Binding var isPresented: Bool
    @State private var saveName: String = ""
    @State private var showDeleteConfirm: Bool = false
    @State private var slotToDelete: String = ""
    @FocusState private var isSaveNameFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                TVBackground()
                    .ignoresSafeArea()

                VStack(spacing: 40) {
                    // Header
                    Text("Save / Load Game")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    HStack(spacing: 60) {
                        // Save Section
                        VStack(spacing: 30) {
                            Text("Save Game")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(TVColors.cyan)

                            TextField("Enter save name", text: $saveName)
                                .textFieldStyle(TVTextFieldStyle())
                                .frame(width: 400)
                                .focused($isSaveNameFocused)

                            Button("Save") {
                                if !saveName.isEmpty {
                                    gameEngine.saveGame(toSlot: saveName)
                                    saveName = ""
                                    isSaveNameFocused = false
                                }
                            }
                            .buttonStyle(TVPrimaryButtonStyle())
                            .disabled(saveName.isEmpty)

                            Spacer()
                        }
                        .padding(40)
                        .frame(width: 500)
                        .background(saveLoadCardBackground)

                        // Load Section
                        VStack(spacing: 30) {
                            Text("Load Game")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(TVColors.cyan)

                            ScrollView {
                                VStack(spacing: 16) {
                                    let slots = gameEngine.getSaveSlots()

                                    if slots.isEmpty {
                                        Text("No saved games")
                                            .font(.system(size: 24, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.5))
                                            .padding(40)
                                    } else {
                                        ForEach(slots) { slot in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text(slot.name)
                                                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                                                        .foregroundColor(.white)

                                                    Text("\(slot.savedDate.formatted()) - \(slot.messageCount) messages")
                                                        .font(.system(size: 20, design: .monospaced))
                                                        .foregroundColor(.white.opacity(0.6))
                                                }

                                                Spacer()

                                                HStack(spacing: 16) {
                                                    Button("Load") {
                                                        gameEngine.loadGame(fromSlot: slot.id)
                                                        isPresented = false
                                                    }
                                                    .buttonStyle(TVLoadButtonStyle())

                                                    Button("Delete") {
                                                        slotToDelete = slot.id
                                                        showDeleteConfirm = true
                                                    }
                                                    .buttonStyle(TVDeleteButtonStyle())
                                                }
                                            }
                                            .padding(20)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.white.opacity(0.05))
                                            )
                                        }
                                    }
                                }
                            }
                            .frame(height: 400)

                            if !gameEngine.getSaveSlots().isEmpty {
                                Button("Delete All Saves") {
                                    slotToDelete = "ALL"
                                    showDeleteConfirm = true
                                }
                                .buttonStyle(TVDestructiveButtonStyle())
                            }
                        }
                        .padding(40)
                        .frame(width: 700)
                        .background(saveLoadCardBackground)
                    }

                    // Done button
                    Button("Done") {
                        isPresented = false
                    }
                    .buttonStyle(TVSecondaryButtonStyle())
                    .padding(.bottom, 40)
                }
            }
            .alert("Delete Save?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if slotToDelete == "ALL" {
                        gameEngine.deleteAllSaves()
                    } else {
                        gameEngine.deleteSaveSlot(slotToDelete)
                    }
                }
            } message: {
                if slotToDelete == "ALL" {
                    Text("This will permanently delete all saved games. This cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this save?")
                }
            }
        }
    }

    private var saveLoadCardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.black.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Button Styles

struct TVLoadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(TVColors.cyan.opacity(0.6))
            )
            .scaleEffect(configuration.isPressed ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TVDeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(0.5))
            )
            .scaleEffect(configuration.isPressed ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

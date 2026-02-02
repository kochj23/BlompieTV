//
//  StatsView.swift
//  BlompieTV
//
//  Game statistics and achievements view for tvOS
//  Created by Jordan Koch on 2/2/2026.
//  Copyright 2026 Jordan Koch. All rights reserved.
//

import SwiftUI

struct StatsView: View {
    @ObservedObject var gameEngine: GameEngine
    @Binding var isPresented: Bool
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            ZStack {
                TVBackground()
                    .ignoresSafeArea()

                VStack(spacing: 40) {
                    // Header
                    Text("Game Statistics")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    // Tab picker
                    Picker("Stats Section", selection: $selectedTab) {
                        Text("Stats").tag(0)
                        Text("Achievements").tag(1)
                        Text("Inventory").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 200)

                    ScrollView {
                        VStack(spacing: 30) {
                            if selectedTab == 0 {
                                statsSection
                            } else if selectedTab == 1 {
                                achievementsSection
                            } else {
                                inventorySection
                            }
                        }
                        .padding(40)
                    }

                    // Done button
                    Button("Done") {
                        isPresented = false
                    }
                    .buttonStyle(TVSecondaryButtonStyle())
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: 30) {
            // Performance Stats
            VStack(alignment: .leading, spacing: 20) {
                Text("Performance")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(TVColors.cyan)

                HStack(spacing: 40) {
                    StatCard(
                        title: "Token Speed",
                        value: gameEngine.lastTokensPerSecond > 0 ? String(format: "%.1f t/s", gameEngine.lastTokensPerSecond) : "N/A",
                        color: TVColors.cyan
                    )

                    StatCard(
                        title: "Model",
                        value: gameEngine.selectedModel,
                        color: TVColors.purple
                    )

                    StatCard(
                        title: "Streaming",
                        value: gameEngine.streamingEnabled ? "On" : "Off",
                        color: TVColors.green
                    )
                }
            }
            .padding(30)
            .background(statsCardBackground)

            // Gameplay Stats
            VStack(alignment: .leading, spacing: 20) {
                Text("Gameplay")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(TVColors.cyan)

                HStack(spacing: 40) {
                    StatCard(
                        title: "Actions",
                        value: "\(gameEngine.actionHistory.count)",
                        color: TVColors.yellow
                    )

                    StatCard(
                        title: "Messages",
                        value: "\(gameEngine.messages.count)",
                        color: TVColors.orange
                    )

                    StatCard(
                        title: "Saves",
                        value: "\(gameEngine.getSaveSlots().count)",
                        color: TVColors.purple
                    )
                }

                HStack(spacing: 40) {
                    StatCard(
                        title: "NPCs Met",
                        value: "\(gameEngine.metNPCs.count)",
                        color: TVColors.green
                    )

                    StatCard(
                        title: "Items",
                        value: "\(gameEngine.inventory.count)",
                        color: TVColors.cyan
                    )

                    StatCard(
                        title: "Locations",
                        value: "\(gameEngine.locationHistory.count)",
                        color: TVColors.yellow
                    )
                }
            }
            .padding(30)
            .background(statsCardBackground)

            // Settings Summary
            VStack(alignment: .leading, spacing: 20) {
                Text("Current Settings")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(TVColors.cyan)

                HStack(spacing: 40) {
                    StatCard(
                        title: "Detail",
                        value: gameEngine.detailLevel.rawValue,
                        color: TVColors.purple
                    )

                    StatCard(
                        title: "Tone",
                        value: gameEngine.toneStyle.rawValue,
                        color: TVColors.orange
                    )

                    StatCard(
                        title: "Creativity",
                        value: String(format: "%.1f", gameEngine.temperature),
                        color: TVColors.green
                    )
                }
            }
            .padding(30)
            .background(statsCardBackground)
        }
    }

    // MARK: - Achievements Section

    private var achievementsSection: some View {
        VStack(spacing: 30) {
            // Progress
            VStack(spacing: 20) {
                let unlockedCount = gameEngine.achievements.filter { $0.isUnlocked }.count
                let totalCount = gameEngine.achievements.count
                let progress = totalCount > 0 ? Double(unlockedCount) / Double(totalCount) : 0

                Text("\(unlockedCount) / \(totalCount) Achievements Unlocked")
                    .font(.system(size: 28, design: .monospaced))
                    .foregroundColor(.white)

                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: TVColors.yellow))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                    .padding(.horizontal, 100)

                Text("\(Int(progress * 100))% Complete")
                    .font(.system(size: 24, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(30)
            .background(statsCardBackground)

            // Achievement List
            ForEach(gameEngine.achievements) { achievement in
                HStack(spacing: 24) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(achievement.isUnlocked ? TVColors.yellow : Color.gray.opacity(0.3))
                            .frame(width: 60, height: 60)

                        Text(achievement.isUnlocked ? "star.fill" : "lock.fill")
                            .font(.system(size: 28))

                        Image(systemName: achievement.isUnlocked ? "star.fill" : "lock.fill")
                            .font(.system(size: 28))
                            .foregroundColor(achievement.isUnlocked ? .white : .gray)
                    }

                    // Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text(achievement.title)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)

                        Text(achievement.description)
                            .font(.system(size: 22, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))

                        if let date = achievement.unlockDate {
                            Text("Unlocked: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 18, design: .monospaced))
                                .foregroundColor(TVColors.yellow.opacity(0.8))
                        }
                    }

                    Spacer()

                    // Status
                    if achievement.isUnlocked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(TVColors.green)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(achievement.isUnlocked ? TVColors.yellow.opacity(0.15) : Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(achievement.isUnlocked ? TVColors.yellow.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Inventory Section

    private var inventorySection: some View {
        VStack(spacing: 30) {
            // Inventory
            VStack(alignment: .leading, spacing: 20) {
                Text("Inventory (\(gameEngine.inventory.count) items)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(TVColors.cyan)

                if gameEngine.inventory.isEmpty {
                    Text("No items collected yet")
                        .font(.system(size: 24, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                        ForEach(gameEngine.inventory, id: \.self) { item in
                            HStack {
                                Image(systemName: "cube.fill")
                                    .foregroundColor(TVColors.cyan)
                                Text(item)
                                    .font(.system(size: 22, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(TVColors.cyan.opacity(0.15))
                            )
                        }
                    }
                }
            }
            .padding(30)
            .background(statsCardBackground)

            // NPCs Met
            VStack(alignment: .leading, spacing: 20) {
                Text("Characters Met (\(gameEngine.metNPCs.count))")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(TVColors.purple)

                if gameEngine.metNPCs.isEmpty {
                    Text("No characters met yet")
                        .font(.system(size: 24, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                        ForEach(gameEngine.metNPCs, id: \.self) { npc in
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(TVColors.purple)
                                Text(npc)
                                    .font(.system(size: 22, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(TVColors.purple.opacity(0.15))
                            )
                        }
                    }
                }
            }
            .padding(30)
            .background(statsCardBackground)

            // Locations Visited
            VStack(alignment: .leading, spacing: 20) {
                Text("Locations Visited (\(gameEngine.locationHistory.count))")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(TVColors.green)

                if gameEngine.locationHistory.isEmpty {
                    Text("No locations visited yet")
                        .font(.system(size: 24, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 16) {
                        ForEach(gameEngine.locationHistory, id: \.self) { location in
                            HStack {
                                Image(systemName: "map.fill")
                                    .foregroundColor(TVColors.green)
                                Text(location)
                                    .font(.system(size: 22, design: .monospaced))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(TVColors.green.opacity(0.15))
                            )
                        }
                    }
                }
            }
            .padding(30)
            .background(statsCardBackground)
        }
    }

    private var statsCardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.black.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundColor(color)

            Text(title)
                .font(.system(size: 20, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(minWidth: 150)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.15))
        )
    }
}

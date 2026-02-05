//
//  TopShelfDataManager.swift
//  BlompieTV
//
//  Created by Jordan Koch
//  Manages data sharing between the main app and Top Shelf extension
//

import Foundation
import TVServices

/// Manages data synchronization between the main app and the Top Shelf extension
final class TopShelfDataManager {

    // MARK: - Singleton
    static let shared = TopShelfDataManager()

    // MARK: - Constants
    private let appGroupIdentifier = "group.com.jordankoch.blompietv"

    private enum Keys {
        static let hasSaveData = "hasSaveData"
        static let currentLocation = "currentLocation"
        static let npcsEncountered = "npcsEncountered"
        static let itemsFound = "itemsFound"
        static let locationsVisited = "locationsVisited"
        static let saveSlotPrefix = "saveSlot"
    }

    // MARK: - Properties
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private init() {}

    // MARK: - Public Methods

    /// Updates the Top Shelf with current game state
    func updateGameState(hasSave: Bool, currentLocation: String) {
        sharedDefaults?.set(hasSave, forKey: Keys.hasSaveData)
        sharedDefaults?.set(currentLocation, forKey: Keys.currentLocation)
        notifyTopShelfUpdate()
    }

    /// Updates game statistics for Top Shelf display
    func updateStats(npcs: Int, items: Int, locations: Int) {
        sharedDefaults?.set(npcs, forKey: Keys.npcsEncountered)
        sharedDefaults?.set(items, forKey: Keys.itemsFound)
        sharedDefaults?.set(locations, forKey: Keys.locationsVisited)
        notifyTopShelfUpdate()
    }

    /// Updates a save slot name for Top Shelf display
    /// - Parameters:
    ///   - slot: Slot index (0-2)
    ///   - name: Name to display for this save slot
    func updateSaveSlot(_ slot: Int, name: String) {
        guard slot >= 0 && slot < 3 else { return }
        sharedDefaults?.set(name, forKey: "\(Keys.saveSlotPrefix)\(slot)Name")
        notifyTopShelfUpdate()
    }

    /// Notifies the system that Top Shelf content has changed
    func notifyTopShelfUpdate() {
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    /// Clears all Top Shelf data (for new game)
    func clearTopShelfData() {
        sharedDefaults?.set(false, forKey: Keys.hasSaveData)
        sharedDefaults?.removeObject(forKey: Keys.currentLocation)
        sharedDefaults?.set(0, forKey: Keys.npcsEncountered)
        sharedDefaults?.set(0, forKey: Keys.itemsFound)
        sharedDefaults?.set(0, forKey: Keys.locationsVisited)
        for i in 0..<3 {
            sharedDefaults?.removeObject(forKey: "\(Keys.saveSlotPrefix)\(i)Name")
        }
        notifyTopShelfUpdate()
    }

    // MARK: - Convenience Methods

    /// Call when player enters a new location
    func onLocationEntered(_ locationName: String, totalVisited: Int) {
        sharedDefaults?.set(locationName, forKey: Keys.currentLocation)
        sharedDefaults?.set(totalVisited, forKey: Keys.locationsVisited)
        notifyTopShelfUpdate()
    }

    /// Call when player encounters a new NPC
    func onNPCEncountered(totalNPCs: Int) {
        sharedDefaults?.set(totalNPCs, forKey: Keys.npcsEncountered)
        notifyTopShelfUpdate()
    }

    /// Call when player finds a new item
    func onItemFound(totalItems: Int) {
        sharedDefaults?.set(totalItems, forKey: Keys.itemsFound)
        notifyTopShelfUpdate()
    }

    /// Call when game is saved
    func onGameSaved(slot: Int, saveName: String, location: String) {
        sharedDefaults?.set(true, forKey: Keys.hasSaveData)
        sharedDefaults?.set(location, forKey: Keys.currentLocation)
        updateSaveSlot(slot, name: saveName)
    }
}

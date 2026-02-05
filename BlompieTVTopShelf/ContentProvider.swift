//
//  ContentProvider.swift
//  BlompieTVTopShelf
//
//  Created by Jordan Koch
//

import TVServices

class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        // Load game stats and save slots
        let gameData = loadGameData()

        var items: [TVTopShelfSectionedItem] = []

        // New Game item
        let newGameItem = TVTopShelfSectionedItem(identifier: "new_game")
        newGameItem.title = "New Adventure"
        if let url = URL(string: "blompietv://new") {
            newGameItem.displayAction = TVTopShelfAction(url: url)
            newGameItem.playAction = TVTopShelfAction(url: url)
        }
        items.append(newGameItem)

        // Continue Game item (if save exists)
        if gameData.hasSaveData {
            let continueItem = TVTopShelfSectionedItem(identifier: "continue")
            continueItem.title = "Continue: \(gameData.currentLocation)"
            if let url = URL(string: "blompietv://continue") {
                continueItem.displayAction = TVTopShelfAction(url: url)
                continueItem.playAction = TVTopShelfAction(url: url)
            }
            items.append(continueItem)
        }

        // Save slots
        for (index, slot) in gameData.saveSlots.prefix(3).enumerated() {
            let slotItem = TVTopShelfSectionedItem(identifier: "slot_\(index)")
            slotItem.title = slot.name.isEmpty ? "Empty Slot \(index + 1)" : slot.name
            if let url = URL(string: "blompietv://load/\(index)") {
                slotItem.displayAction = TVTopShelfAction(url: url)
                slotItem.playAction = TVTopShelfAction(url: url)
            }
            items.append(slotItem)
        }

        // Create sections
        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []

        // Main actions section
        let mainSection = TVTopShelfItemCollection(items: Array(items.prefix(2)))
        mainSection.title = "Blompie Adventure"
        sections.append(mainSection)

        // Save slots section
        if items.count > 2 {
            let savesSection = TVTopShelfItemCollection(items: Array(items.suffix(from: 2)))
            savesSection.title = "Saved Games"
            sections.append(savesSection)
        }

        // Stats section
        if gameData.hasStats {
            let statsItem = TVTopShelfSectionedItem(identifier: "stats")
            statsItem.title = "NPCs: \(gameData.npcsEncountered) | Items: \(gameData.itemsFound) | Places: \(gameData.locationsVisited)"

            let statsSection = TVTopShelfItemCollection(items: [statsItem])
            statsSection.title = "Your Journey"
            sections.append(statsSection)
        }

        let content = TVTopShelfSectionedContent(sections: sections)
        completionHandler(content)
    }

    private func loadGameData() -> GameData {
        let userDefaults = UserDefaults(suiteName: "group.com.jordankoch.blompietv")

        let hasSaveData = userDefaults?.bool(forKey: "hasSaveData") ?? false
        let currentLocation = userDefaults?.string(forKey: "currentLocation") ?? "Unknown"
        let npcsEncountered = userDefaults?.integer(forKey: "npcsEncountered") ?? 0
        let itemsFound = userDefaults?.integer(forKey: "itemsFound") ?? 0
        let locationsVisited = userDefaults?.integer(forKey: "locationsVisited") ?? 0

        var saveSlots: [SaveSlot] = []
        for i in 0..<3 {
            let name = userDefaults?.string(forKey: "saveSlot\(i)Name") ?? ""
            saveSlots.append(SaveSlot(name: name))
        }

        return GameData(
            hasSaveData: hasSaveData,
            currentLocation: currentLocation,
            npcsEncountered: npcsEncountered,
            itemsFound: itemsFound,
            locationsVisited: locationsVisited,
            saveSlots: saveSlots
        )
    }
}

// MARK: - Game Data Model
struct GameData {
    let hasSaveData: Bool
    let currentLocation: String
    let npcsEncountered: Int
    let itemsFound: Int
    let locationsVisited: Int
    let saveSlots: [SaveSlot]

    var hasStats: Bool {
        npcsEncountered > 0 || itemsFound > 0 || locationsVisited > 0
    }
}

struct SaveSlot {
    let name: String
}

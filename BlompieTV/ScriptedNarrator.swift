//
//  ScriptedNarrator.swift
//  BlompieTV
//
//  The game-level AI contract that sits on top of LLMBalancerManager:
//   • ScriptedNarrator: a small hand-written world that narrates every turn when
//     AI is switched off or no backend answers, so the game is always playable.
//   • NarrationValidator: cleans and sanity-checks model output before it can
//     touch game state (reasoning tags, control characters, prompt echoes,
//     empty/garbage replies, overlong text and actions).
//   • NarrationSource: the label shown for each turn (AI vs scripted).
//
//  Pattern follows CarTest NovaAI / StuntDriver AIFeatures: the deterministic
//  answer always exists, the AI answer replaces it only if it passes the checks.
//  Fallback lines are shared with the web Blompie narrator (NovaGames).
//
//  Created by Jordan Koch on 2026-11-11.
//  Copyright 2026 Jordan Koch. All rights reserved.
//

import Foundation

// MARK: - Turn source

/// Where the narration of a turn came from.
enum NarrationSource: Equatable {
    case none
    /// A model answered; `backend` is the display name of the backend used.
    case ai(backend: String)
    /// The scripted narrator answered because AI is switched off.
    case scriptedAIOff
    /// The scripted narrator answered because no backend answered or the reply failed validation.
    case scriptedFallback

    var label: String {
        switch self {
        case .none: return ""
        case .ai(let backend): return "AI narrator (\(backend))"
        case .scriptedAIOff: return "Scripted narrator (AI off)"
        case .scriptedFallback: return "Scripted narrator (AI unavailable)"
        }
    }

    var isAI: Bool { if case .ai = self { return true } else { return false } }
}

// MARK: - Scripted narrator

/// Deterministic offline narrator: a little loop of places with fixed exits.
/// Actions it doesn't know (e.g. ones an AI turn offered before the AI went away)
/// get a fallback line and the current place's actions, so play never stalls.
enum ScriptedNarrator {

    struct Turn: Equatable {
        let text: String
        let actions: [String]
        let sceneID: String
    }

    struct Scene {
        let id: String
        let text: String
        /// Ordered (action, destination scene id).
        let exits: [(String, String)]
        var actions: [String] { exits.map { $0.0 } }
    }

    static let startSceneID = "meadow"

    static let fallbackLines = [
        "A thick, slightly sarcastic fog rolls in. For a moment you can't see your own boots, but you can hear them, and they sound unimpressed.",
        "Somewhere nearby a kettle whistles, though there is no kettle and nobody is making tea. The world seems to be thinking very hard about what happens next.",
        "A small sign appears at your feet. It reads: 'Narrator on a short break. Please continue adventuring responsibly.' It disappears with a polite pop.",
        "The wind changes direction twice, apologises, and settles down. The path ahead looks exactly as mysterious as before.",
        "A passing snail gives you a long look, as if it knows something. It does not share."
    ]

    static let scenes: [String: Scene] = {
        let list = [
            Scene(id: "meadow",
                  text: "You find yourself in a meadow that smells faintly of cinnamon and old maps. A crooked signpost points in three directions at once. Somewhere, a bell rings without a bell. This is Blompie.",
                  exits: [("Read the signpost", "crossroads"), ("Follow the bell", "belltower"), ("Walk toward the smell of cinnamon", "market"), ("Look around", "meadow")]),
            Scene(id: "crossroads",
                  text: "You arrive at a crossroads where the signpost has given up and is napping. A traveler named Pim leans on a walking stick and greets you with a cheerful wave. 'Lost? Good. Lost is where the interesting bits are.'",
                  exits: [("Ask Pim for directions", "library"), ("Take the river path", "river"), ("Go back to the meadow", "meadow"), ("Look around", "crossroads")]),
            Scene(id: "belltower",
                  text: "You enter a bell tower with no bell. The keeper, an elder named Ostra, polishes the empty air where it should hang. 'It left to see the sea,' she says. 'It writes.' She hands you a postcard; you pick up the postcard.",
                  exits: [("Read the postcard", "river"), ("Climb to the top", "observatory"), ("Go back to the meadow", "meadow"), ("Look around", "belltower")]),
            Scene(id: "market",
                  text: "You arrive at a tiny market of three stalls and one very confident merchant named Bram. He sells cinnamon, compasses that point at whatever you want most, and slightly used wishes. You receive a free sample of cinnamon.",
                  exits: [("Trade the postcard for a compass", "library"), ("Buy a slightly used wish", "grove"), ("Go back to the meadow", "meadow"), ("Look around", "market")]),
            Scene(id: "library",
                  text: "You enter a library where the books are all maps and the maps are all of places that change when you look away. A guide named Quill, made mostly of folded paper, offers to lend you one. You acquire a folding map.",
                  exits: [("Borrow the folding map", "river"), ("Ask Quill about the bell", "belltower"), ("Go back to the crossroads", "crossroads"), ("Look around", "library")]),
            Scene(id: "river",
                  text: "You arrive at a slow, polite river. A ferryman named Lune waits in a boat shaped like a teacup. 'Fare is one good story,' he says. You tell him about the napping signpost. He laughs so hard the teacup spins.",
                  exits: [("Ride the teacup ferry", "grove"), ("Follow the river upstream", "observatory"), ("Go back to the crossroads", "crossroads"), ("Look around", "river")]),
            Scene(id: "grove",
                  text: "You enter a grove where a sprite named Fizzle is rearranging the shadows for fun. She grins and swaps yours with a tree's. It suits you. 'Keep it,' she says, 'it's a loan.' You grab a pinecone that hums.",
                  exits: [("Play Fizzle's shadow game", "observatory"), ("Ask about the humming pinecone", "library"), ("Head back to the meadow", "meadow"), ("Look around", "grove")]),
            Scene(id: "observatory",
                  text: "You arrive at an observatory on a hill. Inside, a wizard named Marrow studies a star map and the missing bell, which is sitting happily on the telescope. 'It wanted a better view,' Marrow explains. The bell rings once, pleased to see you.",
                  exits: [("Thank Marrow and the bell", "meadow"), ("Look through the telescope", "grove"), ("Walk down to the river", "river"), ("Look around", "observatory")])
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()

    static func scene(_ id: String?) -> Scene {
        scenes[id ?? startSceneID] ?? scenes[startSceneID]!
    }

    /// The opening scene of a new game.
    static func opening() -> Turn {
        let s = scene(startSceneID)
        return Turn(text: s.text, actions: s.actions, sceneID: s.id)
    }

    /// Narrate `action` taken in `sceneID`. Deterministic.
    static func respond(to action: String, in sceneID: String?) -> Turn {
        let current = scene(sceneID)
        let wanted = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exit = current.exits.first(where: { $0.0.lowercased() == wanted }) {
            let next = scene(exit.1)
            return Turn(text: next.text, actions: next.actions, sceneID: next.id)
        }
        // Unknown action: a fallback line, then the place's own options.
        let index = wanted.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % fallbackLines.count
        return Turn(text: fallbackLines[abs(index)], actions: current.actions, sceneID: current.id)
    }
}

// MARK: - Output validation

/// Sanity checks for model output before it touches game state.
enum NarrationValidator {
    static let maxNarrationCharacters = 6000
    static let maxActions = 6
    static let maxActionCharacters = 80
    static let defaultActions = ["Look around", "Continue", "Go back", "Examine surroundings"]

    /// Phrases from the system prompt; a reply that repeats several is a prompt echo.
    static let promptEchoMarkers = [
        "You are the game master", "Your role is to:", "CRITICAL FORMAT REQUIREMENT",
        "CRITICAL - ACTIONS MUST", "PROGRESS IS MANDATORY", "BAD (stuck):", "GOOD (progress):",
        "FORMAT 1 (PREFERRED)", "Populate the world with NPCs"
    ]

    /// Clean a raw reply. Returns nil when it is empty, garbage or a prompt echo.
    static func sanitize(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
        if let r = text.range(of: "</think>") { text = String(text[r.upperBound...]) }
        let scalars = text.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t"
        }
        text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Needs to read as words: enough letters among the visible characters.
        let visible = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        let letters = visible.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 3, Double(letters.count) / Double(max(visible.count, 1)) >= 0.4 else { return nil }

        let echoes = promptEchoMarkers.filter { text.contains($0) }.count
        guard echoes < 2 else { return nil }

        if text.count > maxNarrationCharacters { text = String(text.prefix(maxNarrationCharacters)) }
        return text
    }

    /// Clamp the action list: plain short text, no duplicates, at most `maxActions`.
    static func sanitizeActions(_ actions: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for action in actions {
            let scalars = action.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            var a = String(String.UnicodeScalarView(scalars))
                .replacingOccurrences(of: "[*#_`>\\[\\]]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !a.isEmpty else { continue }
            if a.count > maxActionCharacters { a = String(a.prefix(maxActionCharacters)).trimmingCharacters(in: .whitespaces) }
            guard seen.insert(a.lowercased()).inserted else { continue }
            out.append(a)
            if out.count == maxActions { break }
        }
        return out
    }
}

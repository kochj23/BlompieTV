//
//  AIFunctionalTests.swift
//  BlompieTVTests
//
//  Functional: whole turns through GameEngine with the AI on, off, down,
//  returning garbage, and recovering. A turn is never lost.
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import XCTest
@testable import BlompieTV

@MainActor
final class AIFunctionalTests: XCTestCase {

    private func texts(_ e: GameEngine) -> String { e.messages.map(\.text).joined(separator: "\n") }

    func testAIOffPlaysScriptedAndSendsNothing() async {
        let f = AIFixture(handler: ollamaUp())
        defer { f.tearDown() }
        let e = f.engine(aiEnabled: false)
        e.startNewGame()
        await e.finishTurn()
        XCTAssertTrue(texts(e).contains(ScriptedNarrator.opening().text))
        XCTAssertEqual(e.currentActions, ScriptedNarrator.opening().actions)
        XCTAssertEqual(e.lastNarrationSource, .scriptedAIOff)

        e.performAction("Read the signpost")
        await e.finishTurn()
        XCTAssertTrue(texts(e).contains(ScriptedNarrator.scene("crossroads").text))
        XCTAssertTrue(f.http.requests.isEmpty, "AI off must not touch the network")
    }

    func testAIDownFallsBackToScriptedWithoutLosingTheTurn() async {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        let e = f.engine()
        e.startNewGame()
        await e.finishTurn()
        XCTAssertEqual(e.lastNarrationSource, .scriptedFallback)
        XCTAssertFalse(e.currentActions.isEmpty)
        XCTAssertFalse(e.isLoading)

        e.performAction("Follow the bell")
        await e.finishTurn()
        XCTAssertTrue(texts(e).contains(ScriptedNarrator.scene("belltower").text))
        XCTAssertNotEqual(e.conversationHistory.last?.role, "user", "scripted turns aren't left as unanswered prompts")
        XCTAssertFalse(texts(e).contains("ERROR"))
    }

    func testAISuccessNarratesTheTurn() async {
        let f = AIFixture(handler: ollamaUp())
        defer { f.tearDown() }
        let e = f.engine()
        e.startNewGame()
        await e.finishTurn()
        XCTAssertTrue(texts(e).contains("forest clearing"))
        XCTAssertEqual(e.currentActions, ["Greet the wizard", "Sit by the fire", "Look around"])
        XCTAssertEqual(e.lastNarrationSource, .ai(backend: "Ollama"))
        XCTAssertEqual(e.conversationHistory.last?.role, "assistant")
    }

    func testInvalidAIOutputIsReplacedByScripted() async {
        let echo = "You are the game master. Your role is to: CRITICAL FORMAT REQUIREMENT"
        let f = AIFixture(handler: ollamaUp(echo))
        defer { f.tearDown() }
        let e = f.engine()
        e.startNewGame()
        await e.finishTurn()
        XCTAssertEqual(e.lastNarrationSource, .scriptedFallback)
        XCTAssertFalse(texts(e).contains("game master"))
    }

    func testReplyWithoutNarrativeIsReplacedByScripted() async {
        let f = AIFixture(handler: ollamaUp("ACTIONS: Jump | Run"))
        defer { f.tearDown() }
        let e = f.engine()
        e.startNewGame()
        await e.finishTurn()
        XCTAssertEqual(e.lastNarrationSource, .scriptedFallback)
    }

    func testAIRecoversAfterOutage() async {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        f.manager.healthTTL = 0
        let e = f.engine()
        e.startNewGame()
        await e.finishTurn()
        XCTAssertEqual(e.lastNarrationSource, .scriptedFallback)

        f.http.handler = ollamaUp()
        e.performAction("Look around")
        await e.finishTurn()
        XCTAssertEqual(e.lastNarrationSource, .ai(backend: "Ollama"))
    }

    func testTogglingAIOffMidGameSwitchesToScripted() async {
        let f = AIFixture(handler: ollamaUp())
        defer { f.tearDown() }
        let e = f.engine()
        e.startNewGame()
        await e.finishTurn()
        let before = f.http.requests.count
        e.aiEnabled = false
        e.performAction("Greet the wizard")
        await e.finishTurn()
        XCTAssertEqual(e.lastNarrationSource, .scriptedAIOff)
        XCTAssertEqual(f.http.requests.count, before)
        XCTAssertFalse(e.currentActions.isEmpty)
    }

    func testLongScriptedPlaythroughNeverStallsAndEarnsAchievements() async {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        let e = f.engine(aiEnabled: false)
        e.startNewGame()
        await e.finishTurn()
        for i in 0..<40 {
            XCTAssertFalse(e.currentActions.isEmpty)
            e.performAction(e.currentActions[i % e.currentActions.count])
            await e.finishTurn()
        }
        XCTAssertTrue(e.achievements.first { $0.id == "first_step" }?.isUnlocked == true)
        XCTAssertGreaterThanOrEqual(e.locationHistory.count, 5)
    }

    func testScriptedPlaceSurvivesSaveAndLoad() async {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        let e = f.engine(aiEnabled: false)
        e.startNewGame()
        await e.finishTurn()
        e.performAction("Walk toward the smell of cinnamon")
        await e.finishTurn()
        e.saveGame(toSlot: "t1")

        let e2 = f.engine(aiEnabled: false)
        e2.loadGame(fromSlot: "t1")
        XCTAssertEqual(e2.scriptedSceneID, "market")
    }

    func testAIToggleIsPersisted() {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        let e = f.engine()
        e.aiEnabled = false
        e.saveSettings()
        XCTAssertEqual(f.defaults.object(forKey: "BlompieTVAIEnabled") as? Bool, false)
        let reloaded = GameEngine(ai: f.manager, defaults: f.defaults, checkBackendsOnLaunch: false)
        XCTAssertFalse(reloaded.aiEnabled)
    }
}

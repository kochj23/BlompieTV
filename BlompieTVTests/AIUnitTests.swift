//
//  AIUnitTests.swift
//  BlompieTVTests
//
//  Unit: the pure pieces of the AI layer (backend ids and order, endpoint and
//  model settings, reply parsing, output validation, the scripted narrator).
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import XCTest
@testable import BlompieTV

final class AIUnitTests: XCTestCase {

    // MARK: Backend ids and auto order

    func testAutoOrderIsTheCanonicalFixedOrder() {
        XCTAssertEqual(LLMBackendType.autoOrder,
                       [.ollama, .mlx, .tinyChat, .tinyLLM, .openWebUI, .novaGateway, .openRouter, .openAI])
        XCTAssertFalse(LLMBackendType.autoOrder.contains(.auto))
        XCTAssertEqual(FailoverPlanner.defaultChain, LLMBackendType.autoOrder)
    }

    func testPickerHidesMLXOnTVOS() {
        XCTAssertFalse(LLMBackendType.pickerCases.contains(.mlx))
        XCTAssertEqual(LLMBackendType.pickerCases.first, .auto)
        XCTAssertEqual(LLMBackendType.pickerCases.count, LLMBackendType.allCases.count - 1)
    }

    func testOnlyCloudBackendsNeedKeys() {
        XCTAssertEqual(LLMBackendType.allCases.filter(\.requiresAPIKey), [.openRouter, .openAI])
    }

    func testCloudDefaultsAreHTTPS() {
        XCTAssertTrue(LLMBackendType.openRouter.defaultURL.hasPrefix("https://"))
        XCTAssertTrue(LLMBackendType.openAI.defaultURL.hasPrefix("https://"))
    }

    func testEveryBackendHasADefaultModelExceptAutoAndMLX() {
        for b in LLMBackendType.allCases where b != .auto && b != .mlx {
            XCTAssertFalse(b.defaultModel.isEmpty, b.rawValue)
        }
    }

    // MARK: Endpoint validation

    func testEndpointValidation() {
        XCTAssertTrue(LLMBalancerManager.isValidEndpoint("http://192.168.1.5:11434", requireHTTPS: false))
        XCTAssertTrue(LLMBalancerManager.isValidEndpoint("https://api.openai.com/v1", requireHTTPS: true))
        XCTAssertFalse(LLMBalancerManager.isValidEndpoint("http://api.openai.com/v1", requireHTTPS: true))
        XCTAssertFalse(LLMBalancerManager.isValidEndpoint("", requireHTTPS: false))
        XCTAssertFalse(LLMBalancerManager.isValidEndpoint("192.168.1.5:11434", requireHTTPS: false))
        XCTAssertFalse(LLMBalancerManager.isValidEndpoint("ftp://host", requireHTTPS: false))
        XCTAssertFalse(LLMBalancerManager.isValidEndpoint("file:///etc/passwd", requireHTTPS: false))
    }

    // MARK: Reply extraction

    func testExtractContentFormats() {
        XCTAssertEqual(LLMBalancerManager.extractContent(Reply.openAI(" Hi ")), "Hi")
        XCTAssertEqual(LLMBalancerManager.extractContent(Reply.ollama("Hello")), "Hello")
        XCTAssertNil(LLMBalancerManager.extractContent(Data("plain words".utf8)))
        XCTAssertEqual(LLMBalancerManager.extractContent(Data("plain words".utf8), allowPlainText: true), "plain words")
        XCTAssertNil(LLMBalancerManager.extractContent(Reply.openAI("   ")))
        XCTAssertNil(LLMBalancerManager.extractContent(Data()))
    }

    func testParseModelIDs() {
        XCTAssertEqual(LLMBalancerManager.parseModelIDs(Reply.modelList(["a", "b"])), ["a", "b"])
        XCTAssertEqual(LLMBalancerManager.parseModelIDs(Reply.tags(["mistral"])), ["mistral"])
        XCTAssertEqual(LLMBalancerManager.parseModelIDs(Data(#"{"models":[{"id":"w1"}]}"#.utf8)), ["w1"])
        XCTAssertTrue(LLMBalancerManager.parseModelIDs(Data("junk".utf8)).isEmpty)
    }

    // MARK: Response parsing

    func testParsePipeActions() {
        let r = GameEngine.parseResponse("You enter a cave.\nACTIONS: Light torch | Go deeper | Leave")
        XCTAssertEqual(r.narrative, "You enter a cave.")
        XCTAssertEqual(r.actions, ["Light torch", "Go deeper", "Leave"])
    }

    func testParseNumberedActions() {
        let r = GameEngine.parseResponse("A merchant waves.\nWhat do you do?\n1. Talk to merchant\n2. Walk away")
        XCTAssertEqual(r.narrative, "A merchant waves.")
        XCTAssertEqual(r.actions, ["Talk to merchant", "Walk away"])
    }

    func testParseBoldActions() {
        let r = GameEngine.parseResponse("Fog.\n1. **Wave** (be friendly)\n2. **Hide**")
        XCTAssertEqual(r.actions, ["Wave", "Hide"])
    }

    // MARK: Output validation

    func testSanitizeStripsReasoningAndControlCharacters() {
        let raw = "<think>secret plan</think>\u{0007}You arrive at the gate.\u{0000}"
        XCTAssertEqual(NarrationValidator.sanitize(raw), "You arrive at the gate.")
        XCTAssertEqual(NarrationValidator.sanitize("reasoning...</think>The door opens."), "The door opens.")
    }

    func testSanitizeRejectsEmptyAndGarbage() {
        XCTAssertNil(NarrationValidator.sanitize(""))
        XCTAssertNil(NarrationValidator.sanitize("   \n "))
        XCTAssertNil(NarrationValidator.sanitize("{}[]{}[]{}[]{}[]{}"))
        XCTAssertNil(NarrationValidator.sanitize("0101 0101 0101 0101 9999"))
        XCTAssertNil(NarrationValidator.sanitize("<think>only thinking</think>"))
    }

    func testSanitizeRejectsPromptEcho() {
        let echo = "You are the game master for a text-based adventure. CRITICAL FORMAT REQUIREMENT - THIS IS MANDATORY"
        XCTAssertNil(NarrationValidator.sanitize(echo))
        // One stray phrase inside a real story is fine.
        XCTAssertNotNil(NarrationValidator.sanitize("The sign says: PROGRESS IS MANDATORY. You laugh and walk on."))
    }

    func testSanitizeCapsLength() {
        let long = String(repeating: "word ", count: 5000)
        XCTAssertEqual(NarrationValidator.sanitize(long)?.count, NarrationValidator.maxNarrationCharacters)
    }

    func testSanitizeActionsClamps() {
        let raw = ["**Open door**", "open door", "", "  ", "# Go north", String(repeating: "x", count: 300),
                   "a", "b", "c", "d", "e", "f"]
        let clean = NarrationValidator.sanitizeActions(raw)
        XCTAssertEqual(clean.count, NarrationValidator.maxActions)
        XCTAssertEqual(clean[0], "Open door")
        XCTAssertEqual(clean[1], "Go north")
        XCTAssertEqual(clean[2].count, NarrationValidator.maxActionCharacters)
        XCTAssertEqual(Set(clean.map { $0.lowercased() }).count, clean.count, "no duplicates")
    }

    // MARK: Scripted narrator

    func testOpeningIsTheMeadow() {
        let t = ScriptedNarrator.opening()
        XCTAssertEqual(t.sceneID, ScriptedNarrator.startSceneID)
        XCTAssertFalse(t.text.isEmpty)
        XCTAssertGreaterThanOrEqual(t.actions.count, 3)
    }

    func testKnownActionMovesToItsScene() {
        let t = ScriptedNarrator.respond(to: "read the signpost", in: "meadow")
        XCTAssertEqual(t.sceneID, "crossroads")
        XCTAssertTrue(t.text.contains("crossroads"))
    }

    func testUnknownActionKeepsPlaceAndOffersItsActions() {
        let t = ScriptedNarrator.respond(to: "Dance with the moon", in: "market")
        XCTAssertEqual(t.sceneID, "market")
        XCTAssertTrue(ScriptedNarrator.fallbackLines.contains(t.text))
        XCTAssertEqual(t.actions, ScriptedNarrator.scene("market").actions)
    }

    func testScriptedNarratorIsDeterministic() {
        XCTAssertEqual(ScriptedNarrator.respond(to: "Sing", in: "river"), ScriptedNarrator.respond(to: "Sing", in: "river"))
    }

    func testUnknownSceneFallsBackToStart() {
        XCTAssertEqual(ScriptedNarrator.scene("nowhere").id, ScriptedNarrator.startSceneID)
        XCTAssertEqual(ScriptedNarrator.scene(nil).id, ScriptedNarrator.startSceneID)
    }

    func testEveryExitLeadsSomewhereAndEverySceneIsReachable() {
        var seen: Set<String> = [ScriptedNarrator.startSceneID]
        var queue = [ScriptedNarrator.startSceneID]
        while let id = queue.popLast() {
            for (_, to) in ScriptedNarrator.scene(id).exits {
                XCTAssertNotNil(ScriptedNarrator.scenes[to], "\(id) -> \(to)")
                if seen.insert(to).inserted { queue.append(to) }
            }
        }
        XCTAssertEqual(seen, Set(ScriptedNarrator.scenes.keys))
    }

    func testNarrationSourceLabels() {
        XCTAssertEqual(NarrationSource.ai(backend: "Ollama").label, "AI narrator (Ollama)")
        XCTAssertTrue(NarrationSource.ai(backend: "x").isAI)
        XCTAssertFalse(NarrationSource.scriptedFallback.isAI)
        XCTAssertTrue(NarrationSource.scriptedAIOff.label.contains("AI off"))
        XCTAssertEqual(NarrationSource.none.label, "")
    }

    // MARK: Manager settings

    @MainActor
    func testURLForBackendTrimsAndPersists() {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        f.manager.setURL(" http://10.0.0.9:11434/ ", for: .ollama)
        XCTAssertEqual(f.manager.url(for: .ollama), "http://10.0.0.9:11434")
        f.manager.selectedBackend = .tinyChat
        f.manager.setModel("qwen3:8b", for: .ollama)

        let again = LLMBalancerManager(settingsKey: "AITestSettings", defaults: f.defaults,
                                       keychainServicePrefix: f.keychainPrefix, legacyOpenRouterService: nil,
                                       transport: f.http.transport)
        XCTAssertEqual(again.url(for: .ollama), "http://10.0.0.9:11434")
        XCTAssertEqual(again.selectedBackend, .tinyChat)
        XCTAssertEqual(again.model(for: .ollama), "qwen3:8b")
    }

    @MainActor
    func testModelDefaultsAndPickerBackend() {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        XCTAssertEqual(f.manager.model(for: .ollama), "mistral")
        f.manager.setModel("  ", for: .ollama)
        XCTAssertEqual(f.manager.model(for: .ollama), "mistral", "blank falls back to default")
        XCTAssertEqual(f.manager.modelPickerBackend, .ollama, "auto with nothing active edits Ollama")
        f.manager.selectedBackend = .openRouter
        XCTAssertEqual(f.manager.modelPickerBackend, .openRouter)
        XCTAssertEqual(f.manager.currentModel, OpenRouterProvider.defaultModel)
    }

    @MainActor
    func testCandidateChain() {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        XCTAssertEqual(f.manager.candidateChain, LLMBackendType.autoOrder.filter { $0 != .mlx })
        f.manager.selectedBackend = .openWebUI
        XCTAssertEqual(f.manager.candidateChain, [.openWebUI])
    }

    @MainActor
    func testIsConfigured() {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        XCTAssertTrue(f.manager.isConfigured(.ollama))
        XCTAssertFalse(f.manager.isConfigured(.auto))
        XCTAssertFalse(f.manager.isConfigured(.mlx))
        XCTAssertFalse(f.manager.isConfigured(.openRouter), "no key")
        f.manager.setURL("not a url", for: .tinyLLM)
        XCTAssertFalse(f.manager.isConfigured(.tinyLLM))
    }

    @MainActor
    func testLegacyServerSettingsMigrate() {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        f.defaults.set("192.168.1.50", forKey: "BlompieTVServerAddress")
        f.defaults.set(3000, forKey: "BlompieTVServerPort")
        f.defaults.set("OpenWebUI", forKey: "BlompieTVServerType")
        f.defaults.set("llama3.1", forKey: "BlompieTVSelectedModel")
        GameEngine.migrateLegacyServerSettings(defaults: f.defaults, into: f.manager)
        XCTAssertEqual(f.manager.url(for: .openWebUI), "http://192.168.1.50:3000")
        XCTAssertEqual(f.manager.model(for: .ollama), "llama3.1")
        XCTAssertNil(f.defaults.string(forKey: "BlompieTVServerAddress"))
        XCTAssertNil(f.defaults.string(forKey: "BlompieTVSelectedModel"))
    }
}

//
//  AIFrameTests.swift
//  BlompieTVTests
//
//  Frame: the AI-facing views render offscreen (no window): the header status
//  indicator in each state, and the Settings AI / Model / Cloud tabs. Images are
//  written to a temp folder for inspection.
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import XCTest
import SwiftUI
@testable import BlompieTV

@MainActor
final class AIFrameTests: XCTestCase {

    private var out: URL { FileManager.default.temporaryDirectory.appendingPathComponent("BlompieTVFrames", isDirectory: true) }

    private func render<V: View>(_ view: V, _ name: String, size: CGSize) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color.black))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "\(name) rendered nothing")
        XCTAssertEqual(image.width, Int(size.width))
        XCTAssertEqual(image.height, Int(size.height))
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        if let data = UIImage(cgImage: image).pngData() {
            try? data.write(to: out.appendingPathComponent("\(name).png"))
        }
        return image
    }

    /// Pixel bytes, for comparing frames.
    private func bytes(_ img: CGImage) -> [UInt8] {
        var d = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = CGContext(data: &d, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return d
    }

    private func distinctColours(_ img: CGImage) -> Int {
        let d = bytes(img)
        return Set(stride(from: 0, to: d.count, by: 4 * 5).map { Int(d[$0]) << 16 | Int(d[$0 + 1]) << 8 | Int(d[$0 + 2]) }).count
    }

    func testStatusIndicatorRendersEachStateDifferently() async throws {
        let size = CGSize(width: 700, height: 80)

        let offFixture = AIFixture(handler: everythingDown)
        defer { offFixture.tearDown() }
        let off = offFixture.engine(aiEnabled: false)
        XCTAssertEqual(NarratorStatusView(gameEngine: off).status, .off)
        let offImg = try render(NarratorStatusView(gameEngine: off), "status-off", size: size)

        let downFixture = AIFixture(handler: everythingDown)
        defer { downFixture.tearDown() }
        let down = downFixture.engine()
        await downFixture.manager.refreshStatus()
        XCTAssertEqual(NarratorStatusView(gameEngine: down).status, .offline)
        let downImg = try render(NarratorStatusView(gameEngine: down), "status-offline", size: size)

        let upFixture = AIFixture(handler: ollamaUp())
        defer { upFixture.tearDown() }
        let up = upFixture.engine()
        await upFixture.manager.refreshStatus()
        XCTAssertEqual(NarratorStatusView(gameEngine: up).status, .online("Ollama"))
        let upImg = try render(NarratorStatusView(gameEngine: up), "status-online", size: size)

        for img in [offImg, downImg, upImg] { XCTAssertGreaterThan(distinctColours(img), 2) }
        XCTAssertNotEqual(bytes(offImg), bytes(downImg))
        XCTAssertNotEqual(bytes(downImg), bytes(upImg))
        XCTAssertNotEqual(bytes(offImg), bytes(upImg))
    }

    func testStatusShowsLastTurnSource() async throws {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        let e = f.engine()
        let before = try render(NarratorStatusView(gameEngine: e), "status-before-turn", size: CGSize(width: 700, height: 80))
        e.startNewGame()
        await e.finishTurn()
        let after = try render(NarratorStatusView(gameEngine: e), "status-after-fallback", size: CGSize(width: 700, height: 80))
        XCTAssertNotEqual(bytes(before), bytes(after), "the 'Last turn' line appears")
    }

    func testSettingsTabsRender() throws {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        let e = f.engine()
        var images: [[UInt8]] = []
        for (tab, name) in [(0, "settings-ai"), (2, "settings-model"), (3, "settings-cloud")] {
            // ScrollView and segmented pickers don't render offscreen, so render the tab's cards.
            let view = SettingsView(gameEngine: e, isPresented: .constant(true), initialTab: tab).section(for: tab)
            let img = try render(view, name, size: CGSize(width: 1600, height: 2200))
            XCTAssertGreaterThan(distinctColours(img), 3, name)
            images.append(bytes(img))
        }
        XCTAssertEqual(Set(images.map { $0.hashValue }).count, images.count, "each tab looks different")
    }

    func testHeaderRendersWithStatus() throws {
        let f = AIFixture(handler: everythingDown)
        defer { f.tearDown() }
        let img = try render(HeaderView(gameEngine: f.engine()), "header", size: CGSize(width: 1920, height: 140))
        XCTAssertGreaterThan(distinctColours(img), 2)
    }
}

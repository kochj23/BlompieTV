# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Performance improvements
- Additional features based on community feedback

## [1.1.0] - 2026-11-11

### Added
- "Use AI narrator" switch (Settings > AI). Off: a built-in scripted narrator tells every turn and nothing is sent over the network.
- Scripted fallback: when AI is on but no backend answers, or the reply fails validation, the scripted narrator tells that turn. A failed AI call no longer shows an error or loses the turn.
- Backend picker over the canonical ids (auto, ollama, tinyllm, tinychat, openwebui, novagateway, openrouter, openai), editable endpoint URLs for every backend, and a model per backend.
- Auto mode: tries reachable backends in a fixed order (Ollama, TinyChat, TinyLLM, OpenWebUI, Nova Gateway, OpenRouter, OpenAI), with 4 s probes cached 30 s, 120 s request timeouts and at most 2 attempts per backend.
- Header status indicator (backend online / unreachable / AI off) and a last-turn source label; per-backend health and Test Connection in Settings.
- AI output validation (reasoning tags, control characters, prompt echoes, empty/garbage replies, length and action caps).
- OpenAI backend with its own Keychain key; on-screen key entry documented (iPhone Apple TV Keyboard).
- Tests: 148 tests across unit, integration, functional, retry, performance, security and frame suites; `BlompieTVTests.swift` now runs.

### Changed
- API keys use BlompieTV's own Keychain services `com.jkoch.blompietv.openrouter` and `com.jkoch.blompietv.openai`. Keys under AIStudio's `com.jkoch.aistudio.openrouter` or the interim `com.jordankoch.BlompieTV.*` names are migrated on first launch and the old items deleted. OpenRouter attribution headers now say BlompieTV.
- Top Shelf extension version now follows the app version (fixes the version-mismatch build warning).
- Local API `/api/status` reports the real app version.
- README fully rewritten.
- API keys are only sent over https.
- Old server address/port/type and model settings are migrated into the new settings on first launch.
- Ollama streaming now decodes UTF-8 correctly.

### Removed
- Unused `AIBackendManager.swift` and `AIBackendStatusMenu.swift` (never called).
- README claims for features that didn't exist. Google Cloud / Azure / AWS / IBM Watson backends are not offered (they were stubs or broken in the other apps).

## [1.0.0] - 2025-01-01

### Added
- Initial release
- Core functionality
- macOS native interface
- MIT License

---

*For detailed release notes, see [GitHub Releases](https://github.com/kochj23/BlompieTV/releases).*

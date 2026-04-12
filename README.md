# BlompieTV

![Build](https://github.com/kochj23/BlompieTV/actions/workflows/build.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-tvOS%2017.0+-black)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

An AI-powered text adventure game for Apple TV. BlompieTV brings classic Zork-style interactive fiction to the big screen, generating dynamic narratives in real time using large language models running on your local network. No cloud services required -- your stories stay on your network.

Written by Jordan Koch.

---

## Architecture

```
+------------------------------------------------------------------+
|                        Apple TV (tvOS 17+)                        |
|                                                                   |
|  +--------------------+    +----------------------------------+   |
|  |   BlompieTVApp     |    |         ContentView              |   |
|  |   (Entry Point)    |--->|  +------------+ +--------------+ |   |
|  +--------+-----------+    |  | StoryPanel | | ActionsPanel | |   |
|           |                |  +------------+ +--------------+ |   |
|           v                +----------------------------------+   |
|  +--------------------+                    |                      |
|  |  NovaAPIServer     |                    v                      |
|  |  (port 37427)      |    +----------------------------------+   |
|  |  loopback only     |    |           GameEngine             |   |
|  +--------------------+    |  - AI prompt construction        |   |
|                            |  - Response parsing & streaming  |   |
|  +--------------------+    |  - NPC / item / location tracker |   |
|  | TopShelfDataManager|    |  - Achievement system (10 total) |   |
|  | (App Group sync)   |    |  - Save/Load (multi-slot)       |   |
|  +--------------------+    |  - Undo history (20 snapshots)   |   |
|                            +----------------+-----------------+   |
|                                             |                     |
|  +------------------------------------------+------------------+  |
|  |                   Service Layer                              | |
|  |                                                              | |
|  |  +------------------+  +------------------+  +------------+  | |
|  |  | OllamaService    |  | AIBackendManager |  | Server     |  | |
|  |  | - /api/chat      |  | - Ollama         |  | Discovery  |  | |
|  |  | - /api/tags      |  | - TinyLLM        |  | - Bonjour  |  | |
|  |  | - streaming      |  | - TinyChat       |  | - Port     |  | |
|  |  | - token metrics  |  | - OpenWebUI      |  |   scan     |  | |
|  |  +------------------+  | - Auto-select    |  +------------+  | |
|  |                        +------------------+                  | |
|  +--------------------------------------------------------------+ |
|                             |                                     |
+-----------------------------+-------------------------------------+
                              | HTTP (local network)
                              v
               +-----------------------------+
               |    AI Backend (your Mac)    |
               |                             |
               |  Ollama     :11434          |
               |  OpenWebUI  :3000 / :8080   |
               |  TinyLLM    :8000           |
               |  TinyChat   :8000           |
               +-----------------------------+
```

---

## Features

### AI-Powered Storytelling
- Dynamic narrative generation using any local LLM (Mistral, Llama 3, Phi, and others)
- Configurable system prompt with detail level (Brief / Normal / Detailed) and tone (Serious / Balanced / Whimsical)
- Adjustable creativity temperature from 0.1 to 2.0
- Real-time streaming responses -- watch the story unfold token by token
- Token-per-second performance metrics displayed in the UI

### Multi-Backend Support
- **Ollama** -- Direct API integration (default port 11434)
- **OpenWebUI** -- Self-hosted AI platform (ports 3000 / 8080)
- **TinyLLM** -- Lightweight LLM server by Jason Cox (port 8000)
- **TinyChat** -- Fast chatbot interface by Jason Cox (port 8000)
- **Auto mode** -- Automatically selects the best available backend
- **Random Model Mode** -- Automatically cycles between installed models every N actions for varied storytelling

### Network Service Discovery
- Bonjour/mDNS auto-discovery of AI servers on the local network
- Port scanning across common subnet ranges (192.168.x.x, 10.0.0.x)
- Manual server configuration with connection testing
- Real-time connection status indicator

### Game Mechanics
- 10 unlockable achievements (First Steps, Explorer, World Traveler, Social Butterfly, Diplomat, Collector, Hoarder, Conversationalist, Veteran Adventurer, Trader)
- Automatic NPC, item, and location tracking parsed from AI responses
- Inventory management displayed in a grid view
- Full undo system with up to 20 state snapshots
- Transcript export for reviewing past adventures

### Save System
- Multiple named save slots with timestamp and message count
- Autosave after every action (configurable)
- Save/load UI with delete and bulk-delete options
- Top Shelf extension shows save slots and game stats on the Apple TV home screen

### TV-Optimized Interface
- Focus-based navigation designed for Siri Remote
- Large monospaced typography (configurable 20pt to 48pt)
- Dark gradient background with subtle grid overlay
- Cyan accent color scheme with animated button states
- Split-panel layout: story text on the left, action buttons on the right
- Settings organized in tabbed sections (Server / Game / Model)

### Local API Server
- HTTP API on port 37427 (loopback only, no external exposure)
- Endpoints: `/api/status` (app status and uptime), `/api/ping` (health check)
- Integration point for Nova (OpenClaw AI) and other local automation tools

### Top Shelf Extension
- Displays "New Adventure" and "Continue" quick-launch items
- Shows up to 3 save slot names
- Displays gameplay statistics (NPCs met, items found, locations visited)
- Data shared via App Group (`group.com.jordankoch.blompietv`)

---

## Requirements

### Hardware
- Apple TV 4K or Apple TV HD
- tvOS 17.0 or later

### AI Backend (one of the following, running on your local network)
- [Ollama](https://ollama.ai) (recommended) -- port 11434
- [OpenWebUI](https://openwebui.com) -- ports 3000 or 8080
- [TinyLLM](https://github.com/jasonacox/TinyLLM) -- port 8000
- [TinyChat](https://github.com/jasonacox/tinychat) -- port 8000

### Recommended Models
- mistral
- llama3.2
- llama3.1
- phi
- codellama

Any model available through your AI backend will appear in the model picker.

---

## Installation

BlompieTV is distributed as a direct install via Xcode. It is not available on the App Store.

### Option 1: Build from Source

```bash
# Clone the repository
git clone git@github.com:kochj23/BlompieTV.git
cd BlompieTV

# Open in Xcode
open BlompieTV.xcodeproj
```

1. Select your Apple TV as the deployment target in Xcode.
2. Build and run (Cmd+R).
3. Xcode will deploy the app to your Apple TV over the network or via USB-C.

### Build Requirements
- macOS 14.0 or later
- Xcode 15.0 or later
- Apple Developer account (required for device deployment)
- Swift 5.0

---

## Setup

### 1. Start an AI Backend

#### Ollama (Recommended)
```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull a model
ollama pull mistral

# Start the server (if not auto-started)
ollama serve
```

#### OpenWebUI
```bash
docker run -d -p 3000:8080 \
  -v open-webui:/app/backend/data \
  ghcr.io/open-webui/open-webui:main
```

### 2. Network Configuration
- Both devices (Apple TV and AI server) must be on the same local network.
- Firewall must allow inbound connections on the relevant port (11434 for Ollama, 3000/8080 for OpenWebUI, 8000 for TinyLLM/TinyChat).

### 3. Configure BlompieTV
1. Launch BlompieTV on your Apple TV. Settings will open automatically on first launch.
2. Use "Scan Network" to auto-discover servers, or enter the server IP and port manually.
3. Select the server type (Ollama or OpenWebUI).
4. Test the connection.
5. Choose your preferred AI model from the list.

---

## Gameplay

### Controls (Siri Remote)
| Input | Action |
|---|---|
| Swipe / D-pad | Navigate between action buttons |
| Click / Select | Choose an action |
| Menu | Access Settings, Save/Load, and Stats |

### Tips
- The game autosaves after each action when auto-save is enabled.
- Use **Undo** to step back if you take a wrong turn.
- Try different models for distinct storytelling voices.
- Enable **Random Model Mode** in Settings to cycle between models automatically.
- Adjust **Detail Level** and **Tone** to shape the narrative style.
- Higher **Creativity** values produce more surprising (and occasionally wilder) prose.

---

## Project Structure

```
BlompieTV/
|-- BlompieTVApp.swift              App entry point, starts Nova API server
|-- GameEngine.swift                Core game logic, AI prompt construction,
|                                   response parsing, save/load, achievements,
|                                   undo history, gameplay tracking
|-- NovaAPIServer.swift             Local HTTP API (port 37427, loopback only)
|-- TopShelfDataManager.swift       App Group data sync for Top Shelf extension
|-- Services/
|   |-- OllamaService.swift         Ollama and OpenWebUI API client (chat,
|   |                               streaming, model listing, token metrics)
|   |-- AIBackendManager.swift      Multi-backend manager (Ollama, TinyLLM,
|   |                               TinyChat, OpenWebUI, auto-select)
|   |-- AIBackendStatusMenu.swift   Status bar menu for backend selection
|   +-- ServerDiscovery.swift       Bonjour/mDNS + port-scan server discovery
|-- Views/
|   |-- ContentView.swift           Main game UI (story panel, actions panel,
|   |                               header, toolbar, TV background and styles)
|   |-- SettingsView.swift          Server, game, and model settings (tabbed)
|   |-- SaveLoadView.swift          Save/load slot management
|   +-- StatsView.swift             Statistics, achievements, inventory display
BlompieTVTopShelf/
+-- ContentProvider.swift           Top Shelf extension (save slots, stats)
```

---

## Nova / Claude API Integration

BlompieTV exposes a local HTTP API on port **37427** for integration with Nova (OpenClaw AI) and Claude Code.

**Platform:** tvOS
**Binding:** 127.0.0.1 only (no external network exposure)
**Auth:** `X-Nova-Token` header required for tvOS requests.

```bash
# Health check
curl -s http://127.0.0.1:37427/api/ping

# App status and uptime
curl -s http://127.0.0.1:37427/api/status | python3 -m json.tool
```

The API server starts automatically when the app launches.

---

## Third-Party Credits

- [TinyLLM](https://github.com/jasonacox/TinyLLM) by Jason Cox
- [TinyChat](https://github.com/jasonacox/tinychat) by Jason Cox
- [OpenWebUI](https://github.com/open-webui/open-webui) Community Project
- Inspired by classic text adventures, particularly Zork

---

## Version History

### v1.0.0 (February 2026)
- Initial tvOS release
- Multi-backend support (Ollama, OpenWebUI, TinyLLM, TinyChat)
- Network service discovery (Bonjour + port scanning)
- Focus-based Siri Remote navigation
- Save/load system with multiple named slots
- 10 unlockable achievements
- NPC, item, and location tracking
- Streaming responses with token-per-second metrics
- Top Shelf extension with game state display
- Random Model Mode for varied storytelling
- Nova API server on port 37427

---

## Author

**Jordan Koch**
GitHub: [@kochj23](https://github.com/kochj23)

---

## License

MIT License -- see [LICENSE](LICENSE) for full text.

Copyright (c) 2026 Jordan Koch.

---

> **Disclaimer:** This is a personal project created on my own time. It is not affiliated with, endorsed by, or representative of my employer.

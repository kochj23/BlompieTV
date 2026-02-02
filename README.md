# BlompieTV

A tvOS port of the Blompie AI-powered text adventure game. Experience classic Zork-style interactive fiction on your Apple TV, powered by Ollama or OpenWebUI running on your local network.

## Features

- **AI-Powered Storytelling**: Dynamic narrative generation using large language models
- **Network Service Discovery**: Automatically finds Ollama and OpenWebUI servers on your network
- **Focus-Based Navigation**: Optimized for Siri Remote with large, TV-friendly UI
- **Save/Load System**: Multiple save slots to continue your adventures
- **Achievement System**: Track your progress with 10 unlockable achievements
- **Model Selection**: Choose from available models on your AI server
- **Streaming Responses**: Watch the story unfold in real-time
- **Statistics Tracking**: Monitor NPCs met, items collected, locations visited

## Screenshots

*Screenshots coming soon*

## Requirements

### Hardware
- Apple TV 4K or Apple TV HD
- tvOS 17.0 or later

### Network Requirements
One of the following AI backends running on your local network:
- **Ollama** (default port 11434) - https://ollama.ai
- **OpenWebUI** (default ports 3000 or 8080) - https://openwebui.com

### Recommended Models
- mistral
- llama3.2
- llama3.1
- codellama
- phi

## Setup Instructions

### 1. Install an AI Backend

#### Option A: Ollama (Recommended)
```bash
# Install Ollama on your Mac/Linux server
curl -fsSL https://ollama.com/install.sh | sh

# Pull a model
ollama pull mistral

# Start the server (if not auto-started)
ollama serve
```

#### Option B: OpenWebUI
```bash
# Using Docker
docker run -d -p 3000:8080 \
  -v open-webui:/app/backend/data \
  ghcr.io/open-webui/open-webui:main
```

### 2. Configure Network Access
Ensure your AI server is accessible from your Apple TV:
- Both devices must be on the same local network
- Firewall must allow connections on the relevant port (11434 for Ollama, 3000/8080 for OpenWebUI)

### 3. Install BlompieTV
- Build from source using Xcode
- Deploy to your Apple TV via Xcode

### 4. Configure the App
1. Launch BlompieTV on your Apple TV
2. Go to Settings
3. Either use "Scan Network" to automatically discover servers, or manually enter:
   - Server IP address (e.g., 192.168.1.100)
   - Port number (e.g., 11434)
   - Server type (Ollama or OpenWebUI)
4. Test the connection
5. Select your preferred AI model

## Building from Source

### Requirements
- macOS 14.0 or later
- Xcode 15.0 or later
- Apple Developer account (for device deployment)

### Build Steps
```bash
# Clone the repository
git clone https://github.com/kochj23/BlompieTV.git
cd BlompieTV

# Open in Xcode
open BlompieTV.xcodeproj

# Select your Apple TV as the deployment target
# Build and run (Cmd+R)
```

## Gameplay

### Controls (Siri Remote)
- **Swipe/D-pad**: Navigate between action buttons
- **Click/Select**: Choose an action
- **Menu**: Access settings, save/load, and stats

### Tips
- The game automatically saves after each action (if auto-save is enabled)
- Use "Undo" to go back if you make a wrong choice
- Experiment with different models for varied storytelling styles
- Enable "Random Model Mode" in settings for diverse narrative experiences

## Project Structure

```
BlompieTV/
├── BlompieTVApp.swift          # App entry point
├── GameEngine.swift            # Core game logic
├── Services/
│   ├── OllamaService.swift     # AI backend communication
│   └── ServerDiscovery.swift   # Network service discovery
└── Views/
    ├── ContentView.swift       # Main game UI
    ├── SettingsView.swift      # Server and game settings
    ├── SaveLoadView.swift      # Save/load management
    └── StatsView.swift         # Statistics and achievements
```

## Acknowledgments

- Original Blompie macOS app concept
- Inspired by classic text adventures like Zork
- Powered by open-source AI models

## Author

**Jordan Koch**
- GitHub: [@kochj23](https://github.com/kochj23)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Version History

### v1.0.0 (February 2026)
- Initial tvOS port from macOS Blompie
- Network service discovery for Ollama/OpenWebUI
- Focus-based navigation for Siri Remote
- Full save/load and achievement system

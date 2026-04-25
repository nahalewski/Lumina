<p align="center">
  <img src="assets/icon/icon.png" width="128" height="128" alt="Lumina Logo">
</p>

# <p align="center">Lumina Media Player</p>
### <p align="center">Cinematic • Premium • Dark Sakura Edition</p>

---

![Lumina Hero](assets/readme/hero.png)

Lumina is a state-of-the-art media player built with Flutter, designed for those who value both aesthetics and functionality. Featuring a stunning **Dark Sakura** theme, it provides a seamless cinematic experience across macOS, iOS, Apple TV, and Samsung TV (Tizen).

## ✨ Key Features

- **🌸 Dark Sakura Aesthetic**: A curated, high-end theme with glassmorphism, smooth gradients, and falling petal micro-animations.
- **🎥 Cinematic Intros**: Automatic introduction sequences (`intro.mp4`) that play before your movies for a theater-like feel.
- **🎵 Ambient Menu Music**: Immersive background music (`menu_music.mp4`) that flows through the navigation menus.
- **🌐 Built-in Media Server**: Auto-starting HTTP server to stream your library to other devices on your network.
- **☁️ Cloudflare Tunnel Integration**: One-click remote access to your library from anywhere in the world without port forwarding.
- **📺 Multi-Platform Support**: Tailored interfaces for Desktop, Mobile, and Smart TVs.
- **🤖 AI Subtitles**: Real-time transcription and translation powered by on-device Whisper models.
- **🕵️ Deep Monitoring**: Integrated debug windows in settings for real-time tracking of server and tunnel logs.

## 🛠 Technology Stack

- **Framework**: [Flutter](https://flutter.dev)
- **Local Server**: Dart `HttpServer`
- **Remote Access**: Cloudflare Tunnel (`cloudflared`)
- **Video Engine**: AVFoundation (macOS/iOS) / Tizen Video Player
- **State Management**: Provider
- **Persistence**: SQLite & JSON

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (latest stable)
- macOS 14+ (for desktop features)
- `cloudflared` installed via Homebrew: `brew install cloudflared`

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/nahalewski/Lumina.git
   cd lumina_media
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run on macOS:**
   ```bash
   flutter run -d macos
   ```

## 📐 Project Structure

- `lib/providers/`: Core business logic and server management.
- `lib/services/`: Native bridges, IPTV, and Tunnel services.
- `lib/screens/`: platform-specific UI for TV, Desktop, and Mobile.
- `lib/themes/`: The Dark Sakura design system.
- `tizen/`: Samsung TV specific project files.
- `macos/`: Native macOS implementation including `SubtitleBridge`.

## 📜 License

© 2024 Ben Nahalewski. All rights reserved.

---

<p align="center">
  Developed with ❤️ for the cinematic enthusiast.
</p>

# 🦑 Orphij — PS5-Controller 3D Party Game

<p align="center">
  <img src="https://readme-typing-svg.herokuapp.com/?lines=Red+Light%2C+Green+Light...;PS5+Controller+Ready;Host+a+Room%2C+Share+the+Code;Play+With+Friends+on+LAN&font=Fira%20Code&center=true&width=600&height=50">
</p>

<p align="center"><b>⚠️ Private repository — see <a href="#-license--asset-notice">License &amp; Asset Notice</a> before ever making this public.</b></p>

---

## 📌 What is Orphij?

A solo-built, Squid-Game-style **"Red Light, Green Light"** party game in 3D — made from scratch in Godot 4 on a laptop with no dedicated GPU. Fully playable with a **PS5 (DualSense) controller**, end to end: menus, login, lobby, and gameplay.

---

## 📌 Project Structure

```plaintext
Orphij (MyGame3D)
│   project.godot
│   README.md
│
├── scenes/                 # Login, Lobby, Player, Main
│   └── games/               # RedLightGreenLight.tscn
│
├── scripts/
│   │   local_auth.gd        # Auth       -- local account + session, no cloud
│   │   network_manager.gd   # Network    -- LAN host/join, discovery, room codes
│   │   lobby.gd             # Lobby UI, customization panel, networked room
│   │   login.gd             # Login / Signup screen
│   │   player.gd            # Movement, animation, outfit colors
│   │   world_builder.gd     # Procedural level/UI building helpers
│   │   ui_theme.gd          # Shared dark+gold UI theme
│   └── games/
│       └── red_light_green_light.gd   # Core game mode logic
│
└── assets/
    ├── arena/                # 3D arena model (see license notice)
    ├── characters/           # Character models
    ├── audio/                # Procedurally generated SFX (WAV)
    └── fonts/
```

---

## 🛠 Tech Stack

<p align="center">
  <img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/godot/godot-original.svg" width="40"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Engine-Godot%204.7-478CBF?style=for-the-badge&logo=godotengine&logoColor=white"/>
  <img src="https://img.shields.io/badge/Language-GDScript-355570?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Multiplayer-LAN%20(ENet)-22C55E?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Input-PS5%20DualSense-0070CC?style=for-the-badge&logo=playstation&logoColor=white"/>
</p>

**Engine:** Godot 4.7 (GDScript) · everything built procedurally in code, no external plugins/GDExtensions
**Multiplayer:** Built-in `ENetMultiplayerPeer` + `MultiplayerSpawner`/`MultiplayerSynchronizer`, UDP broadcast for LAN discovery
**Accounts:** 100% local — JSON file under `user://`, no external service, no account to connect

---

## 🌟 Features

* 🎮 **Full PS5 Controller Support** — D-pad/stick navigates every menu (Login, Signup, Lobby, in-game pause), Cross (✕) confirms. No mouse needed anywhere.
* 🔐 **Local Account System** — sign up / log in without connecting any external/cloud account. Session persists across launches; logout available in-game.
* 🎨 **Character Customization** — skin, hair, shirt, and pants color, with **live preview** before you commit (Cancel reverts, Done saves).
* 🌐 **LAN Multiplayer, Two Ways to Join** — host a game and get a **4-character room code** to share with friends, or pick a friend's game from an auto-discovered list. Manual IP entry stays available as a fallback.
* 🚦 **Red Light, Green Light Game Mode** — move on green, freeze on red, get caught and you're out. Host-authoritative rules, real-time sync, clean disconnect handling.
* 🚪 **Proper Navigation Everywhere** — every screen has a way back, out to the lobby, or to quit the game entirely.
* 🖥️ **Modern 2026-style UI** — dark + gold theme across menus and HUD.

---

## 🚀 How to Run Locally

### 1️⃣ Clone
```bash
git clone https://github.com/dilzaibofficial/Orphij-3D-Game.git
cd Orphij-3D-Game
```

### 2️⃣ Open in Godot
- Install **Godot 4.7+** (Standard, not .NET build).
- Open Godot → **Import** → select `project.godot` from this folder.
- Press **F5** (or the Play button) to run.

### 3️⃣ Controls
| Action | Keyboard | PS5 Controller |
|---|---|---|
| Move | WASD | Left Stick |
| Sprint | Shift | R2 (analog) |
| Menu navigate | Arrow Keys | D-pad / Left Stick |
| Confirm / Click | Enter | ✕ (Cross) |
| Pause | Esc | Options |

### 4️⃣ Playing with friends (same WiFi)
- One player **Hosts** → gets a room code (e.g. `X7QK`).
- Friends pick **Join** → either select the game from the auto-discovered list, or type the room code directly.

---

## ⚖️ License & Asset Notice

This is a **student / educational, local-only project** — not distributed or monetized.

The arena model in `assets/arena/` is used under **CC-BY-NC-ND-4.0** (Sketchfab), which forbids redistribution and derivative use — including unmodified reuse in another project. It is kept here **only** because this repository is private and not distributed. **Before this project is ever made public, open-sourced, or shipped anywhere, that asset must be removed or replaced.**

---

## 🗺️ Known Limitations / Roadmap

* 🌍 Multiplayer currently works over **LAN only** (same WiFi). Internet-wide play across different networks would need an always-on relay server — not yet built.
* 🎨 Character customization is applied locally; it isn't yet synced so other players see your outfit over the network.

---

## 📡 Connect with Me

<p align="center">
  <a href="https://dilzaibofficial.github.io/" target="_blank"><img src="https://img.shields.io/badge/Website-000000?style=for-the-badge&logo=About.me&logoColor=white"/></a>
  <a href="https://www.linkedin.com/in/dilzaibofficial" target="_blank"><img src="https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white"/></a>
  <a href="https://x.com/dilzaibofficial" target="_blank"><img src="https://img.shields.io/badge/Twitter-1DA1F2?style=for-the-badge&logo=twitter&logoColor=white"/></a>
  <a href="https://www.instagram.com/dilzaibofficial" target="_blank"><img src="https://img.shields.io/badge/Instagram-E4405F?style=for-the-badge&logo=instagram&logoColor=white"/></a>
  <a href="https://youtube.com/@dilzaibofficial" target="_blank"><img src="https://img.shields.io/badge/YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white"/></a>
</p>

---

👨‍💻 **Dil Zaib**
*Solo game dev, learning as I build.*

# Blackbox Mod

## Overview
Admin panel mod for the game Species: Unknown, eventually adding more features such as a radar
This mod uses the lua API from UE4SS and an external python menu (Will be integrated into C++ mod eventually)

## Status
**In Development** - This project is a work in progress, expect errors and broken features.
Current Status: GUI integration, overlay state panels, and registry tooling

## Features

### General
- Command system with help documentation
- Player listing with GUI support
- Return position tracking system
- GUI state management
- Overlay auto-launch (Windows) with process detection + one-shot guard
- Robust game-process detection and bridge/overlay health indicators
- Panel open/close state handling with state payloads

### Teleportation
- Teleport to named map locations
- Teleport to players by name
- Teleport to nearest player
- Teleport to specific items
- Teleport to weapons
- Teleport to monsters
- Bring players to you
- Bring all players to your location
- Bring nearest player to you
- Bring items to you
- Bring weapons to you
- Bring monsters to you
- Map-wide teleportation for all players
- Return to saved positions

### Player Status
- Healing (restore health)
- God mode (invincibility toggle)
- Stamina restoration
- Battery management
- Walk speed modification

### Inventory & Equipment
- Unlimited ammo toggle
- Max out ammo
- Set weapon damage
- Set player HP
- Set player max HP
- Weapon GUI state (current weapon) with overlay controls

### Environmental Controls
- Pipe status checking
- Pipe state management
- Lab airlock status monitoring
- Lab airlock state control
- Self-destruct activation

### Creature Management
- List monsters in area
- Go to monsters
- Bring monsters to you
- Monster removal
- Invisibility toggle

### Contract Management
- Open contracts interface
- Start contracts
- Contract state tracking
- Contract list discovery + GUI cache + overlay controls
- Contract GUI state and refresh pipeline
- Contract list decoding and value/type extraction

### Overlay UI
- New Weapons and Contracts tabs
- Weapons UI with unlimited ammo toggle and auto-refresh
- Contracts UI with list/type/value display and toggle controls
- Core State panel (map/world/pawn/radar/registry counts + emit/prune timing)
- State read/write age indicators and refresh scheduling

### Debug & Registry
- State snapshot action and verbose hookprints toggle
- Registry metrics and counters in overlay
- Registry clear/rebuild actions
- Registry storage rework (by UID/object, stable numeric IDs)
- Throttled scanning, periodic rescans, and improved pruning

### Utilities
- Expanded UE utility layer (safe field/call helpers, null/valid checks)
- Cached controller/pawn/map accessors and UFunction helpers

## Installation
Instructions to be added.

## Usage
Documentation to be added.

## Support
For issues or questions, please open an issue on the repository.

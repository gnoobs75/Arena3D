# Arena Godot

A tactical card battle game built with Godot 4.5.

## Overview

Arena is a turn-based strategy game where two players control teams of champions on a 10x10 grid battlefield. Each champion has unique abilities represented by cards that can be played during combat.

## Features

- **12 Unique Champions**: Brute, Ranger, Beast, Redeemer, Confessor, Barbarian, Burglar, Berserker, Shaman, Illusionist, Dark Wizard, and Alchemist
- **112 Cards**: Each champion has their own deck of Action, Response, and Equipment cards
- **Tactical Grid Combat**: 10x10 battlefield with walls, pits, and positioning strategies
- **Response System**: React to opponent actions with response cards during combat
- **AI Opponent**: Play against an AI with configurable difficulty

## Project Structure

```
arena_godot/
├── data/
│   ├── cards.json          # All card definitions
│   └── champions.json      # Champion stats and abilities
├── scenes/
│   ├── game/
│   │   ├── board/          # 10x10 game board
│   │   ├── cards/          # Card visuals, hand, discard pile
│   │   ├── game.tscn       # Main game scene
│   │   └── game_hud.tscn   # HUD with player stats
│   ├── main/               # Entry point
│   └── testing/            # AI testing scenes
├── scripts/
│   ├── autoload/           # Singletons (CardDatabase)
│   ├── core/               # Game logic (state, actions, effects)
│   ├── ai/                 # AI controller
│   └── ui/                 # Visual theme constants
├── docs/                   # Documentation
└── assets/                 # Art, audio, fonts
```

## Visual System

The game uses a procedural visual system with styled graphics:

### Cards
- **Card Fronts**: Champion-colored headers, mana cost gems (color-coded 0-4), type badges, art areas with champion symbols, wrapped description text
- **Card Backs**: Universal "ARENA" design with diamond pattern and corner flourishes
- **States**: Playable cards are bright, unplayable cards are dimmed

### Board
- 10x10 grid with coordinate labels (A-J, 1-10)
- Checkerboard tile pattern for depth
- Brick pattern for wall tiles
- Glowing edges for pit tiles
- Color-coded highlights: green (move), red (attack), blue (cast), gold (selected)

### Champion Tokens
- Circular tokens with team colors (blue/red)
- Champion initials displayed
- HP bars with color coding (green > 50%, yellow 25-50%, red < 25%)
- Selection glow effect

### HUD
- Mana gem display (filled/empty visualization)
- Mini champion boxes with HP bars
- Team-colored panels
- Turn and phase indicators

### Theme System
All visual constants are centralized in `scripts/ui/visual_theme.gd`:
- Champion color palettes
- Card type colors
- Mana cost colors
- Board tile colors
- Highlight colors
- HP bar colors
- Font sizes

## Controls

- **Click champion**: Select to see available moves/attacks
- **Click tile**: Move selected champion or target for abilities
- **Click card**: Select card to cast
- **End Turn button**: End your turn
- **Undo button**: Undo last action

## Running the Game

1. Open the project in Godot 4.5+
2. Run the main scene (`scenes/main/main.tscn`)
3. Select champions and start playing

## Documentation

- [Response Card Workflows](docs/response_card_workflows.md) - Detailed documentation of the response card system

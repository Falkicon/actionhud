# ActionHud

A lightweight, high-performance action bar HUD for World of Warcraft Retail. Displays a compact 6×4 grid of your primary action bars, designed for quick combat awareness.

![WoW Version](https://img.shields.io/badge/WoW-11.0%2B-blue)
![Interface](https://img.shields.io/badge/Interface-110002-green)
[![GitHub](https://img.shields.io/badge/GitHub-Falkicon%2FActionHud-181717?logo=github)](https://github.com/Falkicon/ActionHud)
[![Sponsor](https://img.shields.io/badge/Sponsor-pink?logo=githubsponsors)](https://github.com/sponsors/Falkicon)

> **Midnight Compatibility**: This addon is fully prepared for WoW 12.0 (Midnight). It uses passthrough patterns for secret values during combat, defensive API wrappers, and graceful degradation for restricted zones.

## Features

- **Compact Grid** – Shows Action Bar 1 (slots 1-12) and Action Bar 2 (slots 61-72) in a tight layout
- **Stance/Form Support** – Automatically updates for Druid forms, Rogue stealth, and other bar swaps
- **Visual Feedback**:
  - **Yellow Glow** – Proc tracking via Spell Activation Overlay
  - **Blue Glow** – WoW 11.x Assisted Combat rotation recommendations
  - **Cooldowns** – Clear countdown numbers with configurable font size
  - **Charges** – Stack counts for charge-based abilities
  - **Usability** – Desaturates unusable skills; tints out-of-range abilities red
- **Resource Bars**:
  - **Health & Power** – Compact bars for Player and Target
  - **Class Resources** – Dynamic bars for Combo Points, Holy Power, Chi, etc. that auto-hide when empty
- **Profiles** – Support for character-specific settings and profile sharing via AceDB
- **Integration** – Minimap button and DataBroker (LDB) support for quick access

## Installation

1. Download or clone this repository
2. Place the `ActionHud` folder in your WoW addons directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
3. Restart WoW or type `/reload` if already running

## How to Use

ActionHud mirrors your Action Bars 1 and 2. Set them up correctly so the HUD displays what you want:

### Step 1: Configure Your Action Bars

1. Open **Edit Mode** (`Esc` → `Edit Mode`)
2. Select **Action Bar 1** and set:
   - **Orientation**: Horizontal
   - **Buttons**: 12
   - **Wrap**: After 6 buttons
3. Select **Action Bar 2** and use the same settings
4. **Stack them**: Position Bar 1 directly above Bar 2 (this creates a 6×4 grid)

### Step 2: Place Your Abilities

- Put the abilities you want on the HUD in **Action Bar 1** (top 2 rows) and **Action Bar 2** (bottom 2 rows)
- ActionHud will automatically display whatever is on these bars

### Step 3: Position the HUD

1. Open ActionHud settings (`Esc` → `Options` → `AddOns` → `ActionHud`)
2. Uncheck **Lock Frame** (a green overlay appears)
3. Drag the HUD to your preferred screen position
4. Re-check **Lock Frame** to lock it in place

> **Tip**: You can hide the default Action Bars 1 and 2 in Edit Mode once you've confirmed ActionHud is showing everything correctly.

## Prerequisites

To get the most out of ActionHud, enable these native WoW features in **Gameplay** → **Gameplay Enhancements**:

- **Enable Cooldown Manager** – Required for the Cooldown Manager module to function
- **Assisted Highlight** – Required to see the blue glow recommendations on the HUD

## Slash Commands

| Command | Description |
|---------|-------------|
| `/ah` or `/actionhud` | Opens the configuration dialog |
| `/ah debug` | Prints debug info if enabled |

## Configuration

Open the settings panel via slash command or `Esc` → `Options` → `AddOns` → `ActionHud`.

### Settings Sections

- **General** – Lock frame, Opacity, and Icon Dimensions
- **Resource Bars** – Enable/Disable Health & Power bars, adjust size/position
- **Fonts** – Customize fonts and sizes for cooldowns and stack counts (LibSharedMedia support)
- **Profiles** – Create, Copy, Delete, or Reset profiles for different characters

| Setting | Description |
|---------|-------------|
| Lock Frame | Toggle to drag/position the HUD (green overlay when unlocked) |
| Icon Width/Height | Adjust icon dimensions (10-30px) |
| Cooldown Font Size | Size of cooldown countdown text (6-16px) |
| Stack Count Font Size | Size of charge/stack numbers (6-16px) |
| Background Opacity | Visibility of empty slot backgrounds (0-100%) |
| Proc Glow Opacity | Brightness of yellow proc border (0-100%) |
| Assist Glow Opacity | Brightness of blue recommendation border (0-100%) |

## Requirements

- World of Warcraft Retail 11.0+ or Midnight Beta
- Action Bars 1 and 2 configured as described above

## Files

| File | Purpose |
|------|---------|
| `ActionHud.toc` | Addon manifest |
| `Core.lua` | Frame creation, event handling, state updates |
| `Cooldowns.lua` | Cooldown Manager (Proxy System, Hijacking, Layout) |
| `SettingsUI.lua` | Blizzard Settings panel integration |

## Technical Notes

- **Event-Driven** – Primary updates react to game events; minimal polling with adaptive throttling (20 Hz active, 2 Hz idle)
- **Static Frames** – All 24 buttons are created once at load, never during combat
- **Minimal Memory** – Reuses textures, frames, and tables; eliminates per-frame allocations
- **API Resilience** – All critical APIs wrapped with `pcall` for stability across patches
- **Midnight Ready** – Passthrough patterns for secret values; graceful degradation when data is restricted
- **Ace3 Framework** – Uses AceAddon, AceDB, AceConfig for robust infrastructure

## Credits

A special thanks to the authors of:

- **Cooldown Manager Tweaks** – For logic references related to styling native cooldown frames
- **Addon Bars Enhanced** – For inspiration and implementation details on hijacking native frames

## Support

If you find ActionHud useful, consider [sponsoring on GitHub](https://github.com/sponsors/Falkicon) to support continued development and new addons. Every contribution helps!

## License

MIT License – see [LICENSE](LICENSE) for details.

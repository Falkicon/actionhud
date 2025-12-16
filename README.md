# ActionHud

A lightweight, high-performance action bar HUD for World of Warcraft Retail. Displays a compact 6x4 grid of your primary action bars, designed for quick combat awareness.

## Features

- **Compact Grid**: Shows Action Bar 1 (slots 1-12) and Action Bar 2 (slots 61-72) in a tight layout.
- **Stance/Form Support**: Automatically updates for Druid forms, Rogue stealth, and other bar swaps.
- **Visual Feedback**:
  - **Yellow Glow**: Proc tracking via Spell Activation Overlay.
  - **Blue Glow**: WoW 11.x Assisted Combat rotation recommendations.
  - **Cooldowns**: Clear countdown numbers with configurable font size.
  - **Charges**: Stack counts for charge-based abilities.
  - **Usability**: Desaturates unusable skills; tints out-of-range abilities red.

## How to Use

ActionHud mirrors your Action Bars 1 and 2. Set them up correctly so the HUD displays what you want:

### Step 1: Configure Your Action Bars
1. Open **Edit Mode** (`Esc` → `Edit Mode`).
2. Select **Action Bar 1** and set:
   - **Orientation**: Horizontal
   - **Buttons**: 12
   - **Wrap**: After 6 buttons
3. Select **Action Bar 2** and use the same settings.
4. **Stack them**: Position Bar 1 directly above Bar 2 (this creates a 6×4 grid).

### Step 2: Place Your Abilities
- Put the abilities you want on the HUD in **Action Bar 1** (top 2 rows) and **Action Bar 2** (bottom 2 rows).
- ActionHud will automatically display whatever is on these bars.

### Step 3: Position the HUD
1. Open ActionHud settings (`Esc` → `Options` → `AddOns` → `ActionHud`).
2. Uncheck **Lock Frame** (a green overlay appears).
3. Drag the HUD to your preferred screen position.
4. Re-check **Lock Frame** to lock it in place.

> **Tip**: You can hide the default Action Bars 1 and 2 in Edit Mode once you've confirmed ActionHud is showing everything correctly.

## Configuration

Open via: `Esc` → `Options` → `AddOns` → `ActionHud`

| Setting | Description |
|---------|-------------|
| Lock Frame | Toggle to drag/position the HUD (green overlay when unlocked). |
| Icon Width/Height | Adjust icon dimensions (10-30px). |
| Cooldown Font Size | Size of cooldown countdown text (6-16px). |
| Stack Count Font Size | Size of charge/stack numbers (6-16px). |
| Background Opacity | Visibility of empty slot backgrounds (0-100%). |
| Proc Glow Opacity | Brightness of yellow proc border (0-100%). |
| Assist Glow Opacity | Brightness of blue recommendation border (0-100%). |

## Commands

- `/actionhud` — Prints a debug dump of button states to the error frame.

## Installation

1. Place the `ActionHud` folder in `World of Warcraft/_retail_/Interface/AddOns/`.
2. Reload the game or restart the client.

## Performance

- **Event-Driven**: No `OnUpdate` polling; reacts only to game events.
- **Static Frames**: All 24 buttons are created once at load, never during combat.
- **Minimal Memory**: Reuses textures and frames; avoids table churn.

---

*MIT License • Created for WoW 11.x (The War Within)*

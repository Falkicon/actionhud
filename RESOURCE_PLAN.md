---
description: Implementation Plan for Resource Bars
---

# Feature: HUD Resource Bars

## Goal
Add configurable Personal and Target resource bars (Health/Power) to the ActionHud, supporting dynamic resizing and multi-stage class powers, while maintaining "Midnight" (WoW 12.0) API compliance.

## Viability
- **Feasible**: Yes.
- **Complexity**: Medium (Dynamic layout logic + Class Power handling).
- **Compliance**: Uses `StatusBar` widgets to handle potential future "Secret" values.

## Architecture

### 1. New Module: `Resources.lua`
A dedicated file to handle resource bar logic, keeping `Core.lua` clean.
- **Frames**:
  - `Container`: Holds all bars, positioned relative to the Main HUD.
  - `PlayerGroup`: Holds Player Health/Power.
  - `TargetGroup`: Holds Target Health/Power.
- **Components**:
  - `HealthBar`: StatusBar (Class Color / Reaction Color).
  - `PowerBar`: StatusBar (Power Color).
  - `ClassPowerBar`: Specialized StatusBar or Pip-Display for Combo Points/Essence/etc.

### 2. Logic Flow
- **Initialization**: Create frames on load.
- **Events**:
  - `PLAYER_TARGET_CHANGED`: Toggles `TargetGroup` visibility and resizes `PlayerGroup` (Full Width vs 50% Split).
  - `UNIT_HEALTH` / `UNIT_POWER_UPDATE`: direct `StatusBar:SetValue()`.
  - `UNIT_DISPLAYPOWER`: Updates power bar color/max for shapeshifts.
- **Safety**: Use `pcall` for all Unit API calls.

### 3. Settings (`SettingsUI.lua`)
New "Resource Bars" Section:
- **Enable**: Toggle entire feature.
- **Position**: "Top" or "Bottom" (relative to 6x4 Grid).
- **Show Target**: Toggle Target bar logic.
- **Height**: Slider (e.g., 4px - 15px).

## Execution Steps

1.  **Create `Resources.lua`**:
    - Implement frame construction.
    - Implement `Update` functions for Health/Power.
    - Implement `UpdateLayout` for Split-View logic.
2.  **Update `Core.lua`**:
    - Load `Resources.lua` (via TOC).
    - Call `Resources:Initialize()` on login.
    - Hook into `UpdateLayout` to position the Resource Container.
3.  **Update `SettingsUI.lua`**:
    - Add the new sliders and toggles.
4.  **Update `ActionHud.toc`**:
    - Add `Resources.lua`.

## Visual Style
- **Texture**: Clean, flat texture (`Interface\Buttons\WHITE8x8`).
- **Colors**:
  - Health: Class Color (Player), Reaction Color (Target).
  - Power: Standard Power Color (Energy=Yellow, Rage=Red, Mana=Blue).
- **Background**: Faded version of the bar color or black.

## Midnight Compliance Strategy
- **Do**: `StatusBar:SetMinMaxValues(0, UnitHealthMax("player"))`, `StatusBar:SetValue(UnitHealth("player"))`.
- **Don't**: `local percent = UnitHealth("player") / UnitHealthMax("player")`.

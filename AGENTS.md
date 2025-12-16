# ActionHud Agent Documentation

## Architecture Overview

ActionHud is a **single-purpose HUD** built on the native WoW API. It bypasses framework libraries (like Ace3) to ensure maximum performance and minimal footprint.

### Files

*   `Core.lua`: The heart of the addon. Handles frame creation, event listeners (`COMBAT_LOG`, `SPELL_UPDATE`, etc.), and button state logic.
*   `SettingsUI.lua`: Integrates with `Settings.RegisterAddOnCategory` to provide a native config panel.
*   `ActionHud.toc`: Metadata and load order.

## Core Logic

### The "Virtual Slot" System
ActionHud does not use `SecureActionButtonTemplate` to avoid taint issues with custom sizing and clicking. Instead, it creates **Passthrough Frames** that visualize standard Action slots (`1-12`, `61-72`).

*   **Mapping**: The grid is strictly mapped to specific Action IDs.
*   **Updates**: 
    *   `UpdateAction`, `UpdateCooldown`, `UpdateState` are the central instructions called on events.
    *   It queries `GetActionTexture`, `GetActionCooldown`, `GetActionCount`, and `IsUsableAction`.
    *   It handles **Fallbacks**: If standard API fails (e.g. for Skyriding charges), it performs a deep lookup via `C_Spell.GetSpellCharges`.

### Assisted Highlight ("The Blue Glow")
WoW 11.0 Introduced `AssistedCombatManager`. ActionHud hooks this system via `hooksecurefunc`:
1.  **Hook**: `AssistedCombatManager:SetAssistedHighlightFrameShown`.
2.  **Mirror**: When the default UI shows a glow, ActionHud spawns/shows a lightweight `BackdropTemplate` frame on the corresponding HUD button.
3.  **Crop**: The glow logic respects the custom `iconWidth` / `iconHeight` settings to ensure perfect alignment.

## Performance Considerations

*   **Events over Polling**: The addon listens to granular events (`ACTIONBAR_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES`). It **never** runs an `OnUpdate` script for state checking.
*   **Object Pooling**: All 24 buttons are static. No frames are created/destroyed during combat.
*   **Efficient Cropping**: Texture cropping (`SetTexCoord`) is calculated via a helper `ApplyIconCrop` only when textures change or layout updates.

## Midnight Expansion (12.0) Preparedness

*   **Secret Values**: The addon's charge logic checks `if count > 1` and uses `SetText`. In 12.0, `count` may be a "Secret Value" (opaque userdata) during combat.
    *   *Risk*: `count > 1` comparison will error.
    *   *Mitigation Strategy*: Future updates should use `issecretvalue()` checks and utilize `StatusBar` widgets (which accept secrets) or Boolean "Has Charges" states if numeric display is blocked.

## Debugging

*   **Slash Command**: `/actionhud` dumps the state of all virtual buttons vs real action slots.
*   **Globals**: `ActionHudFrame` (Main window), `ActionHudDB` (SavedVariables).

---
**Agent Note**: When refactoring, maintain the separation between `Core` (Logic) and `SettingsUI` (Config). Do not introduce external dependencies.

# ActionHud

**ActionHud** is a lightweight, high-performance action HUD designed for World of Warcraft Retail. It provides a compact 6x4 grid visualization of your primary action bars, optimized for quick combat decision-making.

## Features

*   **Compact Grid Layout**: Visualizes Action Bar 1 (Slots 1-12) and Action Bar 2 (Slots 61-72) in a tight 6x4 grid.
*   **Stance & Form Support**: Automatically updates to reflect Druid forms, Rogue stealth, and other stance-based bar swaps.
*   **Assisted Highlight**: Fully supports the new WoW 11.x "Blue Glow" rotation assistance, mirroring the default UI's recommendations.
*   **Proc Tracking**: Displays standard yellow "Spell Activation Overlay" glows for procs.
*   **Combat Essentials**:
    *   **Cooldowns**: High-visibility cooldown numbers.
    *   **Charges**: Stack counts for charge-based abilities.
    *   **Range & Usability**: Desaturates unusable skills and tints out-of-range targets red.
    *   **Skyriding Ready**: Correctly tracks charges even for complex riding abilities.

## Configuration

ActionHud provides a native Blizzard Settings panel for customization.

*   **Open Settings**: `Esc` -> `Options` -> `AddOns` -> `ActionHud`.
*   **Unlock Frame**: Toggle "Lock frame" to drag the HUD anywhere on screen (shows a green overlay when unlocked).
*   **Customization**:
    *   **Icon Width/Height**: precise sizing (10-30px).
    *   **Font Sizes**: Adjust cooldown and stack count text.
    *   **Opacity**: Control background visibility.

## Commands

*   `/actionhud` - Prints a detailed debug dump of the current button states to the chat/error frame (useful for troubleshooting missing glows or wrong spells).

## Installation

1.  Place the `ActionHud` folder into your `World of Warcraft/Interfact/AddOns/` directory.
2.  Reload the game.

## Performance

ActionHud is designed with a "zero-overhead" philosophy:
*   **Event-Driven**: No expensive `OnUpdate` polling loops during combat.
*   **Reusable Frames**: All buttons are created once on load and updated only when necessary.
*   **Memory Efficient**: Minimal closures and table churn.

---
*Created for the Agents of the Future.*

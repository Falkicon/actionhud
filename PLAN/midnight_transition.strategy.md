# Midnight "Royal" Transition Strategy

This document outlines the architecture for maintaining ActionHud stability during the World of Warcraft 12.0 (Midnight) expansion transition, specifically targeting the "Royal" API changes introduced in Beta 5/PTR.

## 1. Architectural Principles

To support both Retail (11.x) and Midnight (12.x) with a single codebase, ActionHud uses a **Capability-Based Pattern**.

- **Feature Detection**: Instead of checking game versions, we check for the existence of specific objects (e.g., `SecondsFormatter`) or the absence of deprecated APIs (e.g., `C_UnitAuras.GetAuraDurationRemaining`).
- **Graceful Degradation**: If the environment is "Royal" but the necessary interpretive APIs are not yet fully implemented in ActionHud, the affected modules enter a **Standby State**.
- **Defensive Styling**: When styling native Blizzard frames in a Royal environment, we prioritize **Visual Alpha (0)** over **Hiding** to prevent cascading combat crashes.

## 2. API Mapping Table

| Feature | Legacy API (Retail 11.x) | Royal API (Midnight 12.x) | ActionHud Wrapper |
|---------|-------------------------|--------------------------|-------------------|
| **Aura Duration** | `C_UnitAuras.GetAuraDurationRemaining` | `Duration` Object from Aura Data | `Utils.GetDurationSafe` |
| **Time Formatting** | `string.format("%.1f", s)` | `SecondsFormatter:Format(s)` | `Utils.FormatTime` |
| **Combat Hiding** | `frame:Hide()` | `frame:SetAlpha(0)` | `Utils.HideSafe` |
| **Absorbs** | `UnitGetTotalAbsorbs` | `UnitHealPredictionCalculator` | `UnitFrames (Pending)` |
| **Boolean Colors** | Local Color Tables | `C_CurveUtil.EvaluateColorFromBoolean` | `Utils.Cap.HasBooleanColor` |

## 3. Implementation Status (Standby Mode)

Due to the fundamental shift in how time and aura data are handled in Beta 5+, the following modules are in **Standby** on Royal clients:

- **Tracked Bars**
- **Tracked Buffs**
- **External Defensives**
- **Unit Frame Styling**

### Criteria for "Active" State
A module moves from Standby to Active when:
1. `Utils.Cap.IsRoyal` is true.
2. The `Utils.FormatTime` and `Utils.GetDurationSafe` wrappers are verified to handle `Duration` objects correctly without tainting Blizzard's secure paths.
3. Combat stability is verified using the `/ah testapi` diagnostic tool.

## 4. Diagnostic Workflow

Addon developers and testers should use the following command to track API readiness:

```bash
/ah testapi
```

This command reports:
- **Build Info**: Confirms if the client is Retail, PTR, or Beta.
- **Capabilities**: Shows exactly which Royal APIs are detected.
- **Readiness Score**: A heuristic value indicating how much of the Royal transition is implemented.

## 5. Roadmap

1.  **Phase 1 (Discovery)**: Implement `Utils.Cap` and Standby guards. (COMPLETE)
2.  **Phase 2 (Diagnostics)**: Enhance `/ah testapi` for daily build tracking. (COMPLETE)
3.  **Phase 3 (Version Detection)**: Refine threshold (120000) for PTR/Beta detection. (COMPLETE)
4.  **Phase 4 (Safety Guards)**: Implement `pcall` and `SafeLTE` for secret value comparison. (COMPLETE)
5.  **Phase 5 (Duration Wrapping)**: Update `Utils.GetDurationSafe` to fully support `Duration` object methods (`EvaluateRemainingDuration`). (PENDING)
6.  **Phase 6 (Royal Styling)**: Restore styling to Tracked Abilities using `C_Timer.After(0)` and `SetAlpha(0)` exclusively. (PENDING)
7.  **Phase 7 (Absorb Transition)**: Migrate UnitFrames to `UnitHealPredictionCalculator`. (PENDING)


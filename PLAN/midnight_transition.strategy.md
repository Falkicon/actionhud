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
| **Aura Duration** | `C_UnitAuras.GetAuraDurationRemaining` | `Duration` Object + `EvaluateRemainingDuration` | `Utils.GetDurationSafe` |
| **Time Formatting** | `string.format("%.1f", s)` | `SecondsFormatter:Format(s)` | `Utils.FormatTime` |
| **StatusBar Timer** | `frame:SetValue(val)` | `frame:SetTimerDuration(dur, interp, dir)` | `Utils.SetTimerSafe` |
| **Absorbs** | `UnitGetTotalAbsorbs` | `UnitHealPredictionCalculator` | `UnitFrames (Pending)` |
| **Boolean Colors** | Local Color Tables | `C_CurveUtil.EvaluateColorFromBoolean` | `Utils.Cap.HasBooleanColor` |
| **Secrecy Detection**| `issecretvalue(val)` | `C_Secrets.ShouldUnitComparisonBeSecret` | `Utils.IsSecretSafe` |
| **Class Resources** | Secret Returns | **Non-Secret** (Safe to Read) | `Resources (Restore)` |

## 3. Implementation Status (Phase 7 - Complete)

The transition to the "Royal" interpretive API model is now complete. All modules have been removed from Standby and are now fully functional on Midnight Beta/PTR using the new native wrappers.

| Module | Status | Transition Method |
|---|---|---|
| **Tracked Bars** | ✅ Active | Async Styling + `SetTimerDuration` support |
| **Tracked Buffs** | ✅ Active | Async Styling + `SetAlpha(0)` Stripping |
| **External Defensives**| ✅ Active | Async Styling |
| **Unit Frames** | ✅ Active | `UnitHealPredictionCalculator` integrated |
| **Action Bars** | ✅ Active | `GetActionDisplayCount` + `SetCooldownFromDurationObject` |

## 4. Diagnostic Workflow

Addon developers and testers should use the following command to track API readiness:

```bash
/ah testapi
```

This command reports:
- **Build Info**: Confirms if the client is Retail, PTR, or Beta.
- **Capabilities**: Shows exactly which Royal APIs are detected.
- **Readiness Score**: A heuristic value indicating how much of the Royal transition is implemented.

## 5. Roadmap (Complete)

1.  **Phase 1 (Discovery)**: Implement `Utils.Cap` and Standby guards. ✅
2.  **Phase 2 (Diagnostics)**: Enhance `/ah testapi` for daily build tracking. ✅
3.  **Phase 3 (Version Detection)**: Refine threshold (120000) for PTR/Beta detection. ✅
4.  **Phase 4 (Safety Guards)**: Implement `pcall` and `SafeLTE` for secret value comparison. ✅
5.  **Phase 5 (Duration & Resource Migration)**: ✅
    - Restore Class Resource bars (confirmed non-secret).
    - Implement `Utils.GetActionDisplayCountSafe`.
6.  **Phase 6 (Royal Styling)**: ✅
    - Restore styling to Tracked Abilities using Async Styling (`C_Timer.After(0)`).
    - Integrated `Utils.SetCooldownSafe` for native Duration object support.
7.  **Phase 7 (Absorb Transition)**: ✅
    - Migrate UnitFrames to `UnitHealPredictionCalculator`.
    - Restore Unit Frame styling on Royal.


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
| **Absorbs** | `UnitGetTotalAbsorbs` | `UnitHealPredictionCalculator` | `UnitFrames` (Integrated) |
| **Boolean Colors** | Local Color Tables | `C_CurveUtil.EvaluateColorFromBoolean` | `Utils.Cap.HasBooleanColor` |
| **Secrecy Detection**| `issecretvalue(val)` | `C_Secrets.GetSpellAuraSecrecy` | `Utils.IsValueSecret` |
| **Class Resources** | Secret Returns | **Non-Secret** (Interpretive fragments) | `Resources` (Fractional) |

## 3. Post-Transition Reference

The transition to the "Royal" interpretive API model is complete. ActionHud now operates in a fully hybrid mode, using native interpretive objects where available.

### Diagnostic Workflow
Tester command to verify ongoing environment stability:
```bash
/ah testapi
```

### Ongoing Maintenance
- **Capability Updates**: As Blizzard rolls out the `C_Secrets` namespace, update `Utils.IsValueSecret` to prefer native secrecy queries over `pcall` tests.
- **Whitelist Monitoring**: Monitor GCD and Skyriding vigor spell IDs for any changes in secrecy status.
- **Interpretive Absorb Tuning**: Fine-tune `UnitHealPredictionCalculator` values as new encounter mechanics are added to Beta.

## 4. Feature Roadmap: Central HUD Absorbs

While Unit Frame styling is integrated, the custom central HUD (`Resources.lua`) requires a manual implementation of the absorb/prediction overlay system using the interpretive model.

### Next Steps: `Resources` Module Integration
1. **Calculator Lifecycle**: Initialize a `UnitHealPredictionCalculator` in `Resources:OnEnable` and cache it in the module scope.
2. **Overlay Bars**: 
   - Create `playerAbsorb` and `targetAbsorb` StatusBar overlays for both Player and Target health bars.
   - Use `FLAT_BAR_TEXTURE` with high transparency (e.g., alpha 0.4) and specialized coloring (Teal for absorbs, Green for heals).
3. **Update Logic**:
   - Register `UNIT_HEAL_PREDICTION` and `UNIT_ABSORB_AMOUNT_CHANGED` events.
   - Use `Utils.GetUnitHealsSafe(unit, calculator)` to retrieve data from the appropriate model (Legacy vs. Royal).
   - **Interpretive Constraint**: On Royal clients, ensure the absorb bar is anchored to the *end* of the current health bar value without direct math on secret health totals (using Blizzard's native interpretive anchoring logic if possible).
4. **Settings**: Add toggles in `SettingsUI.lua` for "Show Absorbs on HUD" and "Show Heal Prediction on HUD."


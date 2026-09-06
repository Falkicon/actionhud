# Blizzard API changes and ActionHud opportunities

Research date: 2026-09-05. Scope: changes after the 12.0.0 API baseline through released 12.1.0, plus older supported APIs ActionHud could use better. This is a research assessment, not an implementation or in-game compatibility certification.

## Evidence and version scope

I reviewed Blizzard's public update announcements and compared Blizzard-authored generated API documentation and UI source distributed with the client. The detailed source is accessed through the **community-maintained Gethe mirror**, not a Blizzard-operated GitHub repository. Recommendations below distinguish source-supported capabilities from proposed ActionHud integrations.

The pinned current snapshot is [12.1.0 build 69587](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/version.txt), mirror commit `8ea15b61e45c0ed4eba01439c90757f86eb78d34`, dated September 1, 2026. Compared patch-tag snapshots report:

| Tag | Snapshot version |
| --- | --- |
| 12.0.0 | 12.0.0.65614 |
| 12.0.1 | 12.0.1.66220 |
| 12.0.5 | 12.0.5.67602 |
| 12.0.7 | 12.0.7.68887 |
| 12.1.0 | 12.1.0.69587 |

These are sampled builds, not every hotfix. A capability first observed in a later snapshot may have been hotfixed earlier. PTR-only announcements are not treated as shipped features. Forum/Discord reposts and community indexes were discovery aids; technical conclusions below use the actual shipped definitions and implementation.

Blizzard's [12.0.5 update notes](https://worldofwarcraft.blizzard.com/en-us/news/24271855/1205-content-update-notes), [Revelations notes](https://news.blizzard.com/en-us/article/24244888/revelations-content-update-notes), and [12.1 UI announcement](https://news.blizzard.com/en-us/article/24294064/keep-track-of-potions-trinkets-and-more-with-new-user-interface-updates) provide release context. General UI improvements do not, by themselves, prove an addon-callable API exists.

## Highest-value findings

### 1. Revisit tracked buffs and defensives using 12.1 aura containers

**New capability:** Blizzard ships custom aura containers with declarative groups, individual slots, sorting, and candidate filters. Spell-ID inclusion/exclusion is expressly supported for helpful auras on assistable units and harmful auras on non-assistable units. This supports a prototype for selected player buffs and active defensive effects. [Custom container source](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua)

Custom aura buttons provide presentation methods for icons, cooldowns, duration text/bars, stack counts, dispel indications, and pandemic visuals. Blizzard handles the protected aura data internally. [Custom button source](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua)

**ActionHud recommendation:** build a new small runtime module instead of enabling the old `Cooldowns/TrackedBuffs.lua` or `TrackedDefensives.lua`. Start with selected player buffs/defensives in a fixed slot grid. An ordinary wrapper supplies a configured footprint to LayoutManager; the native aura container manages its contents inside that wrapper.

**Architecture constraint:** native aura layout can be secret, and the implementation deliberately restricts size-change observation. Do not derive HUD stack height from active aura count, inspect restricted visibility, or use `OnSizeChanged` to infer activity. Reserve configured space or keep the new module independently positioned. [Container implementation](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua), [container layout and restrictions](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerShared.lua)

This changes the old conclusion from “no supported buff display” to “a native-owned display is worth prototyping.” It does not authorize arbitrary aura analysis or enemy defensive cooldown inference.

### 2. Keep dormant aura scanning disabled: 12.1 tightened access

Current index/instance-based APIs such as `GetUnitAuras`, `GetAuraDataByAuraInstanceID`, and `GetAuraDuration` carry `RequiresUnitAuraAccess`. The documented failure mode is an error when callers lack access. Spell-ID/name queries carry `RequiresNonSecretAura`; they can return no values for a protected aura. Merely knowing a spell ID does not grant access. [Aura API definitions](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua), [restriction predicates](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua)

**ActionHud impact:** the dormant discovery loops and cached aura-instance assumptions are not a foundation for a 12.1 revival. Returning `nil` or catching an error should not be interpreted as proof that a buff is absent. Keep historical API research clearly dated and treat the new container route separately.

### 3. Add native countdown formatting and simplify GCD handling

**12.0.5 additions observed in the source comparison:** `Cooldown:SetCountdownMillisecondsThreshold` and `SetCountdownFormatter` provide decimal countdowns and configurable native formatting. `C_StringUtil` gained formatter constructors. [Cooldown API](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua), [formatter factories](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/StringUtilDocumentation.lua)

The action/spell cooldown-duration getters also gained `ignoreGCD`. This offers an explicit way to request the real cooldown independently of a global-cooldown sweep. [Action-bar API](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua)

**ActionHud recommendation:** add a setting such as decimal countdowns below three seconds and consider an optional GCD display policy. `ActionBars.lua` already uses native duration objects; its getter call currently supplies only the action ID. Preserve charge and loss-of-control precedence while introducing an explicit GCD choice. A nil/non-nil duration object alone is not a reliable active-charge test; retain explicit state and zero-duration clearing behavior.

This is a smaller, more immediately shippable improvement than aura-container integration.

### 4. Use native duration-to-text bindings for new displays

**12.0.7:** `C_DurationUtil.CreateDurationTextBinding` and its binding object provide automatic duration text updates with a selectable interval. **12.1:** bindings gained additional formatting and text-color curve support. [Duration factory](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/DurationUtilDocumentation.lua), [binding contract](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/DurationTextBindingObjectAPIDocumentation.lua)

**ActionHud recommendation:** use these when adding buff timers or standalone duration labels. Configure formatting and color policies once, then let the native binding update text. Do not introduce an addon timer that reads protected remaining seconds to format, compare, or recolor text. This is an implementation simplification; no performance gain is claimed without measuring it.

Existing action cooldown widgets already update their own countdowns, so replacing them wholesale is unnecessary.

### 5. Expand resource presentation using supported power and percentage APIs

**New since the baseline:** `UnitHasPowerType` appears in 12.0.5 and returns a bool without a secret-return predicate. It is a better basis for determining whether a unit uses a resource than interpreting a protected maximum as “resource exists.” [Unit API](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)

**Older but underused capability:** `UnitHealthPercent` and `UnitPowerPercent`, including optional curves, are already present in the 12.0.0 snapshot. They should not be advertised as newly added in 12.1. Their results may remain secret, but native font strings accept protected formatted text. [Unit API](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua), [FontString API](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua)

**ActionHud opportunities:**

- Restore optional health/power percentage text, currently deliberately hidden in `UnitFrames/Rendering.lua:239` and `:256`. Use a native curve for scaling and a supported font-string setter; never perform arithmetic on the result in Lua.
- Replace the Resources fallback that assumes five full class-resource pips when values are protected (`Resources.lua:216` and `:343`). Prototype native curve-based segment fills using public class/spec configuration for geometry. Verify each class's actual resource scale; `UnitHasPowerType` alone does not reveal the maximum or solve fractional resources.

Both require native combat testing. Percentage text is the smaller prototype; class-resource pips are the broader correctness project.

### 6. Correct and strengthen heal-prediction integration

The 12.0.1 calculator snapshot adds current/maximum health, percentage evaluation, and total incoming-heal/absorb getters. Current documentation distinguishes `GetTotalDamageAbsorbs` (raw total) from `GetDamageAbsorbs` (display amount with configured clamping). [Calculator contract](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitHealPredictionCalculatorAPIDocumentation.lua)

**Concrete mismatch found:** `Utils.GetUnitHealsSafe` at `Utils.lua:585` checks `GetTotalAbsorbs`, which is not a documented calculator method in the inspected versions. A successful calculator call consequently supplies zero as its absorb result. `Resources.lua` independently reads `UnitGetTotalAbsorbs`, so the fallback masks this in the current HUD; this is not evidence that all shields are missing.

**Recommendation:** correct the wrapper to use the documented total getter, with a test fixture that exposes only documented methods. Separately evaluate using the calculator in custom UnitFrames, whose prediction path currently hides predictions when it cannot do ordinary arithmetic.

### 7. Consider consumables and native pings after the core work

Blizzard officially added Cooldown Manager support for trinkets, potions, and racial cooldowns/durations in 12.1, plus action-bar/Cooldown Manager spell-status pings and unit-frame health/mana pings. [Blizzard UI announcement](https://news.blizzard.com/en-us/article/24294064/keep-track-of-potions-trinkets-and-more-with-new-user-interface-updates)

The shipped cooldown-viewer metadata now includes optional equipment slots, buff slots, and spell categories; `spellID` is optional. The existing public category/info getters predate 12.1. [CooldownViewer API](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/CooldownViewerDocumentation.lua)

**ActionHud opportunity:** a compact consumables row or a replacement cooldown-viewer integration could complement `Trinkets.lua`. New metadata must be handled as multiple entry types rather than assuming every entry is a spell. A native ping integration is a separate prototype: today's action mirrors intentionally ignore mouse input, so adding interaction needs a deliberate input design.

I did not find a generic `C_Item.GetItemCooldownDuration` in the inspected current item API. Do not plan a migration around that presumed function. `C_Item.GetItemCooldown` remains a numeric start/duration API without a secret-return annotation. [Item API](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua)

## Compatibility and tooling priorities

- Preserve the duration-object route in active ActionBars. Native `SetCooldown` is not a general-purpose protected-number sink for addon callers. Audit the defensive secret-value branch in `Trinkets:UpdateCooldowns` before extending it; the existence of that branch does not prove ordinary item cooldowns are currently broken. [Cooldown API](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua)
- Audit restrictions as well as names and signatures. The generated `Predicates` documentation makes clear that some calls can return secrets, some return nothing, and some are denied entirely. Extend contract fixtures to cover these distinct outcomes. [Predicates](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua)
- Refresh the reference snapshots used for development. The existing local “live” UI dump reports **11.2.7.64978** and “beta” reports **12.0.1.64914**. They are unsuitable as current 12.1 references. This research downloaded selected pinned files into ignored `_test_/api-review/`; it did not replace those shared source directories.
- Keep a build-pinned manifest of the small set of Blizzard APIs ActionHud depends on. Compare signatures, return-field optionality, restriction predicates, and native method names when updating it. Offline tests still cannot certify WoW taint behavior.

## Suggested implementation order

1. Fix the calculator getter mismatch and add its missing contract test; finish validating the already-pending target-health range correction separately.
2. Add native decimal countdown formatting and an explicit GCD policy.
3. Prototype optional percentage text, then accurate class-resource display.
4. Build an isolated fixed-footprint player buff/defensive prototype with 12.1 aura containers.
5. Evaluate consumables/pings only after confirming their value alongside ActionHud's display-only action mirrors.

The initial research pass changed no runtime code. Implementation progress is recorded below; no dormant module has been enabled.

## Implementation progress

### Step 1: native heal-calculator absorbs

- Corrected `Utils.GetUnitHealsSafe` to call `GetTotalDamageAbsorbs` and preserve its result unchanged for native display.
- Added a calculator contract regression covering opaque heal/absorb passthrough, nil normalization, the native clamping flag, and fallback behavior. The absorb assertion failed before the correction and passed afterward.
- Offline validation: all 15 Lua suites and 7 Python tests pass; active runtime lint has zero warnings/errors. Native combat validation remains pending.
- In-game check after installing this checkout: with heal prediction and absorb displays enabled, apply a shield, take damage, and receive a cast-time heal. Check shield consumption/expiration and prediction clearing on completion, cancellation, and target changes, both outside combat and in an instance. Look for stuck overlays and Lua errors. The existing direct-absorb fallback means a dramatic visual difference is not expected.
- Separately validate the pending target-health range correction: a damaged target should show a proportional bar through intermediate health values, including in instanced combat.

The user reported improved bars and no errors, but subsequently confirmed that the test may have used the earlier installed version. This is not counted as validation of the new fixes. Step 1 is being merged into the installed local-main checkout for a confirmed reload and test.

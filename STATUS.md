# ActionHud Development Status

**Last updated:** 2026-09-18

This page records implementation and validation for version 2.14.1. [ActionHud.toc](ActionHud.toc) declares Retail 12.1 (`120100`) and WoW: Forever 1.60.1 (`16001`, Retail API); release changes are listed in [CHANGELOG.md](CHANGELOG.md). Offline checks, the reported Warrior smoke tests, and Forever load testing passed. Broader class/spec and combat checks remain listed below.

## Active Runtime

| Component | Implemented behavior |
| --- | --- |
| ActionHud core | Initialization, profiles, slash commands, settings access, root positioning, and Addon Compartment entry |
| ActionBars | Edit Mode mirroring of Bars 1 and 2, page changes, cooldowns, counts, usability, range, and proc/assist feedback |
| Resources | Player/target health and power, plus player class resources |
| UnitFrames | Optional custom secure frames for Player, Target, Target of Target, and Focus |
| Trinkets | Equipped on-use trinket display and cooldowns |
| Consumables | Optional fixed-slot item count/cooldown display with bag picker and manual IDs; disabled by default |
| PlayerBuffs | Optional native helpful-aura display, with Recent Buffs discovery and Blizzard Catalog selection; display disabled by default |
| LayoutManager | Queued lifecycle reconciliation, stack measurement, positioning, and rendering with combat deferral |
| Performance | Optional call counts and total/average/peak timings through `/ah perf` and Mechanic integration |

Custom unit frames are disabled by default. They support value text and optional native health/power percentages, which default to off. PlayerBuffs is also disabled by default; it uses a fixed public footprint for up to 12 selected `HELPFUL` player aura IDs and can be independent or part of the HUD stack. Runtime source responsibilities and load order are mapped in [README.md](README.md#development) and [Runtime lifecycle and layout](docs/runtime-layout.md).

## Recent Improvements

- Fixed disabled modules reappearing, event/hook cleanup, duplicate action-slot updates, restricted-value prediction guards, and stale geometry/position state.
- Centralized layout scheduling and established desired, active, and pending module state.
- Extracted shared defaults and split UnitFrames into identity, lifecycle, layout, and rendering files.
- Added a full-TOC integration host, repository validators, standalone lint configuration, and CI checks.
- Added opt-in profiling and lazy debug-log formatting. No in-game speedup is claimed without measurements.
- Corrected protected resource ranges and native absorb prediction; added decimal countdown/GCD controls, optional native unit-frame percentages, and the optional native PlayerBuffs display. See the [API upgrade progress](docs/blizzard-api-review-2026-09.md#implementation-progress) for test notes.

See the [quality review](docs/quality-review.md) for individual findings and [Performance profiling](docs/performance.md) for measurement guidance.

## Offline Verification

The implementation pass on 2026-09-06 completed:

- All 27 standalone Lua suites and seven Python validator tests passed with `lupa==2.8`.
- First-party Lua compilation and TOC/XML, localization, and package checks passed.
- Luacheck 1.2.0 reported zero warnings/errors across 30 active first-party Lua files.
- Git whitespace checks passed.

These are results for the development worktree, not certification of live-client behavior. The host does not model native taint, secret values, or rendering. Repeat the commands in [CONTRIBUTING.md](CONTRIBUTING.md#local-checks) after runtime changes.

## Pending Validation and Follow-Up

- The user confirmed Consumables icons and carried counts appear and reported that the subsequent drag-overlay fix looks good. Item-use cooldown behavior remains pending live validation.
- Consumables: after `/reload`, open **Consumables**, add a carried potion or healthstone from the bag picker, and enable the module. Verify count/charges and cooldown after using it through the normal game binding, including shared potion cooldowns and instanced combat. Depleted items should stay in place with zero count. Check reordering, resizing, dragging, stack inclusion, and profile switching; settings changes during combat must apply after combat. These scenarios still need live validation.
- The user confirmed the corrected Blizzard Catalog is working well on Warrior after the filter fix was merged to local main (`d47915d`). The catalog uses tracked-aura categories and player-aura eligibility without requiring `hasAura = true`. This records a successful catalog smoke test; individual buff matching and other classes/specs still need confirmation.
- Validate Recent Buffs after `/reload`: cast a helpful buff outside combat, then open Player Buffs and find it in the default source. Add it, switch to Blizzard Catalog, and check search, tooltips, pagination, Add/Added state, and selected controls. Recent discovery must pause when restricted, keep the existing history visible, and resume when access is available. It may miss buffs that expire while restricted.
- Check that recent history survives `/reload` and profile changes on the same character. Clear History must leave selected buffs intact. Verify catalog selections with linked aura IDs display correctly in combat, and that spec/metadata changes update candidate filters after combat without Lua errors.
- Rallying Cry did not appear when selected from the spellbook. Its cast ID now resolves to the buff ID, including existing selections; after `/reload`, cast it and confirm the icon/countdown appears and disappears when the buff ends. This fix still needs in-game validation.

- Verify stance/form changes, spell overrides, duplicate slots, range feedback, and charge cooldowns in-game.
- Exercise profile changes, module toggles, stack inclusion, scaled dragging, and combat-interrupted dragging.
- Verify secure unit-frame geometry, restricted health/heal prediction, and maximum-health updates in instanced combat.
- PlayerBuffs smoke test: the user confirmed that a manually configured Spell Reflection entry shows the native icon and countdown. Expiration behavior, early removal when a reflection is consumed, instanced-combat behavior, and geometry remain pending.
- Validate PlayerBuffs in-game: `/reload`, open **Player Buffs**, search for Spell Reflection, add it, enable the module, and confirm the countdown expires normally or ends early when a reflection is consumed, and inactive configured slots remain reserved. Change icon size, columns, spacing, and independent position. Include the module in the HUD stack and confirm buffs appearing or expiring do not shift other stack modules; toggling stack inclusion should update the stack layout as expected. Repeat the enable/configuration flow during combat and check for Lua errors. These detailed combat and lifecycle cases remain pending beyond the reported icon/countdown smoke test.
- Collect comparable performance recordings before claiming performance gains.
- Align legacy in-game debug help and position diagnostics with the implemented slash commands and current profile keys. The top-level command documentation reflects `SlashHandler`; legacy `debug`, `record`, and `clear` subcommands are not implemented.

The [in-game checklist](docs/quality-review.md#required-in-game-validation) provides the detailed scenarios. Merging the development changes does not complete live-client validation; reload the development build before testing.

## Dormant Modules

| Source | State |
| --- | --- |
| Essential/Utility Cooldown Manager | Retained experiment while native cooldown-viewer APIs are under review |
| TrackedBuffs | Retained aura/icon styling experiment |
| TrackedDefensives | Retained experiment affected by aura API restrictions |
| DefensiveTracker | Retained test/reference implementation |

All of `Cooldowns/` and its corresponding settings files are excluded from the active TOC and release package. Legacy core experiments are also excluded. Their presence in source or profile defaults does not make them active features.

[Aura API testing](docs/aura-api-testing.md) and [Skinning patterns](docs/skinning-patterns.md) preserve the historical WoW 12.0 research. Revalidate against the target build before using those findings to re-enable modules; update the TOC, package exclusions, and tests together.

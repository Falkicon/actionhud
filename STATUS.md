# ActionHud Development Status

**Last updated:** 2026-09-05

This page describes the current development worktree. [ActionHud.toc](ActionHud.toc) declares Retail 12.1 (`120100`) and version 2.13.7; subsequent changes are listed under [Unreleased](CHANGELOG.md#unreleased). The recent review and architecture changes have passed offline checks and still need in-game combat validation.

## Active Runtime

| Component | Implemented behavior |
| --- | --- |
| ActionHud core | Initialization, profiles, slash commands, settings access, root positioning, and Addon Compartment entry |
| ActionBars | Edit Mode mirroring of Bars 1 and 2, page changes, cooldowns, counts, usability, range, and proc/assist feedback |
| Resources | Player/target health and power, plus player class resources |
| UnitFrames | Optional custom secure frames for Player, Target, Target of Target, and Focus |
| Trinkets | Equipped on-use trinket display and cooldowns |
| LayoutManager | Queued lifecycle reconciliation, stack measurement, positioning, and rendering with combat deferral |
| Performance | Optional call counts and total/average/peak timings through `/ah perf` and Mechanic integration |

Custom unit frames are disabled by default. They support value text, while percentage text remains disabled. Runtime source responsibilities and load order are mapped in [README.md](README.md#development) and [Runtime lifecycle and layout](docs/runtime-layout.md).

## Recent Improvements

- Fixed disabled modules reappearing, event/hook cleanup, duplicate action-slot updates, restricted-value prediction guards, and stale geometry/position state.
- Centralized layout scheduling and established desired, active, and pending module state.
- Extracted shared defaults and split UnitFrames into identity, lifecycle, layout, and rendering files.
- Added a full-TOC integration host, repository validators, standalone lint configuration, and CI checks.
- Added opt-in profiling and lazy debug-log formatting. No in-game speedup is claimed without measurements.

See the [quality review](docs/quality-review.md) for individual findings and [Performance profiling](docs/performance.md) for measurement guidance.

## Offline Verification

The implementation pass on 2026-09-05 completed:

- All 14 standalone Lua suites and seven Python validator tests passed with `lupa==2.8`.
- First-party Lua compilation and TOC/XML, localization, and package checks passed.
- Luacheck 1.2.0 reported zero warnings/errors across 22 active first-party Lua files.
- Git whitespace checks passed.

These are results for the development worktree, not certification of live-client behavior. The host does not model native taint, secret values, or rendering. Repeat the commands in [CONTRIBUTING.md](CONTRIBUTING.md#local-checks) after runtime changes.

## Pending Validation and Follow-Up

- Install the worktree for testing and verify stance/form changes, spell overrides, duplicate slots, range feedback, and charge cooldowns in-game.
- Exercise profile changes, module toggles, stack inclusion, scaled dragging, and combat-interrupted dragging.
- Verify secure unit-frame geometry, restricted health/heal prediction, and maximum-health updates in instanced combat.
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

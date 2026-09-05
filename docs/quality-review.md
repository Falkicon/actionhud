# Repository quality review — 2026-09-05

The main problems were inconsistent module lifecycle handling, duplicated positioning logic, stale layout caches, and settings that no longer matched the runtime. Focused fixes preserve the current module architecture and dormant cooldown-viewer boundary.

## Fixed findings

| Priority | Finding and impact | Resolution |
| --- | --- | --- |
| P1 | Resource heal prediction checked current health and incoming heals before arithmetic, but not maximum health. A restricted maximum could reach `math.min`. | Check all operands; use the existing anchored prediction fallback when maximum health is restricted. |
| P1 | Unit-frame settings could mutate secure layout during combat; computed heights were cached even when secure resizing was skipped. | Defer layout changes and retry after combat. Record the applied height only after resizing succeeds. |
| P2 | Disabled resources could reappear during layout; disabled action bars were also shown by `ApplyLayoutPosition`. | Clear resource runtime state and height reservations; guard action-bar positioning and layout by enabled state. |
| P2 | Re-enabling action bars installed repeated permanent Edit Mode hooks. Old callbacks could run after disable/re-enable; trinkets lacked disable cleanup. | Install one hook, reject callbacks from earlier enable cycles, unregister events, and hide disabled containers. |
| P2 | Action Bars enable state was not saved; enabling trinkets through settings could leave their contents undiscovered. | Persist `actionBarsEnabled` and apply module lifecycle transitions through `ApplyEnabledState`. Discover trinkets immediately on enable. |
| P2 | One action slot can appear on both mirrored bars, but its lookup stored only one button. Range, usability, and assist updates missed the other. | Index every button for a slot and update all mirrors. Empty slots now clear both cooldown displays. |
| P2 | A stale unit-event registration callback could clear the scheduling flag belonging to a newer callback. | Reject stale generations before changing scheduling state. |
| P2 | Resource width differed between measurement and positioning; excluded modules retained stack dimensions; independent resource anchors could remain attached to the stack. | Use one width calculation, rebuild active height reservations, and apply independent positioning explicitly. |
| P2 | HUD dragging saved offsets for an arbitrary anchor but restored them relative to center. Profile changes did not restore the root position. Action bars duplicated drag code outside the container registry. | Save scale-correct center offsets, restore profile position, share registered drag behavior, and defer combat-interrupted drag completion. |
| P2 | Maximum-health changes did not refresh resource ranges. Unit-frame prediction could show a stale value when current health became restricted. | Handle scoped `UNIT_MAXHEALTH` events and hide predictions that cannot be refreshed. |
| P2 | Settings reset to coordinates that differed from profile defaults. Layout movement could stop at hidden modules and notify the wrong AceConfig registration. | Read reset coordinates from AceDB defaults, move across hidden entries, and notify `ActionHud_Layout`. |
| P2 | Mechanic buttons used obsolete settings navigation and layout-only toggles; active help advertised dormant functionality. | Use the addon's settings/lifecycle helpers, remove the dormant toggle and instructions, and localize changed panel labels. |
| P2 | Packaging contradicted the documented exclusion of dormant cooldown modules. | Exclude dormant runtime/settings, legacy core experiments, tests, and development documentation. Retain source in the repository. |

## Architecture and maintainability follow-ups — implemented

- **Integration coverage:** a deterministic host loads the full TOC with real embedded Ace libraries. Tests cover normal, disabled, and combat startup; profile changes/copy/reset; event cleanup; frame reuse; and queued geometry.
- **Layout ownership:** LayoutManager now coalesces requests, reconciles lifecycle changes, prepares content, measures the stack, positions modules, and renders. Module timers and ActionBars' same-frame throttle were removed. A ten-change settings burst is covered by an integration assertion that exactly one layout pass runs.
- **Module lifecycle contract:** all four runtime modules expose desired, active, and pending state and use the same layout scheduler for combat deferral. Ace enablement and feature enablement remain distinct and documented in [Runtime lifecycle and layout](runtime-layout.md).
- **Large source files:** defaults now live in `Core/Defaults.lua`. UnitFrames is separated into identity, lifecycle, layout, and rendering files, with explicit TOC load order. Earlier duplicate default entries were removed without changing their effective values.
- **Quality automation:** standalone Luacheck 1.2.0 uses explicit WoW globals. CI and local commands check active Lua, localization keys, manifests, and package exclusions. Python tests exercise validator failure paths.
- **Performance evidence:** opt-in counters now report calls, cumulative time, average time, and peak cost; inactive logging avoids formatting at hot call sites. See [Performance profiling](performance.md). No in-game speedup or allocation improvement is claimed without measurements.

## Verification

- Baseline: all five original standalone test files passed.
- Final after follow-up: all 14 standalone Lua test files and seven Python validator tests pass with `lupa==2.8`.
- The runner discovers `Tests/test_*.lua`, uses Lua 5.1 explicitly, compiles first-party Lua, skips development environments, and works when invoked outside the addon directory.
- TOC/XML dependency validation and automated package-exclusion closure pass, including the newly extracted runtime files.
- Luacheck 1.2.0 reports zero warnings/errors across all 22 active first-party Lua files.
- `git diff --check` passes.
- README, CONTRIBUTING, and STATUS now describe the actual active modules and dependencies.

Review coverage includes active first-party runtime, settings, localization, tests, manifests, and development documentation. Dormant code was checked for load/package separation and syntax. Vendored libraries were inspected where their contracts mattered, not comprehensively audited or upgraded.

## Required in-game validation

Offline verification was performed in the review worktree. After merging or installing the development build and reloading it in-game:

1. Reload and verify enable/disable persistence for Action Bars and Trinkets, both from settings and Mechanic tools. Toggle resources and individual resource bars; switch stack inclusion and reset positions.
2. Test Druid form changes, Rogue stealth, action-page changes, proc overrides, shared slots, range colors, assist glows, and empty charge-cooldown slots.
3. Test root and independent dragging with UI scale changes, profile switching, and entering combat mid-drag. Confirm positioning and deferred changes after combat.
4. With custom unit frames enabled, change power layout during combat, leave combat, and verify frame heights. Exercise restricted health/heal prediction and maximum-health changes in instanced combat.

Standalone mocks cannot validate WoW taint, native secret-value behavior, or secure-frame restrictions. Combat validation remains required for the protected-value and secure-layout changes. Mechanic output must be read only after the tester confirms reload, per the shared agent workflow.

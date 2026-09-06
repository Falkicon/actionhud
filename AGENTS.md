# ActionHud — Agent Documentation

Technical reference for agents modifying this addon. Start with [README.md](README.md) for user behavior and [CONTRIBUTING.md](CONTRIBUTING.md) for checks.

For shared patterns, library references, and development guides, also read the shared `Mechanic/AGENTS.md` when available. It normally lives at `../Mechanic/AGENTS.md` in the development checkout; isolated worktrees may require locating the original Mechanic checkout instead.

## Project Intent

ActionHud is a compact display overlay for Blizzard Action Bars 1 and 2, with resource bars, equipped trinkets, and optional custom secure unit frames. The action icons do not handle clicks. The target interface is declared in [ActionHud.toc](ActionHud.toc): WoW Retail 12.1 (`120100`).

- Edit Mode determines mirrored button counts and rows. This is not a fixed 6×4 grid.
- Action Bar 2 uses action slots 61–72. Internal `bar6` identifiers refer to this bar; user-facing documentation should call it Action Bar 2.
- Stance/form paging uses the current action page and bonus bar offset.
- Cooldown and range updates use native duration objects and opt-in action range events where available.
- Protected values remain opaque passthrough data. Combat testing is required for every protected-API change.

## Midnight Safety Rules

1. Use the safe helpers in `Utils.lua`, such as `GetActionCooldownSafe`, `GetInventoryItemCooldownSafe`, and `GetActionDisplayCountSafe`, instead of calling their underlying APIs directly.
2. Use `Utils.SafeCompare(a, b, op)` for numeric comparisons involving game API values. Before arithmetic, indexing, formatting, or branching on restricted data, validate every operand with the relevant safety helper. A comparison guard does not make a secret value safe for arithmetic.
3. Preserve native cooldown duration/display-value passthrough. Do not extract secret values into ordinary Lua calculations.
4. Run `python Tests/run.py` after runtime changes. Mocks cannot prove native secret-value or taint safety; test the affected path in instanced combat too.
5. Existing `-- @scan-ignore: midnight-*` comments document reviewed boundaries. Do not add one without verifying the call in combat.

## Source Map

The TOC/XML manifests define the runtime. `.pkgmeta` defines package exclusions.

| File | Responsibility |
| --- | --- |
| `ActionHud.lua` | Addon initialization, profile callbacks, root frame, settings access, slash commands, and logging helpers |
| `Core/Defaults.lua` | `ns.defaults`, the single source of profile defaults |
| `Core/Performance.lua` | Optional aggregate timing counters |
| `Core/DraggableContainer.lua` | Registered drag overlays, scale-correct positioning, and combat-interrupted drag handling |
| `Core/UnitEventRouter.lua` | Unit-scoped event subscriptions and deferred registration |
| `Utils.lua` | Protected API wrappers, fonts, and optional-library fallbacks |
| `LayoutManager.lua` | Queued layout scheduler and module stack |
| `ActionBars.lua` | Mirrored buttons, page/slot resolution, cooldowns, usability, range, and glows |
| `Resources.lua` | Player/target health and power, plus player class resources |
| `Trinkets.lua` | Equipped on-use trinket display and cooldowns |
| `UnitFrames/Identity.lua` | Restricted identity normalization, colors, status icon decisions, and value formatting |
| `UnitFrames/UnitFrames.lua` | Ace module creation, lifecycle, events, and layout requests |
| `UnitFrames/Layout.lua` | Custom frame construction, styling, and geometry |
| `UnitFrames/Rendering.lua` | Unit values, prediction, text, icons, and final rendering |
| `Settings/init.lua` | Settings helpers and AceConfig registration |
| Other active files in `Settings/` | Action Bars, Resources, Unit Frames, Trinkets, and Layout options |
| `Locales/enUS.lua` | Base AceLocale strings |
| `Mechanic.lua` | Optional Mechanic tools, diagnostics, and performance rows |
| `Tests/` | Python repository checks, Lua regressions, and full-TOC integration host |

Keep the UnitFrames TOC order: Identity, UnitFrames, Layout, Rendering. The latter files retrieve the existing Ace module; they do not create new modules.

## Layout and Lifecycle Contract

Read [Runtime lifecycle and layout](docs/runtime-layout.md) before changing geometry or enablement.

`LayoutManager:RequestLayout(reason)` is the shared entry point. `TriggerLayoutUpdate()` is a compatibility alias. Requests coalesce into a next-frame callback, use the latest profile, and wait for `PLAYER_REGEN_ENABLED` during combat. Generation checks invalidate callbacks from previous enable cycles.

Each pass reconciles lifecycle state, calls `PrepareLayout()`, measures stack heights/widths into a manager-owned snapshot, sizes and positions the HUD, then calls `RenderLayout()`. Stack modules supply `CalculateHeight()`, `GetLayoutWidth()`, and `ApplyLayoutPosition()`. UnitFrames participates outside the stack as an auxiliary module.

Module `UpdateLayout()` methods only request a pass. Do not add module layout timers, publish height caches directly, call manager passes recursively, or invoke prepare/position/render phases externally. Value events may update existing widgets directly; geometry changes go through the scheduler.

Runtime modules expose:

| Field | Meaning |
| --- | --- |
| `_desiredEnabled` | Latest feature toggle from the profile |
| `_runtimeActive` | Frames and runtime subscriptions have started |
| `_pendingEnabledState` | Lifecycle or secure geometry reconciliation is pending |

`ApplyEnabledState()` records intent and reconciles outside combat. `StartRuntime()` is idempotent; stop paths release event subscriptions and hide frames when allowed. ActionBars and Trinkets use Ace enable/disable; Resources and UnitFrames keep their Ace modules available while their features are off. Use `_runtimeActive` when checking whether a feature is running; Ace `IsEnabled()` alone is insufficient.

Resources, Action Bars, and Trinkets can participate in the HUD stack. Independent positions use the shared draggable-container behavior. Preserve scale-correct center offsets and combat deferral when changing drag or profile code.

## Action Updates

| Function | Responsibility |
| --- | --- |
| `UpdateAction` | Resolve the paged action ID and update the slot's icon |
| `UpdateIcon` | Re-read the spell ID and texture; report icon changes so dependent state can refresh |
| `UpdateCooldown` | Update cooldown/charge displays and GCD versus cooldown styling |
| `UpdateState` | Refresh usability, range, and proc state |
| `UpdateProc` | Re-resolve the spell ID and evaluate its proc glow |
| `RefreshAll` | Recalculate displayed slots after startup or page changes |

Never cache an action's spell ID across events. Proc overrides such as Slam → Heroic Strike can change the backing spell without `ACTIONBAR_SLOT_CHANGED`. `SPELL_UPDATE_ICON` and proc evaluations must resolve the current spell. A slot can appear in both mirrored bars; slot lookups must update every matching button.

Test Druid forms, Rogue stealth, page changes, spell overrides, shared slots, range feedback, and empty cooldown/charge slots when changing action resolution or display logic.

## Custom Unit Frames

`Utils.GetPlayerClassPowerTypeSafe()` is the shared secondary-resource selector for Resources and the custom player frame. It uses public class/spec/form identity and optional `UnitHasPowerType` availability. Never substitute the primary `UnitPowerType` for the secondary pool. HUD segments receive the same native current value with public per-segment ranges; an opaque maximum uses a continuous native bar. Keep current and maximum in matching native units, and create/position segments only during the shared layout pass. Depletion does not remove the row.

The active implementation creates `SecureUnitButtonTemplate` frames for Player, Target, Target of Target, and Focus. Frame creation is deferred until enabled and outside combat; frames are reused across enable cycles. Corresponding Blizzard frames can optionally be hidden and restored.

The current controls are **Enable Custom Unit Frames**, **Hide Blizzard Frames**, and per-frame dimensions, background/border, bars, text, and status icons. Positioning uses **Layout → Unlock Module Positions**. Settings changes request the shared layout pass and defer protected geometry during combat.

Value text and optional health/power percentage text are supported. Percentages default to off and use native percentage APIs with a display-scaling curve, passing results directly to native formatted text. Do not calculate percentages from restricted current/maximum values in Lua. Historical notes about reskinning Blizzard frames, removing portraits, hover-only text, or requiring reload after every setting do not describe this implementation.

## SavedVariables

AceDB manages the saved global `ActionHudDB`. Runtime code reads the selected profile through `ActionHud.db.profile`; the saved global uses AceDB's profile storage (`profiles`, `profileKeys`, etc.), not `ActionHudDB.profile`.

[Core/Defaults.lua](Core/Defaults.lua) defines defaults. Reset controls must read `addon.db.defaults.profile` instead of duplicating coordinates or dimensions. Unit-frame configuration lives in `ufConfig`, keyed by `player`, `target`, `targettarget`, and `focus`.

Some legacy defaults remain for dormant features and compatibility. Their presence does not enable a runtime module. Keep runtime modules separate from `Settings/`, and prefer focused modules over monolithic files.

## Commands and Diagnostics

See [README.md](README.md#slash-commands) for supported user commands and [Performance profiling](docs/performance.md) for measurements.

- `/ah` and `/actionhud` open settings outside combat.
- `/ah reset` resets the current profile.
- `/ah perf on`, `off`, `reset`, and `report` control optional timing counters; `/ah perf` also reports.
- `/ah dump` is a legacy cooldown-manager hook; the active addon reports that the manager is unavailable.
- `/ah pos` or `/ah positions` prints legacy position diagnostics. Some fields use old profile keys, so this is not an authoritative position export.
- `/ah wipe` clears the saved database global and requires reload. It affects all profiles, unlike `reset`.

`debug`, `record`, and `clear` are not implemented slash subcommands, even though legacy in-game help still mentions debug recording.

Profiling defaults to off and works without Mechanic. When disabled, instrumented paths skip clock reads and counter allocation. Timings overlap; do not sum all metrics as total addon CPU usage.

Debug logging requires `profile.debugDiscovery` and an active MechanicLib sink. The **Debug Mode** setting is in Mechanic's ActionHud panel. Use `ActionHud:Logf(category, pattern, ...)` for lazy formatting. No `DevMarker.lua` is loaded by the current TOC; do not assume the legacy `ns.IS_DEV_MODE` flag controls logging.

## Dormant Source and Libraries

`Cooldowns/` contains Essential/Utility Cooldown Manager, TrackedBuffs, TrackedDefensives, and DefensiveTracker experiments. The directory and associated `Settings/EssentialCooldowns.lua`, `Settings/UtilityCooldowns.lua`, and `Settings/Tracked.lua` are neither loaded nor packaged. Re-enabling requires target-build API validation, TOC/package updates, and tests.

`Core/FenCoreCompat.lua`, `Core/init.lua`, `Core/StackContainer.lua`, and `Core/utils_spec.lua` are retained reference/test source outside the runtime and package. First-party reference Lua must remain explicitly excluded from packaging.

Ace3 and required support libraries are embedded. FenCore and !Mechanic are optional dependencies. `Utils.lua` can delegate environment, secret, and table helpers to FenCore, with minimal embedded FenUI utilities or local fallbacks. Preserve these fallbacks.

[Aura API testing](docs/aura-api-testing.md) and [Skinning patterns](docs/skinning-patterns.md) describe historical experiments. Revalidate their observations before applying them to the current target build.

## Validation and Localization

From the addon root:

```powershell
python -m pip install --requirement requirements-dev.txt
python Tests/run.py
python Tests/quality.py --lint
```

The lint command requires Luacheck **1.2.0** (`1.2.0-1` in LuaRocks); use `--luacheck /path/to/luacheck` if it is not on PATH. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup. CI runs the same checks on pull requests and pushes to main.

- `Tests/run.py` validates TOC/XML, localization, and packaging; compiles first-party Lua with Lua 5.1 via pinned Lupa; and runs Python and Lua tests.
- The integration host loads the full active TOC/XML graph with real embedded libraries. Its fake native API models timers, scoped events, and protected geometry, not native taint, secret values, or rendering.
- Test protected API and secure-frame changes in-game after the automated checks. Follow the shared Mechanic workflow when collecting live output.
- Add runtime files to the TOC/XML graph and keep package exclusions consistent. Do not suppress unknown globals merely to satisfy lint.
- All UI strings must use literal `L["KEY"]` lookups and be defined in `Locales/enUS.lua` through AceLocale-3.0. Keep runtime and settings strings localized.

See [STATUS.md](STATUS.md) and the [quality review](docs/quality-review.md) for current offline results and pending in-game checks.

## CurseForge

| Item | Value |
| --- | --- |
| Project ID | 1409478 |
| Project | https://www.curseforge.com/wow/addons/actionhud |
| Author files | https://authors.curseforge.com/#/projects/1409478/files |

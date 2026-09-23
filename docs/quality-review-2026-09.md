# Quality and performance review — 2026-09-23

Deep review of the v2.14.1 tree (commit `ec8723a`) covering the action bars, resources and unit frames, core/layout/utilities, items and buffs, settings and localization, and tests/tooling/packaging. The previous pass is recorded in [quality-review.md](quality-review.md).

**Baseline:** all 27 standalone Lua suites and the Python validators passed. No reviewer found a reachable secret-value violation; native passthrough and fail-closed patterns are consistently applied. The findings below concern release integrity, user-visible behavior, combat-reachable protected calls, and event/layout cost.

**Blizzard source:** the local `wow-ui-source-live` (11.2.7) and `wow-ui-source-beta` (12.0.1) snapshots predate 12.1. 12.1-specific claims were checked against the pinned Gethe mirror commit `8ea15b6` cited in [blizzard-api-review-2026-09.md](blizzard-api-review-2026-09.md).

Status values: **open**, **fixed** (with commit), **deferred**, **won't fix**. Findings marked *in-game* need live validation after the fix.

## Phase plan

| Phase | Scope | Findings |
| --- | --- | --- |
| 1 | Release integrity | R1–R4 |
| 2 | User-visible bugs, each with a regression test | B1–B10 |
| 3 | Protected calls reachable in combat, plus a combat setter sweep test | C1–C4 |
| 4 | Test infrastructure and performance counters, then a recorded baseline | T1–T8 |
| 5 | Event and layout performance, measured before/after | P1–P8 |
| 6 | Action bar cooldown unification, override paging, other correctness | K1–K16 |
| 7 | Dormant code removal, defaults/locale pruning, deduplication, docs | D1–D12 |

## Phase 1 — Release integrity

| ID | Sev | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
| R1 | P1 | `.pkgmeta` `externals` replaces the committed `Libs/` with Ace3/LibStub/LSM trunk at package time. The shipped v2.14.1 contains AceEvent 4, AceDB 36, AceDBOptions 17, AceConfigDialog 93, LibSharedMedia 12000002, LibDBIcon 56; the repo and CI use AceEvent 9, AceDB 33, AceDBOptions 15, AceConfigDialog 92, LSM 3030002, LibDBIcon 55. CI, the integration host, and dev-junction testing run library code players never receive, and every release depends on trunk state on tag day. | `.pkgmeta`; packaged build in the Retail Beta AddOns folder | fixed (phase 1) |
| R2 | P2 | The committed AceEvent-3.0 is a fork with `MINOR = 9` (upstream 4) that defers all registrations through `C_Timer.After(0)` (`5edd82b`). LibStub loads the highest minor, so on dev clients every Ace addon runs the fork; the 2.11.0 changelog fix never shipped. | `Libs/AceEvent-3.0/AceEvent-3.0.lua:15` | fixed (phase 1), *in-game* |
| R3 | P2 | Embedded FenUI populates a shared global (`FenUI.Utils = FenUI.Utils or {}`) without a version guard. Mechanic's older bundled FenUI loads later and overwrites the wrappers, so with Mechanic installed ActionHud runs different safe-API code than players (e.g. `GetInventoryItemCooldownSafe` using `start or 0`). | `Libs/FenUI/ActionHud.lua:3` | fixed (phase 1) |
| R4 | P2 | Uncommitted `ActionHud.toc` edit (`OptionalDeps: WTFix`, `X-WTFix-Managed: 1`) was written by the WTFix launcher through the dev junction; the same marker is in ClassyMap, Weekly and !Mechanic. Releases are tag pushes, so a `commit -a` would ship it. | `git diff ActionHud.toc` | open (owner decision) |

## Phase 2 — User-visible bugs

| ID | Sev | Finding | Where | Status |
| --- | --- | --- | --- | --- |
| B1 | P1 | The resource target split is only applied in `PrepareLayout`, which never runs in combat. Acquiring a target in combat leaves the target half hidden; clearing it leaves two empty half-width bars. Default settings (`resShowTarget = true`). | `Resources.lua:605`, `:811` | fixed (phase 2) |
| B2 | P1 | `PrepareLayout` always clears the class bar's anchors but re-anchors only when class power is available. A Druid shifting to Cat in combat gets a shown, anchorless (invisible) combo-point row for the whole fight; out-of-combat form changes also shift the stack. | `Resources.lua:837`, `:900-913` | fixed (phase 2) |
| B3 | P1 | Unit-frame class bar colour uses numeric `PowerBarColor[powerType]`: combo points (4) receive the Chi colour; Chi (12), Arcane Charges (16), Essence (19) stay grey. | `UnitFrames/Rendering.lua:208` | fixed (phase 2) |
| B4 | P1 | `ResolveSpellID` calls `GetMacroSpell(id)` for macros, but on Retail `GetActionInfo` returns `("macro", spellID, "spell")`. Macro proc glows never show (and IDs ≤ 138 hit unrelated macros). | `ActionBars.lua:817` | fixed (phase 2) |
| B5 | P1 | `UpdateAction` clears `_inRange` on every refresh and `SPELL_UPDATE_ICON` clears range state, while `ACTION_RANGE_CHECK_UPDATE` only fires on change. The out-of-range tint disappears after any layout pass, Edit Mode exit, stealth paging of bar 2, or spell override. | `ActionBars.lua:888`, `:696` | fixed (phase 2), *in-game* |
| B6 | P1 | The readable cooldown path passes `nil` as the loss-of-control frame to `ActionButton_ApplyCooldown`; when `shouldReplaceNormalCooldown` is true both normal and charge sweeps are cleared and nothing replaces them. The test asserts the gap. | `ActionBars.lua:1113` | fixed (phase 2), *in-game* |
| B7 | P1 | Unit Frames **Reset Position** writes `ufConfig[frameId].xOffset/yOffset`, which nothing reads; positions use `uf<Frame>XOffset/YOffset`. `Tests/test_settings.lua:135` asserts the dead key. | `Settings/UnitFrames.lua:403` | fixed (phase 2) |
| B8 | P1 | Unit-frame per-text **Font** is ignored: `ApplyTextStyle` prefers the frame font, which always has the default. | `UnitFrames/Layout.lua:97` | fixed (phase 2) |
| B9 | P1 | `Utils.GetTimerFont` falls back to a constant because embedded FenUI no longer defines `GetTimerFont`; Trinkets **Timer Font Size** has no effect. The runtime test stubs the function. | `Utils.lua:127` | fixed (phase 2) |
| B10 | P1 | Combat-interrupted drag defers `StopMovingOrSizing` until `PLAYER_REGEN_ENABLED`; unprotected containers (and the root while unit frames are off) keep following the cursor all fight. | `Core/DraggableContainer.lua:99`, `ActionHud.lua:217` | fixed (phase 2), *in-game* |

## Phase 3 — Protected calls reachable in combat

| ID | Sev | Finding | Where | Status |
| --- | --- | --- | --- | --- |
| C1 | P2 | **Hide Blizzard Frames** calls `ApplyBlizzardFrameVisibility` directly; `PlayerFrame:EnableMouse` is blocked in combat. | `Settings/UnitFrames.lua:704` | fixed (phase 3) |
| C2 | P2 | **Unlock Module Positions** calls `UpdateAllOverlays` directly; unit-frame containers are protected (secure children), so `EnableMouse`/`SetFrameStrata` are blocked. | `Settings/Layout.lua:32`, `Core/DraggableContainer.lua:190` | fixed (phase 3) |
| C3 | P2 | Blizzard frame restore runs on every login/reconcile even when ActionHud never hid anything, forcing alpha and mouse on PlayerFrame/TargetFrame/FocusFrame/ToT and undoing other addons. | `UnitFrames/UnitFrames.lua:95`, `:132` | fixed (phase 3) |
| C4 | P3 | Trinkets passes possibly-secret start/duration to `SetCooldown` (`AllowedWhenUntainted`); unreachable today, should fail closed like Consumables. | `Trinkets.lua:165` | fixed (phase 3) |

## Phase 4 — Tests and tooling

| ID | Sev | Finding | Status |
| --- | --- | --- | --- |
| T1 | P2 | About 12 ad-hoc secret mocks; the shared host hardcodes `issecretvalue = false`. Add one shared secret factory and a restricted mode for the full-TOC host. | open |
| T2 | P2 | The host models deprecated tuple-returning action globals, not the 12.1 table-returning `C_ActionBar` API. | open |
| T3 | P2 | No regression tests for spell overrides (`SPELL_UPDATE_ICON`/`UpdateProc`), macro resolution, range persistence, combat target changes, Druid combat shift, unit-frame colours, or Blizzard frame hiding. | open |
| T4 | P2 | A combat sweep that calls every settings setter under `InCombatLockdown()` catches C1/C2; make it a permanent test. | fixed (phase 3) |
| T5 | P3 | `quality.py` lacks unused/duplicate locale key checks, a TOC metadata allow-list, and a pinned library-version manifest. | open |
| T6 | P3 | `.luacheckrc` ignores whitespace (611) on the assumption `git diff --check` runs in CI; it does not, and committed files contain trailing whitespace. No `.gitattributes`. | open |
| T7 | P3 | Consumables, Recent Buffs, the catalog, and most ActionBars handlers have no performance counters; `ActionBarsUpdate` conflates refresh and icon events. | open |
| T8 | P3 | `run.py` stops at the first failing suite without a summary; `Core/utils_spec.lua` is never run. | open |

## Phase 5 — Performance

| ID | Sev | Finding | Where | Status |
| --- | --- | --- | --- | --- |
| P1 | P2 | Every `PLAYER_TARGET_CHANGED` requests a full HUD pass (all modules prepared/measured/rendered, ActionBars `RefreshAll`, unit-frame restyle with `SetBackdrop`, UnitFrames `UpdateAll` twice). `UPDATE_SHAPESHIFT_FORM` (all classes), unfiltered `PLAYER_SPECIALIZATION_CHANGED` (fires for group members), and `UNIT_MAXPOWER` do the same. | `Resources.lua:605`, `:639-646` | open |
| P2 | P2 | ActionBars uses `SPELL_UPDATE_COOLDOWN` (per-spell payload, bursty) to refresh all buttons; Blizzard uses `ACTIONBAR_UPDATE_COOLDOWN`. `ACTIONBAR_UPDATE_USABLE` duplicates `ACTION_USABLE_CHANGED`; `ACTIONBAR_UPDATE_STATE` refreshes count/usable/proc on every button per cast; `SPELL_UPDATE_CHARGES` re-runs cooldowns. LoC events are not unit-filtered. | `ActionBars.lua:182-189` | open |
| P3 | P2 | Consumables refreshes all slots on every `GET_ITEM_INFO_RECEIVED` (any item, any addon), on every `SPELL_UPDATE_COOLDOWN`, and three times per potion use; each refresh calls `Describe` and allocates per slot. | `Consumables.lua:67-87`, `:144` | open |
| P4 | P2 | PlayerBuffs catalog events request full layout passes while the feature is off (default); every pass disables/re-enables the aura container and rebuilds 12 filters. | `PlayerBuffs.lua:66-81`, `:202-237` | open |
| P5 | P3 | Resources power events are not filtered by power token; class-power type re-resolved (two pcalls) per tick; unchanged segment ranges/colours re-applied. | `Resources.lua:618-627`, `Utils.lua:537` | open |
| P6 | P3 | Allocation churn: `SafeCompare` fallback allocates a closure per call (up to 72 per slot change), `GetUnitHealsSafe` per health event, `or {}` in range/assist handlers, a timer closure per layout request, and about 20 tables per layout pass. | `Libs/FenUI/Utils/Utils.lua:66`, `Utils.lua:631`, `ActionBars.lua:396,782` | open |
| P7 | P3 | Recent Buffs rescans all auras on every out-of-combat `UNIT_AURA`, including update-only payloads that cannot add IDs. | `Core/RecentPlayerBuffs.lua:87-155` | open |
| P8 | P3 | Trinkets requests a full layout on every `PLAYER_EQUIPMENT_CHANGED` instead of slots 13/14; the catalog computes unused spell descriptions. | `Trinkets.lua:350`, `Core/BlizzardBuffCatalog.lua:100` | open |

## Phase 6 — Other correctness

| ID | Sev | Finding | Where | Status |
| --- | --- | --- | --- | --- |
| K1 | P2 | Vehicle, override, temporary-shapeshift and possess bars are not mapped; pet battles show player actions. Use Blizzard's order and `C_ActionBar.GetBonusBarIndex`, and register the three bar events. | `ActionBars.lua:856-882` | open, *in-game* |
| K2 | P2 | Restricted path selects one cooldown type and clears the charge frame: a 1/2-charge spell shows a full swipe in instanced combat, unlike the readable path. Unify on never-secret booleans plus duration objects (also fixes B6). | `ActionBars.lua:1122-1140` | open, *in-game* |
| K3 | P2 | Edit Mode settings fall back to 2×12 after `/reload` or Edit Mode exit inside party/raid/arena instances. | `ActionBars.lua:31-43` | open |
| K4 | P2 | FenUI's 16 ms `IsSpellOverlayed` cache can serve stale values to glow events in the same frame. | `Libs/FenUI/Utils/SafeAPI.lua:330` | fixed (phase 2) |
| K5 | P2 | One module's error aborts the whole layout pass (single `pcall`), can leave the HUD blank, and loses the stack trace. | `LayoutManager.lua:422-456` | open |
| K6 | P2 | `IS_MIDNIGHT` is `interface >= 120000`, false on WoW Forever (16001, Retail API). Use feature detection. | `Libs/FenUI/Utils/Utils.lua:32` | open |
| K7 | P2 | New and reset profiles run `MigrateOldSettings`: stale `cooldowns` stack entry, 1 px vs 4 px gap, hash-order append. | `LayoutManager.lua:532-577` | open |
| K8 | P2 | Hide Blizzard Frames uses alpha only: invisible target aura buttons still show tooltips, pet/totem frames become invisible but clickable, and focus/ToT hide even when their custom frames are off. | `UnitFrames/UnitFrames.lua:112-150` | partly fixed (phase 3: per-frame gating; child mouse handling open), *in-game* |
| K9 | P2 | Unit-frame class/reaction text colours are applied only during layout and go stale after target/focus/ToT changes. | `UnitFrames/Layout.lua:91-123` | open |
| K10 | P2 | Secret numbers are shown unabbreviated (`AbbreviateNumbers` accepts secrets); secret names are blanked; `GetUnitName` may error under restricted identity. | `UnitFrames/Identity.lua:201`, `Rendering.lua:256` | open, *in-game* |
| K11 | P2 | Unit-frame heal prediction is hidden in instanced combat; Resources already has a calculator-based overlay. | `UnitFrames/Rendering.lua:237-251` | open |
| K12 | P3 | Trinkets: no `BAG_UPDATE_COOLDOWN`, drag overlay visible in stack mode, no retry when item data is uncached, hard-coded default position. | `Trinkets.lua` | open |
| K13 | P3 | PlayerBuffs stack count is parented to the cooldown frame and hides with it. | `PlayerBuffs.lua:185` | open, *in-game* |
| K14 | P3 | Recent Buffs updates redraw the picker (discarding typed input) and check `IsShown` instead of `IsVisible`. | `Settings/init.lua:197` | open |
| K15 | P3 | Unit-frame level text shows raw `UnitLevel` (-1 for bosses); `UNIT_LEVEL`/`UNIT_NAME_UPDATE` unhandled; Essence partial fill is a frozen snapshot; unit-frame class pools use unmodified units. | `UnitFrames/Rendering.lua`, `Resources.lua:142` | open |
| K16 | P3 | Consumables shows pending cooldowns (`enable == false`) as unknown ("?"); Trinkets "Grow Direction" only reorders icons. | `Consumables.lua:153`, `Trinkets.lua:276` | open |

## Phase 7 — Cleanup and documentation

| ID | Finding | Status |
| --- | --- | --- |
| D1 | Dormant code: about 4.7k lines of first-party Lua (`Cooldowns/`, three settings files, four reference Core files) plus about 10k unloaded FenUI lines and `Libs/FenCore`. The API review says the dormant loops are not a 12.1 foundation. Archive-tag and remove. | open |
| D2 | 65 of 188 default keys are dead; `ufConfig.*.xOffset/yOffset` duplicate defaults; `resBarWidth = nil`. | open |
| D3 | 222 of 531 locale keys are unused; 22 are defined twice; hard-coded English in `/ah reset`, `/ah pos`, unlock labels, Mechanic tests, role icon label. | open |
| D4 | About 15 unused `Utils` wrappers; `GetTotemDataForSpellID` compares unchecked values; `GetActionDisplayCountSafe` fallback maps to use-count. | open |
| D5 | Unused libraries: AceHook loaded but unused; LibDBIcon, LibDataBroker, MechanicLib shipped but never loaded; stale LibStub/CallbackHandler inside LSM; 344 KB unreferenced logo. | open |
| D6 | Dead features: minimap option, Mechanic Record/Clear and debug buffer, `SetLayoutMode` loop, `OpenSettings` category search, `refreshGeneration`, legacy cooldown/count/range-ticker paths. | open |
| D7 | Stale in-game help (`/ah debug`, `/ah clear`, "6x4 grid"), `/ah pos` wrong keys, `/ah reset` "reload" text, `/ah wipe` without confirmation, Mechanic "Toggle Lock" only flips `locked`. | open |
| D8 | Duplicated position/stack-inclusion settings blocks (five variants), Trinkets/Consumables slot builders, Consumables/PlayerBuffs grid and picker paging, Resources/unit-frame bars, colours and heal overlays. | open |
| D9 | Settings UX: no confirmation on Copy Settings From (copies `enabled`), Clear IDs/History; mislabeled "Bar Width"; per-frame "Show All Icons"; misleading descriptions. | open |
| D10 | Docs: Forever missing from README/AGENTS; CHANGELOG duplicates; `quality-review.md` counts stale; lifecycle contract duplicated between AGENTS.md and `runtime-layout.md`; AGENTS rule 1 names wrappers with no callers. | open |
| D11 | `.pkgmeta` still ignores `DevMarker.lua`; no `manual-changelog`; `.gitignore` lists tracked files; 36 stale `.luacheckrc` read globals; `Libs/FenUI` first-party code is not linted. | open |
| D12 | Seven stale worktrees/branches (all merged or patch-equivalent), including one nested inside the junctioned addon folder; mixed tag naming. | open |

## In-game validation queue

Run after the related phase lands and the development build is reloaded:

1. Phase 1: `/reload` with and without Mechanic; enter combat, open settings, toggle modules; watch for `ADDON_ACTION_FORBIDDEN`/`BLOCKED`.
2. Phase 2: target acquisition and clearing in combat; Druid caster→Cat in combat; unit-frame colours on Rogue, Monk, Arcane Mage, Evoker; `/cast [@mouseover]` macro proc glow; out-of-range tint across Edit Mode exit and stealth; interrupt lockout sweep in the open world; unit-frame reset and font; trinket timer sizes; drag interrupted by combat.
3. Phase 3: toggle Hide Blizzard Frames and Unlock Module Positions in combat.
4. Phases 5–6: `/ah perf` baseline comparisons (tab-target 20×, dummy rotation, Auction House browsing with Consumables on); vehicle, override-bar encounter, pet battle; charge spells in instanced combat.

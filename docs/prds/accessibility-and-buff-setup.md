# PRD: Accessible displays and guided buff setup

Status: Implemented in this branch (all four phases); native sound triggers, live style updates, and preset values still need in-game validation. See Implementation notes.

Date: 2026-09-06

Product: ActionHud

Baseline: v2.14.0, targeting WoW Retail 12.1

## Decision and problem

Expand ActionHud with accessible presentation, optional aura sounds, useful style presets, and better buff setup guidance. These are two related feature tracks within ActionHud, not separate addons. The proposed migration tool for old aura configurations is intentionally excluded: the owner considers that transition opportunity too late to pursue.

The current HUD provides working native displays, but players must tune several controls to make important information readable. Choosing a valid spell name does not guarantee choosing its buff: Rallying Cry demonstrated a cast-ID versus aura-ID mismatch during live testing. Discovery restrictions and incomplete catalog coverage can also make a valid configuration look broken.

The intended result is that a player can choose a few important buffs, make them easy to recognize, optionally hear supported aura events, and understand what has and has not been verified.

## Users and goals

- Players who need larger text, stronger contrast, less visual clutter, or optional audio reinforcement.
- Players configuring buffs without knowing spell IDs or class-specific API details.
- Existing ActionHud users who want these improvements without rebuilding their layout.

Success means easier setup and recognition, not more automatic combat decisions. Validate the presentation with players who have the relevant accessibility needs; presets alone do not establish accessibility.

## Existing foundation

[PlayerBuffs.lua](../../PlayerBuffs.lua) delegates rendering to the native aura container. [RecentPlayerBuffs](../../Core/RecentPlayerBuffs.lua) records bounded readable history outside restricted contexts, and [BlizzardBuffCatalog](../../Core/BlizzardBuffCatalog.lua) supplies public catalog metadata and candidate IDs. [PlayerBuffPicker](../../Settings/PlayerBuffPicker.lua) provides source selection, search, paging, ordering, and preview. Existing profiles support 12 selected buffs, fixed slot geometry, independent dragging or HUD stacking, and manual IDs.

Preserve those behaviors. This proposal builds on the existing picker and layout scheduler rather than introducing another rendering or discovery path.

## Track A: Accessible presentation and optional sounds

### Style controls

1. Add a coherent presentation group for icon size, spacing, countdown/stack text size and outline, background contrast, and border visibility where the relevant native widget supports them.
2. Start with Player Buffs, then extend applicable controls consistently to Action Bars, Trinkets, Consumables, and resource/unit-frame text. Do not imply every module supports identical properties.
3. Keep critical information understandable without color alone. Static labels or borders must remain tied to configured public identity, not inferred hidden aura state.
4. Provide clearly labeled sample previews, including inactive slots and representative timer/stack text. Samples use synthetic data and do not claim to verify live behavior.

### Preset starting points

Provide a small set of style presets: Large Text, High Contrast, and Compact. Exact values are to be established through visual testing. Audio is a separate opt-in choice and stays off when applying a style preset.

Before applying a preset, show which modules and settings it changes. Preserve spell/item selections, feature enablement, and positions unless explicitly included by the player. Support undo of the most recent application and retain manual customization. Existing profiles keep their appearance on upgrade; applying a preset is never automatic.

### Native aura sounds

Allow a player to assign and preview a sound for an eligible selected buff, initially for application. Offer a short bundled set; optional shared-media sounds must have a predictable fallback if removed. Add per-selection mute and a master sound toggle. Do not require external sound packs.

Use Blizzard's native aura-sound registration, with game-owned event evaluation. Revalidate eligible units, trigger kinds, registration restrictions, and cleanup on the implementation build before finalizing the UI. Expiration and stack-change sounds are a later phase only if verified. Visual candidate-ID support does not establish equivalent sound-rule support: ambiguous mappings must remain explicitly unresolved, and overlapping candidates must not create duplicate alerts.

Registration changes follow profile/enablement lifecycle and combat deferral. Removing a buff, disabling audio, switching profiles, or disabling the module must retire prior rules when permitted. A manual preview is a sound audition, not evidence that the live trigger works. Do not promise custom throttling or priority arbitration unless the native API supports it without exposing combat state.

## Track B: Guided buff selection and diagnosis

1. Retain Recent Buffs, Blizzard Catalog, and Advanced IDs; avoid a dependency on a large manually curated class list.
2. Identify each selection's evidence: observed aura ID in readable history, Blizzard catalog candidate(s), documented mapping, or unverified manual ID. Evidence categories are not guarantees of current combat activity.
3. Explain known cast-to-aura mappings in plain language. Preserve documented sources, reviewed build, and explicit ambiguity; never assume the first linked spell is the buff.
4. Explain when discovery is unavailable and what the player can do next. Absence from recent history does not mean an invalid ID. A missing catalog entry does not mean a spell is untrackable.
5. Offer a short guided test: configure, preview appearance/sound, apply changes outside combat, obtain the buff, and let the player record whether it appeared or sounded. Keep player-confirmed results separate from machine-observed facts and label their character/build context.
6. When a test fails, show relevant public checks and next steps: resolved name, configured candidates, enabled state, deferred changes, and discovery availability. Never infer a hidden aura is absent or claim a specific cause without evidence.

The existing simple add/remove flow remains available; a wizard is optional. Any persisted setup metadata must be bounded, must survive profile changes predictably, and must not turn recent history into a combat log. Reuse `playerBuffsSpellIDs` for selections; version any additional metadata separately.

## Boundaries and dependencies

- Maintain native aura ownership: no polling, child-widget inspection, hooks that infer live aura state, or Lua timer/stack calculations on restricted values.
- Use LayoutManager for geometry and lifecycle. Retain fixed slots and combat deferral.
- Initialize native widgets only at the supported initialization boundary; verify how subsequent style changes can be applied safely before implementation.
- No automatic spell use, rotation advice, full WeakAuras compatibility, or arbitrary conditional scripting.
- No new mandatory Mechanic or spell-list dependency. A future Mechanic report integration is optional; ActionHud setup must work on its own.
- Localize new controls, guidance, evidence labels, and errors.

## Delivery and acceptance

| Phase | Deliverable | Acceptance gate |
| --- | --- | --- |
| 1 | Picker evidence and guided checks | Rallying Cry mapping is explained; unknown IDs stay usable and unverified; restricted discovery never reports a false invalid result |
| 2 | Player Buffs styles, synthetic preview, presets | Presets preview their changes, preserve selections/positions by default, undo correctly, and leave upgraded profiles unchanged |
| 3 | Native application sounds | An eligible buff sounds once per intended event; mute/removal/profile switching retire rules; unsupported or ambiguous rules are explained |
| 4 | Applicable styles across HUD modules | Large text remains readable without overlap; drag overlays and stacked layouts remain correct across UI scales |

For each runtime phase, run the repository checks in [CONTRIBUTING](../../CONTRIBUTING.md), including Lua regressions and lint. Cover persistence, preset undo, unavailable APIs, missing media, mapping ambiguity, and rule cleanup offline. In-game validation must cover open world and instanced combat, profile changes, deferred edits, reloads, and relevant classes. Offline tests do not certify native secret-value or taint behavior.

For usability acceptance, ask representative testers to select three buffs and configure a readable presentation without looking up an ID. Record confusion points and whether the preview predicts the actual layout. Do not require relogging between routine configuration steps.

## Evidence and open questions

The [API review](../blizzard-api-review-2026-09.md) records the original research baseline. Blizzard-authored source is available through the community-maintained Gethe mirror, pinned to 12.1.0 build 69587, commit `8ea15b61e45c0ed4eba01439c90757f86eb78d34`:

- [Aura-sound registration and removal](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua).
- [Native custom aura button implementation](https://github.com/Gethe/wow-ui-source/blob/8ea15b61e45c0ed4eba01439c90757f86eb78d34/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua).

Resolve before the associated phase: supported live style-update methods; exact sound-trigger eligibility and candidate handling; final preset values; and the minimal per-character evidence schema. These are implementation investigations, not promises that the current APIs support every proposed variation.

## Implementation notes

- Evidence and setup check: `Core/BuffEvidence.lua`, `Settings/PlayerBuffPicker.lua`, `Settings/PlayerBuffSetup.lua`. Schema: `char.playerBuffSetup = { version = 1, tests = { [spellID] = { appearance, sound, class, client } }, order = { ... } }`, capped at 24 entries.
- Live style updates: addon-owned Font objects referenced once by the native buttons plus public textures on the slot anchor. This is the proposed mechanism and needs in-game confirmation that the restricted widgets follow the Font objects.
- Sounds: `C_UnitAuras.AddAuraSound(Enum.UnitAuraSoundTrigger.Added, { unitToken = "player", spellID, soundFileName })`, unit `player` only. Bundled sounds are Blizzard client files; their paths need in-game confirmation. Expiration and stack sounds remain a later phase.
- Preset values in `Core/Presentation.lua` are starting points pending visual testing.
- Not implemented: static per-slot name labels.

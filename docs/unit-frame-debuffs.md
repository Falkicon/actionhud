# Player and target debuffs

Reviewed on 2026-10-19 for the addon's declared Retail (`120100`, `120105`)
and Forever (`16001`) interfaces. This is a source/API review and offline
implementation result. The user confirmed the basic debuff display works in
game; client/build and combat scenarios were not specified. Hover tooltips and
broader combat/taint behavior still require live verification.

## Source snapshots

The GitHub branch heads fetched for this review were:

| Client source | Commit |
| --- | --- |
| [Retail live](https://github.com/Gethe/wow-ui-source/tree/b9be9379719047977fca4dba1bb1d9988e8840b3) | `b9be9379719047977fca4dba1bb1d9988e8840b3` |
| [Forever](https://github.com/Gethe/wow-ui-source/tree/172a387e3ab85b26e6640d3058d5ec1e6ccd4c63) | `172a387e3ab85b26e6640d3058d5ec1e6ccd4c63` |

The custom container Lua/XML, custom button, frame provider, group, inbound,
and flow-layout files compared identically between these snapshots. Recheck
these sources and the live checklist when Blizzard changes the aura API.

- [Custom container](https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua): `AddAuraGroup(key, "HARMFUL", options)` supports native limits, candidate filters, sorting, and flow layout. The corresponding [Forever implementation](https://github.com/Gethe/wow-ui-source/blob/172a387e3ab85b26e6640d3058d5ec1e6ccd4c63/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua) exposes the same methods.
- [Filter implementation](https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerUtil.lua): spell-ID includes reject unfilterable friendly harmful auras. An empty filter table avoids discarding restricted player/friendly-target debuffs. The unit-frame debuff sort delegates to Blizzard's comparator.
- [Frame provider](https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerFrameProviders.lua): the engine invokes `initializeFrame` before applying child access restrictions, and can allocate further batches later.
- [Custom button](https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua): `SetIcon`, `SetDurationCooldown`, and `SetApplicationCount` bind native display widgets. ActionHud never reads aura identities, durations, or counts back from them.
- [Intrinsic aura button](https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraButton.lua): native enter/leave handlers display and hide the restricted aura tooltip. The initializer calls `SetMouseMotionEnabled(true)` and `SetMouseClickEnabled(false)`, the frame setters used by [Blizzard's MapCanvas](https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua); addon code never hooks these handlers or reads tooltip/aura data. The intrinsic button Lua/XML compared identically on Retail and Forever.
- [Shared container](https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainer.lua): the container owns scoped aura events, while public `UpdateAllAuras()` is available for external changes such as target swaps.
- [Flow layout](https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerFlowLayout.lua) and [layout defaults](https://github.com/Gethe/wow-ui-source/blob/b9be9379719047977fca4dba1bb1d9988e8840b3/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerShared.lua): the native engine controls group placement and container size. ActionHud uses public parents for anchoring and scale, with no reads of native bounds.

## Settings and runtime

Under **Unit Frames → Player Frame / Target Frame → Debuffs**, **Show Debuffs**
defaults to off for each frame. The defaults are 24-pixel icons, at most 10
debuffs, 2-pixel spacing, and a 4-pixel gap below the frame. Users can select
16–48-pixel icons, up to 24 debuffs, spacing, gap, and above/below placement.
The group displays harmful auras from any caster that Blizzard admits, up to
the limit, using native unit-frame debuff sorting. It has no spell-ID picker
or caster filter. Hovering an icon shows Blizzard's native aura tooltip. Icons
remain display-only and do not consume clicks.

`UnitFrames/Auras.lua` retrieves the existing module after its original four
files. LayoutManager prepares group configuration, positions the secure frame,
then enables the group during render. Stopping the frame stops its group.
Target changes refresh the applied native display during combat; changes to
settings and profiles defer until combat ends. Hidden or missing target frames
hide their descendant debuff display.

Every button is initialized at a constant size inside the native callback.
Scaling its ordinary parent changes existing and future icons together.
Wrappers reserve the configured maximum footprint, and icons wrap to the frame
width. Aura appearance and expiration never alter secure frame dimensions or
HUD-stack measurements. No child references, aura polling, visibility hooks,
timer calculations, or scan-ignore exemptions are added. Countdown decimals
use the same fixed 3-second native threshold as Player Buffs.

## Offline verification

`Tests/test_unitframe_debuffs.lua` exercises native group bindings, independent
toggles, layout, restricted target changes, another initialization batch during
combat, profile switching/copy/reset, enable/disable, and copied configurations
without debuff fields. `Tests/test_unitframe_debuffs_failure.lua` checks failed
group creation and widget callback failures. The full-TOC combat-startup and settings-sweep suites include
active debuff displays. The inbound-only fake rejects post-initialization child
reads/writes and combat configuration writes. It cannot prove native rendering
or taint safety.

The mouse-input regression was reproduced by correcting the host's method names
before correcting runtime calls: the debuff initialization test failed with the
invalid calls and passed with the supported `SetMouseMotionEnabled` and
`SetMouseClickEnabled` setters. The host provides no aliases for the invalid
names, so that initialization failure remains covered.

On 2026-10-19, all 32 Lua suites and 13 Python validator tests passed, including
Lua 5.1 compilation and manifest/localization/package checks. Luacheck 1.2.0
reported zero warnings/errors across 31 active first-party Lua files.

Run `python Tests/run.py` and `python Tests/quality.py --lint` with Luacheck
1.2.0 as documented in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Pending live checks

Perform these on both Retail and Forever, recording the build and character:

1. Reload the changed addon. Enable custom Player/Target frames and each
   **Show Debuffs** toggle. Apply harmful auras from yourself and other casters;
   check icons, expiration, early dispels, stacks, and countdowns.
   Hover player and target debuffs before and during combat; verify tooltip
   contents and dismissal when leaving, expiring, hiding, or changing targets.
2. Test player and friendly-target debuffs in instanced combat, including
   encounter/private auras where available. Compare the visible group with
   Blizzard's display, accounting for the configured icon limit.
3. Switch between hostile, friendly, and absent targets during combat. Confirm
   no stale target icons, visibility errors, blocked actions, or taint errors.
4. Change icon size, count, spacing, gap, above/below placement, and frame width;
   verify wrapping and positions at different UI scales. Drag each frame.
5. Repeat configuration changes, per-frame/master toggles, profile
   switch/copy/reset, and reload during combat. Geometry must apply after combat
   and native aura updates must continue while the old configuration is active.

Mechanic MCP was unavailable in this implementation session; no installed
client state or live diagnostic output was collected.

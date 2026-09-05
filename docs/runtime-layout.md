# Runtime lifecycle and layout

`LayoutManager:RequestLayout(reason)` is the entry point for geometry changes.
Requests coalesce into one next-frame callback. `TriggerLayoutUpdate()` remains
an alias for existing settings code. A request records intent; it does not read
or capture the profile, so several changes in one frame use the latest values.

Combat holds the request until `PLAYER_REGEN_ENABLED`. Disabling LayoutManager
invalidates queued callbacks with a generation counter. An old callback cannot
clear a newer callback's scheduling state. Requests made while rendering arrange
one follow-up pass; requests made during lifecycle reconciliation are consumed
by the current pass.

Each pass runs these phases for stack and independent modules:

1. Reconcile pending lifecycle transitions against the current profile.
2. `PrepareLayout()` updates the content needed to measure it. Action bars lay
   out their buttons, resources apply their configuration, and trinkets discover
   equipped on-use items.
3. Measure stack heights and widths into a complete manager-owned snapshot.
4. Size the root and call `ApplyLayoutPosition()` on active modules.
5. `RenderLayout()` refreshes icons, resource values, cooldowns, and unit frames.

UnitFrames participates as an auxiliary module outside the stack. Its secure
geometry changes use the same combat deferral as the main HUD.

## UnitFrames source map

The TOC loads the files in this order:

| File | Responsibility |
| --- | --- |
| `UnitFrames/Identity.lua` | Restricted identity normalization, colors, status icon decisions, and value formatting. |
| `UnitFrames/UnitFrames.lua` | Creates the Ace module and defines lifecycle, scoped event routing, and layout requests. |
| `UnitFrames/Layout.lua` | Constructs frames and applies configured styling and geometry. Creation and style helpers stay local here. |
| `UnitFrames/Rendering.lua` | Updates values, prediction, text, and icons, then implements the final render phase. |

The latter files retrieve the existing Ace module. Identity helpers retain their
existing `ns.UnitFrameIdentitySafety` namespace; no additional global helper API
is introduced by the split.

## Runtime state

Runtime modules expose these state fields:

| Field | Meaning |
| --- | --- |
| `_desiredEnabled` | Latest feature toggle read from the profile. |
| `_runtimeActive` | Frames and runtime event subscriptions have been started. |
| `_pendingEnabledState` | A lifecycle or secure geometry change needs the next out-of-combat pass. |

`ApplyEnabledState()` records desired state, defers in combat, and reconciles
outside combat. `StartRuntime()` is idempotent. Stop paths unregister global and
scoped events, hide their frames when allowed, and request a new measurement.
UnitFrames unregisters immediately on stop but defers protected hiding if combat
is active. The manager requires both Ace `IsEnabled()` and `_runtimeActive`
before preparing, positioning, or rendering a module.

Ace module enablement and feature enablement remain separate concepts. ActionBars
and Trinkets preserve their existing Ace enable/disable toggles. Resources and
UnitFrames keep their Ace module available while their profile feature is off.
Consumers should use `_runtimeActive` to ask whether a feature is running.

`Core/Defaults.lua` is the single source of profile defaults. Settings reset
controls read `addon.db.defaults.profile`; they should not repeat default values.

Module `UpdateLayout()` methods only request the manager. They must not perform
layout immediately, publish heights, start their own layout timers, or call a
manager pass recursively. Dynamic value events can still update their existing
widgets directly; geometry changes request a pass. External code should not call
`PrepareLayout()`, `ApplyLayoutPosition()`, or `RenderLayout()` itself.

Run `python Tests/run.py` for queued scheduling, lifecycle, combat deferral,
full-TOC startup, and protected-value regression coverage. Secure geometry and
stance/form behavior still require an in-game combat check.

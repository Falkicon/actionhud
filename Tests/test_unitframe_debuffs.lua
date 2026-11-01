-- Inbound native contract, not a simulation of aura selection or rendering.
local host = assert(loadfile("Tests/support/wow.lua"))()
local native = assert(loadfile("Tests/support/aura_container.lua"))()(host)
local addon, ns = assert(loadfile("Tests/support/load_addon.lua"))()(host)
local frames = addon:GetModule("UnitFrames")
local options = ns.Settings.BuildUnitFramesOptions(addon).args
local player = options.player.args.debuffs.args
local target = options.target.args.debuffs.args
local originalProfile = addon.db:GetCurrentProfile()
local function flush() host:Flush(); host:AssertNoErrors() end
local function set(option, value) option.set(nil, value); flush() end
local function assertNativeHover(group)
	for _, slot in ipairs(group.buttons) do
		assert(slot.button.mouseMotionEnabled and slot.button.mouseClicksEnabled == false,
			"debuffs must accept native tooltip hover without consuming clicks")
		assert(not slot.button.scripts.OnEnter and not slot.button.scripts.OnLeave,
			"addon scripts must not replace native tooltip handlers")
		assert(slot.cooldown.mouseEnabled == false, "cooldowns must pass hover through to the aura button")
	end
end
flush()
assert(not options.focus.args.debuffs and not options.targettarget.args.debuffs)
assert(not player.enabled.get() and not target.enabled.get() and #native.containers == 0)
set(options.enable, true)
assert(#native.containers == 0, "enabled unit frames must keep opt-in debuff displays inert")

-- Unsupported clients keep ordinary unit frames working and explain why.
local api = C_AuraContainerUtil
C_AuraContainerUtil = nil
assert(player.enabled.disabled() and player.note.name() == "Native debuff displays are unavailable on this client.")
set(player.enabled, true)
assert(#native.containers == 0 and frames.frames.player.health)
C_AuraContainerUtil = api
frames:UpdateLayout(); flush()
assert(#native.containers == 1)
local p, playerState = frames.frames.player.debuffDisplay, native.containers[1]
local playerGroup = playerState.groups.debuffs
assert(playerState.enabled and playerState.unit == "player")
assert(playerGroup.filter == "HARMFUL" and next(playerGroup.options.candidateFilters) == nil)
assert(playerGroup.maxCount == 10 and #playerGroup.buttons == 10)
assert(p.anchor.parent == frames.frames.player and p.scaled.parent == p.anchor)
assert(playerState.frame.parent == p.scaled and p.scaled.scale == 1)
assert(p.anchor:GetWidth() == 128 and p.anchor:GetHeight() == 50)
assert(p.anchor.point[1] == "TOPLEFT" and p.anchor.point[3] == "BOTTOMLEFT" and p.anchor.point[5] == -4)
assert(playerState.lineSize == 128 and playerState.flowAnchor == "TOPLEFT")
for _, slot in ipairs(playerGroup.buttons) do
	assert(slot.icon and slot.cooldown and slot.count)
	assert(slot.button.width == 24 and slot.button.height == 24)
	assert(slot.cooldown.countdownThreshold == 3)
end
assertNativeHover(playerGroup)
set(target.enabled, true)
local t, targetState = frames.frames.target.debuffDisplay, native.containers[2]
assert(targetState.unit == "target" and targetState.enabled and #native.containers == 2)
assertNativeHover(targetState.groups.debuffs)
assert(t.anchor.parent == frames.frames.target and frames.frames.target.unitWatch)
frames.frames.target:Hide()
assert(not t.anchor:IsVisible(), "debuffs inherit the target frame's unit-watch visibility")
frames.frames.target:Show()

-- Native events own aura changes. No addon polling or geometry follows them.
local writes = native.writes
local frameCount = #host.frames
host:Fire("UNIT_AURA", "player", host.Secret.new({}))
host:Fire("UNIT_AURA", "target", host.Secret.new({}))
flush()
assert(native.writes == writes and #host.frames == frameCount)
host:Fire("PLAYER_TARGET_CHANGED")
assert(targetState.refreshes == 1 and playerState.refreshes == 0)

-- Reconfigure public wrappers and inbound layout without touching children.
set(player.iconSize, 36)
set(player.maxCount, 12)
set(player.spacing, 3)
set(player.gap, 6)
set(player.position, "ABOVE")
assert(p.scaled.scale == 1.5 and p.anchor:GetWidth() == 114 and p.anchor:GetHeight() == 153)
assert(p.anchor.point[1] == "BOTTOMLEFT" and p.anchor.point[3] == "TOPLEFT" and p.anchor.point[5] == 6)
assert(playerState.flowAnchor == "BOTTOMLEFT" and playerState.growth[2] == AnchorUtil.FlowDirection.Up)
assert(playerState.lineSize == 76 and playerGroup.layout.elementSpacing == 2 and playerGroup.maxCount == 12)
assert(playerGroup.buttons[1].button.width == 24 and #native.containers == 2)

host:SetRestricted(true)
host:SetCombat(true)
writes, frameCount = native.writes, #host.frames
set(player.iconSize, 48)
set(player.maxCount, 24)
set(player.position, "BELOW")
set(target.enabled, false)
assert(native.writes == writes and #host.frames == frameCount and p.scaled.scale == 1.5)
assert(targetState.enabled, "protected display changes must wait for combat to end")
host:Fire("PLAYER_TARGET_CHANGED")
assert(targetState.refreshes == 2, "target swaps must refresh the applied display during combat")
-- The engine may need another batch while combat data is restricted. Only its
-- one-time initializer touches these new widgets, retaining no child handles.
native:CreateGroupBatch(playerState, "debuffs")
assert(#playerGroup.buttons == 20 and native.writes == writes)
assertNativeHover(playerGroup)
host:SetRestricted(false)
host:SetCombat(false)
assert(p.scaled.scale == 2 and playerGroup.maxCount == 24 and not targetState.enabled)
assert(playerState.flowAnchor == "TOPLEFT" and playerState.growth[2] == AnchorUtil.FlowDirection.Down)
assert(#native.containers == 2)

-- Per-frame, master, and profile enablement all reuse and stop native groups.
set(options.player.args.enableGroup.args.enabled, false)
assert(not playerState.enabled and not p.anchor:IsShown())
set(options.player.args.enableGroup.args.enabled, true)
assert(playerState.enabled)
host:SetCombat(true)
set(options.enable, false)
assert(playerState.enabled)
host:SetCombat(false)
assert(not playerState.enabled and not targetState.enabled)
set(options.enable, true)
assert(playerState.enabled)
addon.db:SetProfile("Debuff test profile"); flush()
assert(not playerState.enabled and not targetState.enabled)
set(options.enable, true)
set(target.enabled, true)
assert(not playerState.enabled and targetState.enabled)
addon.db:CopyProfile(originalProfile); flush()
assert(playerState.enabled and not targetState.enabled and p.scaled.scale == 2)
host:SetCombat(true)
writes = native.writes
addon.db:SetProfile("Empty debuff profile"); flush()
assert(native.writes == writes and playerState.enabled)
host:SetCombat(false)
assert(not playerState.enabled and not targetState.enabled)
addon.db:SetProfile(originalProfile); flush()
assert(playerState.enabled and #native.containers == 2)

-- Copying a Focus configuration cannot leave missing debuff settings that
-- crash existing displays or controls. Enabling fills in shared defaults.
options.target.args.enableGroup.args.copyFrom.set(nil, "focus"); flush()
assert(target.iconSize.get() == addon.db.defaults.profile.ufConfig.target.debuffs.iconSize)
set(options.target.args.enableGroup.args.enabled, true)
set(target.enabled, true)
assert(targetState.enabled)

host:SetCombat(true)
frames:Disable(); flush()
assert(playerState.enabled and targetState.enabled)
host:SetCombat(false)
assert(not playerState.enabled and not targetState.enabled)
frames:Enable(); flush()
assert(playerState.enabled and targetState.enabled and #native.containers == 2)
addon.db:ResetProfile(); flush()
assert(not playerState.enabled and not targetState.enabled and not player.enabled.get() and not target.enabled.get())
host:AssertNoErrors()
print("SUCCESS: native player/target debuff groups, sizing, target swaps, combat deferral, batches, and profile lifecycle")

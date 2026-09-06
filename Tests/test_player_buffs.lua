-- The native contract deliberately forbids aura reads and post-init child writes.
-- It cannot certify native rendering or taint; those require in-game testing.
local host = assert(loadfile("Tests/support/wow.lua"))()
local native = assert(loadfile("Tests/support/aura_container.lua"))()(host)
local addon, ns = assert(loadfile("Tests/support/load_addon.lua"))()(host)
local buffs = addon:GetModule("PlayerBuffs")
local manager = addon:GetModule("LayoutManager")
local options = ns.Settings.BuildPlayerBuffsOptions(addon).args
local spells = options.spellIDsGroup.args
local sizing = options.sizingGroup.args
local function flush() host:Flush(); host:AssertNoErrors() end
local function setIDs(text) spells.spellIDs.set(nil, text); flush() end
local function enable(value) options.enable.set(nil, value); flush() end
assert(buffs:GetStatus() == "disabled" and not buffs._runtimeActive)
assert(not buffs:GetContainer() and #native.containers == 0, "disabled defaults must create no native frames")
local parsed = assert(buffs:ParseSpellIDs("184364, 871\n184364\t12975"))
assert(#parsed == 3 and parsed[1] == 184364 and parsed[2] == 871 and parsed[3] == 12975)
parsed = assert(buffs:ParseSpellIDs("97462,23920,97463,97462"))
assert(#parsed == 2 and parsed[1] == 97463 and parsed[2] == 23920,
	"cast aliases must resolve before deduplication, preserving first-slot order")
assert(#buffs:ParseSpellIDs(" \n") == 0)
for _, input in ipairs({ "0", "-1", "1.5", "abc", ",,", "2147483648" }) do
	local ids, err = buffs:ParseSpellIDs(input)
	assert(ids == nil and err == "invalid")
	assert(spells.spellIDs.validate(nil, input) ~= true)
end
local ids, err = buffs:ParseSpellIDs("1,2,3,4,5,6,7,8,9,10,11,12,13")
assert(not ids and err == "too_many")
assert(spells.spellIDs.validate(nil, "184364 871") == true)

-- Unsupported clients and empty lists stay inert, but users can edit settings.
local api = C_AuraContainerUtil
C_AuraContainerUtil = nil
assert(options.enable.disabled())
spells.spellIDs.set(nil, "23920"); flush()
assert(addon.db.profile.playerBuffsSpellIDs == "23920")
assert(not addon.db.profile.playerBuffsEnabled and #native.containers == 0)
enable(true)
assert(buffs:GetStatus() == "unavailable" and not buffs._runtimeActive)
C_AuraContainerUtil = api
setIDs("")
assert(buffs:GetStatus() == "empty" and #native.containers == 0)
setIDs("184364,871")
assert(buffs:GetStatus() == "active" and #native.containers == 1 and #native.slots == 2)
local container = buffs:GetContainer()
local state = native.containers[1]
assert(state.enabled and state.unit == "player")
assert(state.slots.selected1.filters.includeSpellIDs[184364])
assert(state.slots.selected2.filters.includeSpellIDs[871])
for _, slot in ipairs(native.slots) do
	assert(slot.icon and slot.cooldown and slot.count, "native slots need icon, duration and stack delegates")
end
assert(buffs:GetLayoutWidth() == 58 and buffs:CalculateHeight() == 28)
assert(container:IsShown() and not manager:IsModuleInStack("playerBuffs"))

-- Existing saved cast IDs and explicit aura IDs select the same native buff.
setIDs("97462,23920,97463")
assert(addon.db.profile.playerBuffsSpellIDs == "97462,23920,97463", "reads must not migrate saved text")
assert(state.slots.selected1.filters.includeSpellIDs[97463])
assert(not state.slots.selected1.filters.includeSpellIDs[97462])
assert(state.slots.selected2.filters.includeSpellIDs[23920] and #native.slots == 2)
setIDs("97463,23920")
assert(state.slots.selected1.filters.includeSpellIDs[97463])

-- Aura activity never invokes addon layout or queries native widget visibility.
local writes = native.writes
host:Fire("UNIT_AURA", "player"); flush()
assert(native.writes == writes and buffs:GetLayoutWidth() == 58)
sizing.iconSize.set(nil, 32)
sizing.columns.set(nil, 1); flush()
assert(buffs:GetLayoutWidth() == 32 and buffs:CalculateHeight() == 66)
assert(native.slots[1].anchor:GetWidth() == 32)
setIDs("12975")
assert(#native.slots == 2 and next(state.slots.selected2.filters.includeSpellIDs) == nil)
assert(state.slots.selected1.filters.includeSpellIDs[12975])
assert(buffs:CalculateHeight() == 32)
options.includeInStack.set(nil, true); flush()
assert(manager:IsModuleInStack("playerBuffs"))
local stackHeight = ActionHudFrame:GetHeight()
host:Fire("UNIT_AURA", "player"); flush()
assert(ActionHudFrame:GetHeight() == stackHeight, "buff expiration must not change reserved stack height")

-- Settings, profile switches, and newly needed slots all defer until combat ends.
host:SetCombat(true)
writes = native.writes
local frames = #host.frames
local oldWidth = container:GetWidth()
setIDs("97462 2 3")
sizing.iconSize.set(nil, 40)
options.resetPosition.func()
enable(false)
enable(true)
assert(native.writes == writes and #host.frames == frames and container:GetWidth() == oldWidth)
assert(buffs:GetStatus() == "pending")
host:SetCombat(false)
assert(buffs:GetStatus() == "active" and #native.slots == 3)
assert(buffs:GetLayoutWidth() == 40 and buffs:CalculateHeight() == 124)
assert(state.slots.selected3.filters.includeSpellIDs[3])
assert(state.slots.selected1.filters.includeSpellIDs[97463], "deferred filters must resolve cast IDs too")
enable(false)
assert(not state.enabled and not container:IsShown() and buffs:CalculateHeight() == 0)
enable(true)
assert(state.enabled and buffs:GetContainer() == container and #native.containers == 1 and #native.slots == 3)
local originalProfile = addon.db:GetCurrentProfile()
addon.db:SetProfile("empty-buff-profile"); flush()
assert(not state.enabled and not buffs._runtimeActive)
addon.db:SetProfile(originalProfile); flush()
assert(state.enabled and #native.slots == 3)
spells.clearSpellIDs.func(); flush()
assert(buffs:GetStatus() == "empty" and not state.enabled and not container:IsShown())

-- The catalog supplies all public associated IDs to one native slot. Changes
-- from spec/hotfix events refresh filters only after combat, without child reads.
local getCandidates, refreshCatalog = ns.BlizzardBuffCatalog.GetCandidateSpellIDs, ns.BlizzardBuffCatalog.Refresh
local linkedID, catalogRefreshes = 200002, 0
function ns.BlizzardBuffCatalog:GetCandidateSpellIDs(id)
	if id == 200001 then return { [200001] = true, [linkedID] = true, [97462] = true } end
end
function ns.BlizzardBuffCatalog:Refresh() catalogRefreshes = catalogRefreshes + 1 end
setIDs("200001")
assert(state.slots.selected1.filters.includeSpellIDs[200001] and state.slots.selected1.filters.includeSpellIDs[200002])
assert(state.slots.selected1.filters.includeSpellIDs[97463] and not state.slots.selected1.filters.includeSpellIDs[97462])
host:SetCombat(true)
writes = native.writes
linkedID = 200003
host:Fire("COOLDOWN_VIEWER_TABLE_HOTFIXED"); flush()
assert(catalogRefreshes == 1 and native.writes == writes)
host:SetCombat(false)
assert(state.slots.selected1.filters.includeSpellIDs[200003] and not state.slots.selected1.filters.includeSpellIDs[200002])
ns.BlizzardBuffCatalog.GetCandidateSpellIDs, ns.BlizzardBuffCatalog.Refresh = getCandidates, refreshCatalog

-- Real AceEvent/router integration: discovery persists actual IDs independently
-- of display enablement and never causes native rendering writes or layout.
local recent = ns.RecentPlayerBuffs
local secretsAPI, aurasAPI = C_Secrets, C_UnitAuras
local observed, scans = { { spellId = 132404 } }, 0
C_Secrets = { ShouldAurasBeSecret = function() return host.combat end }
C_UnitAuras = {
	GetUnitAuras = function(unit, filter)
		assert(not host.combat and unit == "player" and filter == "HELPFUL")
		scans = scans + 1
		return observed
	end,
	AuraIsPrivate = function() return false end,
}
enable(false)
writes = native.writes
host:Fire("UNIT_AURA", "target"); flush()
assert(scans == 0)
host:Fire("UNIT_AURA", "player"); flush()
assert(scans == 1 and addon.db.char.playerBuffRecentIDs[1] == 132404)
assert(native.writes == writes and not buffs._runtimeActive, "discovery must not drive native rendering")
host:SetCombat(true)
observed = { { spellId = 23920 } }
host:Fire("UNIT_AURA", "player"); flush()
assert(scans == 1 and recent:GetEntries()[1].id == 132404)
host:SetCombat(false)
assert(scans == 2 and recent:GetEntries()[1].id == 23920)
recent:Disable()
host:Fire("UNIT_AURA", "player"); flush()
assert(scans == 2, "Ace disable must release the discovery router")
C_Secrets, C_UnitAuras = secretsAPI, aurasAPI
recent:Enable(); flush()
enable(true)

-- A swallowed native initialization error must not report a working display or
-- repeatedly allocate broken slots on subsequent layout passes.
native.failInitialization = true
setIDs("1 2 3 4")
assert(buffs:GetStatus() == "error" and not buffs._runtimeActive and not state.enabled)
assert(not container:IsShown() and buffs:CalculateHeight() == 0)
frames = #host.frames
addon:RefreshLayout(); flush()
enable(false); enable(true)
assert(buffs:GetStatus() == "error" and #host.frames == frames)
host:AssertNoErrors()
print("player buff native contract and lifecycle tests passed")

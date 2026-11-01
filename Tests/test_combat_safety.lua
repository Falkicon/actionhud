-- Full-TOC combat safety: every settings control must be usable in combat
-- without mutating protected frames, and Blizzard unit frames are only
-- changed when ActionHud hides them.
local host = assert(loadfile("Tests/support/wow.lua"))()
local native = assert(loadfile("Tests/support/aura_container.lua"))()(host)
local boot = assert(loadfile("Tests/support/load_addon.lua"))()

-- Blizzard's unit frames are secure; record every visibility change.
local blizzard = {}
for _, name in ipairs({ "PlayerFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT" }) do
	local frame = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
	frame.alpha, frame.mouseEnabled = "other addon", "other addon"
	frame.SetAlpha = function(self, alpha)
		assert(not host.combat, "protected mutation in combat: " .. name)
		self.alpha = alpha
	end
	blizzard[name] = frame
end

-- Trinket cooldowns that become restricted must never reach SetCooldown.
local secretValues = {}
local function forbidden() error("trinket cooldown secret inspected") end
-- Userdata tokens, like native secrets, are not mistaken for legacy info tables.
local function secret()
	local token = newproxy(true)
	local meta = getmetatable(token)
	meta.__lt, meta.__le, meta.__add, meta.__sub, meta.__eq, meta.__concat =
		forbidden, forbidden, forbidden, forbidden, forbidden, forbidden
	secretValues[token] = true
	return token
end
issecretvalue = function(value) return secretValues[value] == true end
local trinketCooldown = { 10, 20, true }
GetInventoryItemCooldown = function() return trinketCooldown[1], trinketCooldown[2], trinketCooldown[3] end

local addon = boot(host)
host:Flush()
for name, frame in pairs(blizzard) do
	assert(frame.alpha == "other addon" and frame.mouseEnabled == "other addon",
		name .. " must be left alone while ActionHud has not hidden it")
end

local profile = addon.db.profile
profile.ufEnabled, profile.ufHideBlizzard = true, true
profile.ufConfig.player.debuffs.enabled, profile.ufConfig.target.debuffs.enabled = true, true
profile.consumablesEnabled, profile.playerBuffsEnabled, profile.trinketsEnabled = true, true, true
addon:OnProfileChanged()
host:Flush()
assert(blizzard.PlayerFrame.alpha == 0 and blizzard.PlayerFrame.mouseEnabled == false)
assert(blizzard.TargetFrame.alpha == 0, "enabled custom frames hide their Blizzard frame")
assert(blizzard.FocusFrame.alpha == "other addon" and blizzard.TargetFrameToT.alpha == "other addon",
	"Blizzard frames stay visible when their custom frame is disabled")

-- Trinket cooldowns: readable values reach the sweep; restricted ones clear it.
local trinket
for _, frame in ipairs(host.frames) do
	if frame.slot == 13 and frame.cooldown then trinket = frame end
end
assert(trinket, "trinket slot 13 must be displayed")
trinket.cooldown.SetCooldown = function(self, start, duration)
	assert(not secretValues[start] and not secretValues[duration], "secret values must not reach SetCooldown")
	self.start, self.duration = start, duration
end
trinket.cooldown.Clear = function(self) self.cleared = true end
host:Fire("SPELL_UPDATE_COOLDOWN")
assert(trinket.cooldown.start == 10 and trinket.cooldown.duration == 20, "readable trinket cooldowns show a sweep")
trinketCooldown = { secret(), secret(), secret() }
host:Fire("SPELL_UPDATE_COOLDOWN")
assert(trinket.cooldown.cleared, "restricted trinket cooldowns clear the sweep")
trinketCooldown = { 0, 0, true }

-- Call every settings control while in combat.
local registry = LibStub("AceConfigRegistry-3.0")
local apps = { "ActionHud", "ActionHud_Layout", "ActionHud_AB", "ActionHud_Res", "ActionHud_UnitFrames",
	"ActionHud_Trinkets", "ActionHud_Consumables", "ActionHud_PlayerBuffs" }
local failures, calls = {}, 0
local function call(path, fn, ...)
	calls = calls + 1
	local nativeWrites = native.writes
	host.combat = true
	local ok, err = pcall(fn, ...)
	host.combat = false
	if not ok then failures[#failures + 1] = path .. ": " .. tostring(err) end
	if native.writes ~= nativeWrites then failures[#failures + 1] = path .. ": native aura write in combat" end
	for _, message in ipairs(host.errors) do failures[#failures + 1] = path .. ": " .. message end
	host.errors = {}
end
local function isOn(value, info)
	if type(value) == "function" then return value(info) end
	return value == true
end
local function walk(group, path)
	local keys = {}
	for key in pairs(group.args or {}) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local option, here = group.args[key], path .. "." .. key
		local info = { option }
		if option.type == "group" then
			walk(option, here)
		elseif option.type == "toggle" and type(option.set) == "function" then
			call(here, option.set, info, not (type(option.get) == "function" and option.get(info)))
		elseif option.type == "range" and type(option.set) == "function" then
			call(here, option.set, info, option.max or 1)
		elseif option.type == "select" and type(option.set) == "function" then
			local values = type(option.values) == "function" and option.values(info) or option.values
			local first
			for value in pairs(values or {}) do
				if value ~= "" then first = value; break end
			end
			if first ~= nil then call(here, option.set, info, first) end
		elseif option.type == "execute" and type(option.func) == "function"
			and not isOn(option.disabled, info) and not isOn(option.hidden, info) then
			call(here, option.func, info)
		end
	end
end
for _, app in ipairs(apps) do
	walk(registry:GetOptionsTable(app)("dialog", "CombatSweep-1.0"), app)
end
assert(calls > 300, "the sweep must reach the settings controls")
assert(#failures == 0, "settings controls failed in combat:\n" .. table.concat(failures, "\n"))
host:SetCombat(false)
host:Flush()
host:AssertNoErrors()

-- A Hide Blizzard Frames change made in combat applies after combat, and
-- restores only the frames ActionHud hid.
profile.ufEnabled, profile.ufHideBlizzard = true, true
profile.ufConfig.player.enabled, profile.ufConfig.focus.enabled = true, false
addon:OnProfileChanged()
host:Flush()
assert(blizzard.PlayerFrame.alpha == 0)
blizzard.FocusFrame.alpha = "other addon"
local hideOption = registry:GetOptionsTable("ActionHud_UnitFrames")("dialog", "CombatSweep-1.0").args.hideBlizzard
host:SetCombat(true)
hideOption.set({ hideOption }, false)
assert(blizzard.PlayerFrame.alpha == 0, "protected Blizzard frames must not change in combat")
host:SetCombat(false)
host:Flush()
assert(blizzard.PlayerFrame.alpha == 1 and blizzard.PlayerFrame.mouseEnabled == true,
	"the Blizzard frame ActionHud hid is restored after combat")
assert(blizzard.FocusFrame.alpha == "other addon", "frames ActionHud never hid are not restored")

host:AssertNoErrors()
print("SUCCESS: " .. calls .. " settings controls in combat, Blizzard frame ownership, and trinket cooldown safety")

--[[
	ActionHud - Utils Unit Tests
	Verifies clean-load FenUI capability initialization and Midnight action APIs.
	Run from addon root: lua Tests/test_utils.lua
]]

_G = _G or {}
unpack = unpack or table.unpack

local function loadFromRoot(path, ...)
	local chunk, err = loadfile(path)
	if not chunk then
		chunk, err = loadfile("../" .. path)
	end
	if not chunk then
		error(err)
	end
	return chunk(...)
end

local function assertEqual(expected, actual, message)
	if expected ~= actual then
		error(string.format("%s\nExpected: '%s'\nActual:   '%s'", message or "Fail", tostring(expected), tostring(actual)))
	end
end

local function assertTrue(actual, message)
	assertEqual(true, actual, message)
end

-- Mock the WoW environment before the embedded FenUI utility loader runs.
GetBuildInfo = function()
	return "12.1.0", "70000", "Aug 10 2026", 120100
end
GetTime = function()
	return 1000
end
wipe = function(target)
	for key in pairs(target) do
		target[key] = nil
	end
end

local formatterCreations = 0
C_StringUtil = {
	CreateSecondsFormatter = function()
		formatterCreations = formatterCreations + 1
		return {
			SetMinimumComponents = function() end,
			Format = function(_, seconds)
				return "native:" .. tostring(seconds)
			end,
		}
	end,
}
CreateSecondsFormatter = nil -- Current clients expose this through C_StringUtil.
SecondsFormatter = nil -- The old capability check incorrectly depended on this global.

local secretValues = {}
issecretvalue = function(value)
	return secretValues[value] == true
end

print("Loading embedded FenUI utilities...")
FenCore = nil
FenUI = {}
loadFromRoot("Libs/FenUI/Utils/Utils.lua")
loadFromRoot("Libs/FenUI/Utils/Formatting.lua")
loadFromRoot("Libs/FenUI/Utils/SafeAPI.lua")

local FenUtils = FenUI.Utils
assertTrue(FenUtils.IS_MIDNIGHT, "Embedded FenUI did not initialize Midnight state")
assertTrue(type(FenUtils.Cap) == "table", "Embedded FenUI did not initialize its capability table")
assertTrue(FenUtils.Cap.HasSecondsFormatter, "CreateSecondsFormatter capability was not detected")
assertTrue(FenUtils.Cap.IsRoyal, "Midnight interpretive API capability was not detected")

local actionCalls = {}
C_ActionBar = {
	GetActionCooldown = function(actionID)
		actionCalls.cooldown = actionID
		if actionID == 999 then
			error("Attempt to access secret action cooldown")
		end
		return { startTime = 100, duration = 30, isEnabled = true, modRate = 1 }
	end,
	GetActionBarPage = function()
		actionCalls.page = true
		return 1
	end,
	GetBonusBarOffset = function()
		actionCalls.bonus = true
		return 3
	end,
	GetActionInfo = function(actionID)
		actionCalls.info = actionID
		return { type = "spell", id = 12345, subType = "spell" }
	end,
	GetActionTexture = function(actionID)
		actionCalls.texture = actionID
		return 98765
	end,
	GetActionDisplayCount = function(actionID)
		actionCalls.count = actionID
		return 4
	end,
	IsUsableAction = function(actionID)
		actionCalls.usable = actionID
		return { isUsable = false, notEnoughMana = false }
	end,
	IsActionInRange = function(actionID)
		actionCalls.range = actionID
		return false
	end,
}
C_Item = {
	GetItemCooldown = function(itemID)
		assertEqual(24680, itemID, "C_Item.GetItemCooldown received the wrong item ID")
		return 200, 45, true
	end,
}
GetInventoryItemID = function(unit, slot)
	assertEqual("player", unit, "GetInventoryItemID received the wrong unit")
	assertEqual(13, slot, "GetInventoryItemID received the wrong slot")
	return 24680
end

-- Removed globals stay absent so any accidental legacy call fails the assertions.
GetActionCooldown = nil
GetActionBarPage = nil
GetBonusBarOffset = nil
GetActionInfo = nil
GetActionTexture = nil
GetActionCount = nil
IsUsableAction = nil
IsActionInRange = nil
GetInventoryItemCooldown = nil

print("Loading ActionHud Utils.lua...")
local ns = {}
loadFromRoot("Utils.lua", "ActionHud", ns)
local Utils = ns.Utils

print("Running Utils tests...")
assertTrue(Utils.IS_MIDNIGHT, "ActionHud did not inherit Midnight state")
assertTrue(Utils.Cap.HasSecondsFormatter, "ActionHud did not inherit formatter capability")

local actionType, actionID, subType = Utils.GetActionInfoSafe(1)
assertEqual("spell", actionType, "C_ActionBar.GetActionInfo type was not normalized")
assertEqual(12345, actionID, "C_ActionBar.GetActionInfo ID was not normalized")
assertEqual("spell", subType, "C_ActionBar.GetActionInfo subtype was not normalized")
assertEqual(1, actionCalls.info, "C_ActionBar.GetActionInfo was not called")

assertEqual(1, Utils.GetActionBarPageSafe(), "C_ActionBar.GetActionBarPage was not used")
assertEqual(3, Utils.GetBonusBarOffsetSafe(), "C_ActionBar.GetBonusBarOffset was not used")
assertEqual(98765, Utils.GetActionTextureSafe(1), "C_ActionBar.GetActionTexture was not used")
assertEqual(4, Utils.GetActionDisplayCountSafe(1), "C_ActionBar.GetActionDisplayCount was not used")

local usable, noMana = Utils.IsUsableActionSafe(1)
assertEqual(false, usable, "C_ActionBar.IsUsableAction false result was lost")
assertEqual(false, noMana, "C_ActionBar.IsUsableAction mana result failed")
assertEqual(false, Utils.IsActionInRangeSafe(1), "C_ActionBar.IsActionInRange false result was lost")

local itemStart, itemDuration, itemEnabled = Utils.GetInventoryItemCooldownSafe("player", 13)
assertEqual(200, itemStart, "C_Item.GetItemCooldown start time failed")
assertEqual(45, itemDuration, "C_Item.GetItemCooldown duration failed")
assertEqual(true, itemEnabled, "C_Item.GetItemCooldown enabled flag failed")

local startTime, duration, enabled, modRate = Utils.GetActionCooldownSafe(1)
assertEqual(100, startTime, "C_ActionBar.GetActionCooldown start time failed")
assertEqual(30, duration, "C_ActionBar.GetActionCooldown duration failed")
assertEqual(true, enabled, "C_ActionBar.GetActionCooldown enabled failed")
assertEqual(1, modRate, "C_ActionBar.GetActionCooldown mod rate failed")

local failedStart, failedDuration, failedEnabled, failedModRate = Utils.GetActionCooldownSafe(999)
assertEqual(0, failedStart, "Action cooldown error start fallback failed")
assertEqual(0, failedDuration, "Action cooldown error duration fallback failed")
assertEqual(false, failedEnabled, "Action cooldown error enabled fallback failed")
assertEqual(1, failedModRate, "Action cooldown error mod rate fallback failed")

assertEqual("native:12.5", Utils.FormatDurationSafe(12.5), "Native seconds formatter was not used")
assertEqual(1, formatterCreations, "Seconds formatter should be created once")
assertEqual("native:5", Utils.FormatDurationSafe(5), "Cached seconds formatter failed")
assertEqual(1, formatterCreations, "Seconds formatter was not cached")

local normalValue = 100
local secretValue = { isSecret = true }
secretValues[secretValue] = true
assertEqual(false, Utils.IsValueSecret(normalValue), "Normal value identified as secret")
assertEqual(true, Utils.IsValueSecret(secretValue), "Secret value not identified")
assertEqual(true, Utils.SafeCompare(10, 5, ">"), "SafeCompare numeric comparison failed")
assertEqual(false, Utils.SafeCompare(secretValue, 10, ">"), "SafeCompare secret fallback failed")

local cooldownFrame = {
	SetCooldown = function(self, start, duration)
		self.start = start
		self.duration = duration
	end,
}
FenUtils:SetCooldownSafe(cooldownFrame, secretValue, secretValue)
assertEqual(secretValue, cooldownFrame.start, "Restricted cooldown start was not passed through")
assertEqual(secretValue, cooldownFrame.duration, "Restricted cooldown duration was not passed through")

print("SUCCESS: Utils module verified!")

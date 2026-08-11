--[[
    ActionHud - Unit-frame identity safety tests
    Run from addon root: lua Tests/test_unitframe_identity.lua
]]

_G = _G or {}

local secretValue = setmetatable({}, {
	__eq = function()
		error("a restricted identity value was compared")
	end,
})

local ns = {
	Utils = {
		IsValueSecret = function(value)
			return rawequal(value, secretValue)
		end,
	},
}

local actionHud = {}
function actionHud:NewModule()
	return {}
end

LibStub = function(name)
	if name == "AceAddon-3.0" then
		return {
			GetAddon = function()
				return actionHud
			end,
		}
	elseif name == "AceLocale-3.0" then
		return {
			GetLocale = function()
				return {}
			end,
		}
	elseif name == "LibSharedMedia-3.0" then
		return {
			Fetch = function()
				return nil
			end,
		}
	end
	error("unexpected library: " .. tostring(name))
end

Enum = {
	SummonStatus = {
		Pending = 1,
		Accepted = 2,
		Declined = 3,
	},
}

local apiValues = {}
UnitAffectingCombat = function()
	return apiValues.combat
end
IsResting = function()
	return apiValues.resting
end
UnitIsPVP = function()
	return apiValues.pvp
end
UnitFactionGroup = function()
	return apiValues.faction
end
UnitIsGroupLeader = function()
	return apiValues.leader
end
UnitGroupRolesAssigned = function()
	return apiValues.role
end
UnitIsGroupAssistant = function()
	return apiValues.guide
end
GetPartyAssignment = function(assignment)
	return apiValues[assignment]
end
UnitInVehicle = function()
	return apiValues.vehicle
end
UnitPhaseReason = function()
	return apiValues.phase
end
GetReadyCheckStatus = function()
	return apiValues.readyCheck
end
UnitPowerType = function()
	return 0, apiValues.powerToken, apiValues.altR, apiValues.altG, apiValues.altB
end
UnitIsPlayer = function()
	return apiValues.isPlayer
end
UnitClass = function()
	return "Mage", apiValues.class
end
UnitIsEnemy = function()
	return apiValues.isEnemy
end
UnitIsFriend = function()
	return apiValues.isFriend
end

C_IncomingSummon = {
	IncomingSummonStatus = function()
		return apiValues.summon
	end,
}

RAID_CLASS_COLORS = {
	MAGE = { r = 0.25, g = 0.5, b = 0.75 },
}
PowerBarColor = {
	MANA = { r = 0, g = 0, b = 1 },
}

local function readUnitFrames()
	local path = "UnitFrames/UnitFrames.lua"
	local file = io.open(path, "r")
	if not file then
		path = "../UnitFrames/UnitFrames.lua"
		file = assert(io.open(path, "r"))
	end
	local source = file:read("*a")
	file:close()
	return path, source
end

local path, source = readUnitFrames()
local loadChunk = loadstring or load
local chunk, loadError = loadChunk(source, path)
assert(chunk, loadError)
chunk("ActionHud", ns)

local IdentitySafety = assert(ns.UnitFrameIdentitySafety)

AbbreviateNumbers = function(value)
	return "abbr:" .. tostring(value)
end

local function resetApiValues()
	for key in pairs(apiValues) do
		apiValues[key] = nil
	end
end

local function assertEqual(expected, actual, message)
	if not rawequal(expected, actual) then
		error(string.format("%s\nExpected: %s\nActual: %s", message, tostring(expected), tostring(actual)))
	end
end

local function assertContains(text, pattern, message)
	if not text:find(pattern, 1, true) then
		error(message)
	end
end

local function assertNotContains(text, pattern, message)
	if text:find(pattern, 1, true) then
		error(message .. ": " .. pattern)
	end
end

print("Running unit-frame identity safety tests...")

assertEqual(secretValue, IdentitySafety.FormatValue(secretValue), "restricted values must pass directly to FontString")
assertEqual("abbr:1234", IdentitySafety.FormatValue(1234), "ordinary values must still be abbreviated")
assertEqual("???", IdentitySafety.FormatValue(nil), "missing values must retain their placeholder")

local filtered, available = IdentitySafety.Get(secretValue)
assertEqual(nil, filtered, "restricted values must be filtered")
assertEqual(false, available, "restricted values must be marked unavailable")

local truthy, truthyAvailable = IdentitySafety.IsTruthy(secretValue)
assertEqual(false, truthy, "restricted values must not become truthy")
assertEqual(false, truthyAvailable, "restricted truthiness must be unavailable")

local iconIds = {
	"combat",
	"resting",
	"pvp",
	"leader",
	"role",
	"guide",
	"mainTank",
	"mainAssist",
	"vehicle",
	"phased",
	"summon",
	"readyCheck",
}

for _, key in ipairs({
	"combat",
	"resting",
	"pvp",
	"faction",
	"leader",
	"role",
	"guide",
	"MAINTANK",
	"MAINASSIST",
	"vehicle",
	"phase",
	"summon",
	"readyCheck",
}) do
	apiValues[key] = secretValue
end

for _, iconId in ipairs(iconIds) do
	local show = IdentitySafety.GetStatusIconState(iconId, "player", false)
	assertEqual(false, show, iconId .. " must hide when its identity result is restricted")
	local forcedShow = IdentitySafety.GetStatusIconState(iconId, "player", true)
	assertEqual(true, forcedShow, iconId .. " must preserve the independent show-all setting")
end

resetApiValues()
apiValues.pvp = true
apiValues.faction = "Horde"
local showPvp, pvpTexture = IdentitySafety.GetStatusIconState("pvp", "target", false)
assertEqual(true, showPvp, "unrestricted PvP state must still show")
assertContains(pvpTexture, "Horde", "unrestricted faction must select its existing texture")

apiValues.role = "DAMAGER"
local showRole, _, roleCoord = IdentitySafety.GetStatusIconState("role", "target", false)
assertEqual(true, showRole, "unrestricted role must still show")
assertEqual(0.3, roleCoord[1], "unrestricted damage role texture coordinates changed")
assertEqual(0.59375, roleCoord[2], "unrestricted damage role texture coordinates changed")
local _, _, repeatedRoleCoord = IdentitySafety.GetStatusIconState("role", "target", false)
assertEqual(roleCoord, repeatedRoleCoord, "status icon updates should reuse texture-coordinate tables")

apiValues.summon = Enum.SummonStatus.Accepted
local showSummon, summonTexture = IdentitySafety.GetStatusIconState("summon", "target", false)
assertEqual(true, showSummon, "unrestricted accepted summon must still show")
assertContains(summonTexture, "Accepted", "accepted summon texture changed")

apiValues.readyCheck = "notready"
local showReady, readyTexture = IdentitySafety.GetStatusIconState("readyCheck", "target", false)
assertEqual(true, showReady, "unrestricted ready-check state must still show")
assertContains(readyTexture, "NotReady", "not-ready texture changed")

resetApiValues()
apiValues.powerToken = "MANA"
local hasSecondary, powerAvailable = IdentitySafety.HasSecondaryPower("player")
assertEqual(false, hasSecondary, "primary resources must not create a class bar")
assertEqual(true, powerAvailable, "unrestricted power tokens must remain available")

apiValues.powerToken = "COMBO_POINTS"
hasSecondary, powerAvailable = IdentitySafety.HasSecondaryPower("player")
assertEqual(true, hasSecondary, "secondary resources must still create a class bar")
assertEqual(true, powerAvailable, "unrestricted secondary resources must remain available")

apiValues.powerToken = secretValue
hasSecondary, powerAvailable = IdentitySafety.HasSecondaryPower("player")
assertEqual(false, hasSecondary, "restricted power tokens must not create a class bar")
assertEqual(false, powerAvailable, "restricted power tokens must be marked unavailable")

resetApiValues()
apiValues.isPlayer = true
apiValues.class = secretValue
setmetatable(RAID_CLASS_COLORS, {
	__index = function()
		error("restricted class was used as a table key")
	end,
})
local r, g, b = IdentitySafety.GetUnitColor("target", "HEALTH", 1)
assertEqual(0, r, "restricted class fallback red changed")
assertEqual(0.8, g, "restricted class fallback green changed")
assertEqual(0, b, "restricted class fallback blue changed")

resetApiValues()
apiValues.powerToken = secretValue
setmetatable(PowerBarColor, {
	__index = function()
		error("restricted power token was used as a table key")
	end,
})
r, g, b = IdentitySafety.GetUnitColor("target", "POWER", 1)
assertEqual(0, r, "restricted power fallback red changed")
assertEqual(0, g, "restricted power fallback green changed")
assertEqual(0.8, b, "restricted power fallback blue changed")

for _, unsafePattern in ipairs({
	"show = show or UnitIsPVP",
	"show = show or UnitIsGroupLeader",
	"show = show or UnitIsGroupAssistant",
	"show = show or UnitPhaseReason",
	"local role = UnitGroupRolesAssigned",
}) do
	assertNotContains(source, unsafePattern, "direct identity composition returned")
end

assertContains(source, 'self:UpdateFrameValues(f, "status")', "status events must use their targeted update path")
assertContains(source, 'updateKind == "powerLayout"', "power layout events must remain separated from power ticks")

print("SUCCESS: unit-frame identity values are filtered before use")

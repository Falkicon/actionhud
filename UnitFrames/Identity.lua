-- Restricted identity normalization, status icon decisions, and display formatting.
local addonName, ns = ...
local Utils = ns.Utils

-- Unit identity APIs may return restricted values in 12.1 instances. Keep every
-- comparison, boolean conversion, and table lookup behind this guard. Exposing
-- the helper on the addon namespace also lets the focused Lua test exercise the
-- same resolver used in game.
local IdentitySafety = {}
ns.UnitFrameIdentitySafety = IdentitySafety

function IdentitySafety.Get(value)
	if Utils.IsValueSecret(value) then
		return nil, false
	end
	return value, true
end

function IdentitySafety.IsTruthy(value)
	local safeValue, isSafe = IdentitySafety.Get(value)
	if not isSafe then
		return false, false
	end
	return not not safeValue, true
end

local function PromoteIfTruthy(current, value)
	local active, isSafe = IdentitySafety.IsTruthy(value)
	if isSafe and active then
		return true
	end
	return current
end

local ICON_TEXCOORDS = {
	combat = { 0.5, 1.0, 0, 0.49 },
	resting = { 0, 0.5, 0, 0.49 },
	roleTank = { 0, 0.3, 0.3, 0.65 },
	roleHealer = { 0.3, 0.59375, 0, 0.3 },
	roleDamage = { 0.3, 0.59375, 0.3, 0.65 },
}

function IdentitySafety.HasSecondaryPower(unit)
	local _, rawPowerToken = UnitPowerType(unit)
	local powerToken, isSafe = IdentitySafety.Get(rawPowerToken)
	if not isSafe then
		return false, false
	end
	if powerToken == nil then
		return false, true
	end
	return powerToken ~= "MANA" and powerToken ~= "RAGE" and powerToken ~= "FOCUS" and powerToken ~= "ENERGY", true
end

function IdentitySafety.GetUnitColor(unit, barType, mult)
	mult = mult or 1
	if barType == "HEALTH" then
		local isPlayer, playerIdentityAvailable = IdentitySafety.IsTruthy(UnitIsPlayer(unit))
		if not playerIdentityAvailable then
			return 0.5 * mult, 0.5 * mult, 0.5 * mult
		end
		if isPlayer then
			local _, rawClass = UnitClass(unit)
			local class, classAvailable = IdentitySafety.Get(rawClass)
			if classAvailable and class ~= nil then
				local classColor = RAID_CLASS_COLORS[class]
				if classColor then
					return classColor.r * mult, classColor.g * mult, classColor.b * mult
				end
			end
			return 0, 0.8 * mult, 0
		end

		local isEnemy, enemyIdentityAvailable = IdentitySafety.IsTruthy(UnitIsEnemy("player", unit))
		if not enemyIdentityAvailable then
			return 0.5 * mult, 0.5 * mult, 0.5 * mult
		end
		if isEnemy then
			return 0.8 * mult, 0, 0
		end

		local isFriend, friendIdentityAvailable = IdentitySafety.IsTruthy(UnitIsFriend("player", unit))
		if not friendIdentityAvailable then
			return 0.5 * mult, 0.5 * mult, 0.5 * mult
		end
		if isFriend then
			return 0, 0.8 * mult, 0
		end
		return 0.8 * mult, 0.8 * mult, 0
	elseif barType == "POWER" or barType == "MANA" then
		local _, rawPowerToken, rawAltR, rawAltG, rawAltB = UnitPowerType(unit)
		local powerToken, tokenAvailable = IdentitySafety.Get(rawPowerToken)
		if tokenAvailable and powerToken ~= nil then
			local info = PowerBarColor[powerToken]
			if info then
				return info.r * mult, info.g * mult, info.b * mult
			end
		end

		local altR, altRAvailable = IdentitySafety.Get(rawAltR)
		local altG, altGAvailable = IdentitySafety.Get(rawAltG)
		local altB, altBAvailable = IdentitySafety.Get(rawAltB)
		if altRAvailable and altGAvailable and altBAvailable and altR ~= nil then
			return altR * mult, altG * mult, altB * mult
		end
		return 0, 0, 0.8 * mult
	end
	return 1, 1, 1
end

function IdentitySafety.GetStatusIconState(iconId, unit, showAllIcons)
	local show = showAllIcons == true
	local texture
	local texCoord

	if iconId == "combat" then
		show = PromoteIfTruthy(show, UnitAffectingCombat(unit))
		texture = "Interface\\CharacterFrame\\UI-StateIcon"
		texCoord = ICON_TEXCOORDS.combat
	elseif iconId == "resting" then
		if unit == "player" then
			show = PromoteIfTruthy(show, IsResting())
		end
		texture = "Interface\\CharacterFrame\\UI-StateIcon"
		texCoord = ICON_TEXCOORDS.resting
	elseif iconId == "pvp" then
		show = PromoteIfTruthy(show, UnitIsPVP(unit))
		local rawFaction = UnitFactionGroup(unit)
		local faction, factionAvailable = IdentitySafety.Get(rawFaction)
		if factionAvailable and faction == "Horde" then
			texture = "Interface\\PVPFrame\\PVP-Currency-Horde"
		else
			texture = "Interface\\PVPFrame\\PVP-Currency-Alliance"
		end
	elseif iconId == "leader" then
		show = PromoteIfTruthy(show, UnitIsGroupLeader(unit))
		texture = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
	elseif iconId == "role" then
		local rawRole = UnitGroupRolesAssigned(unit)
		local role, roleAvailable = IdentitySafety.Get(rawRole)
		texture = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
		if roleAvailable and role == "TANK" then
			show = true
			texCoord = ICON_TEXCOORDS.roleTank
		elseif roleAvailable and role == "HEALER" then
			show = true
			texCoord = ICON_TEXCOORDS.roleHealer
		elseif roleAvailable and role == "DAMAGER" then
			show = true
			texCoord = ICON_TEXCOORDS.roleDamage
		else
			texCoord = ICON_TEXCOORDS.roleTank
		end
	elseif iconId == "guide" then
		show = PromoteIfTruthy(show, UnitIsGroupAssistant(unit))
		texture = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
	elseif iconId == "mainTank" then
		show = PromoteIfTruthy(show, GetPartyAssignment("MAINTANK", unit))
		texture = "Interface\\GroupFrame\\UI-Group-MainTankIcon"
	elseif iconId == "mainAssist" then
		show = PromoteIfTruthy(show, GetPartyAssignment("MAINASSIST", unit))
		texture = "Interface\\GroupFrame\\UI-Group-MainAssistIcon"
	elseif iconId == "vehicle" then
		show = PromoteIfTruthy(show, UnitInVehicle(unit))
		texture = "Interface\\Vehicles\\UI-Vehicles-Raid-Icon"
	elseif iconId == "phased" then
		show = PromoteIfTruthy(show, UnitPhaseReason(unit))
		texture = "Interface\\TargetingFrame\\UI-PhasingIcon"
	elseif iconId == "summon" then
		texture = "Interface\\RaidFrame\\Raid-Icon-SummonPending"
		if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
			local rawStatus = C_IncomingSummon.IncomingSummonStatus(unit)
			local status, statusAvailable = IdentitySafety.Get(rawStatus)
			if statusAvailable and status == Enum.SummonStatus.Pending then
				show = true
			elseif statusAvailable and status == Enum.SummonStatus.Accepted then
				show = true
				texture = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted"
			elseif statusAvailable and status == Enum.SummonStatus.Declined then
				show = true
				texture = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined"
			end
		elseif C_IncomingSummon and C_IncomingSummon.HasIncomingSummon then
			show = PromoteIfTruthy(show, C_IncomingSummon.HasIncomingSummon(unit))
		end
	elseif iconId == "readyCheck" then
		local rawStatus = GetReadyCheckStatus(unit)
		local status, statusAvailable = IdentitySafety.Get(rawStatus)
		texture = "Interface\\RaidFrame\\ReadyCheck-Ready"
		if statusAvailable and status == "ready" then
			show = true
		elseif statusAvailable and status == "notready" then
			show = true
			texture = "Interface\\RaidFrame\\ReadyCheck-NotReady"
		elseif statusAvailable and status == "waiting" then
			show = true
			texture = "Interface\\RaidFrame\\ReadyCheck-Waiting"
		end
	end

	return show, texture, texCoord
end

-- Format large numbers (1000 -> 1K) safely
function IdentitySafety.FormatValue(val)
	if type(val) == "nil" then
		return "???"
	end
	if Utils.IsValueSecret(val) then
		return val
	end

	-- If it's a number, we can use AbbreviateNumbers
	if type(val) == "number" then
		local ok, res = pcall(AbbreviateNumbers, val)
		if ok then
			return res
		end
		local stringifyOk, text = pcall(tostring, val)
		if stringifyOk then
			return text
		end
		return "???"
	end

	-- If it's a secret value, AbbreviateNumbers might crash.
	-- We return it as-is for %s formatting later.
	return val
end

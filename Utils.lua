local addonName, ns = ...

ns.Utils = {}
local Utils = ns.Utils

-- Delegation chain: FenCore.Secrets > FenUI.Utils > built-in fallback
local Secrets = FenCore and FenCore.Secrets
local Environment = FenCore and FenCore.Environment
local F = FenUI and FenUI.Utils

-- Local upvalues for performance
local GetTime = GetTime
local pcall = pcall
local wipe = wipe
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitPowerType = UnitPowerType
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local PowerBarColor = PowerBarColor

--------------------------------------------------------------------------------
-- Environment & Capability
--------------------------------------------------------------------------------

-- Use FenCore.Environment if available, else FenUI, else detect locally
Utils.IS_MIDNIGHT = (Environment and Environment.IsMidnight())
	or (F and F.IS_MIDNIGHT)
	or (((select(4, GetBuildInfo())) or 0) >= 120000)

Utils.Cap = F and F.Cap or {}

if not F then
	-- Fallback detection if FenUI is missing
	function Utils.DetectCapabilities()
		local Cap = Utils.Cap
		Cap.HasSecondsFormatter = (type(SecondsFormatter) ~= "nil")
		Cap.HasHealCalculator = (type(CreateUnitHealPredictionCalculator) ~= "nil")
		if not Utils.IS_MIDNIGHT then
			Cap.IsAuraLegacy = true
		else
			Cap.IsAuraLegacy = (C_UnitAuras and type(C_UnitAuras.GetAuraDurationRemaining) ~= "nil")
		end
		Cap.HasBooleanColor = (C_CurveUtil and type(C_CurveUtil.EvaluateColorFromBoolean) ~= "nil")
		Cap.HasDurationUtil = (C_DurationUtil and type(C_DurationUtil.CreateDuration) ~= "nil")
		-- 12.0.1: C_Secrets namespace replaces old GetSpellAuraSecrecy
		Cap.HasSecrecyQueries = (C_Secrets ~= nil and C_Secrets.ShouldSpellCooldownBeSecret ~= nil)
		if not Utils.IS_MIDNIGHT then
			Cap.IsRoyal = false
		else
			Cap.IsRoyal = Cap.HasSecondsFormatter
				or not Cap.IsAuraLegacy
				or Cap.HasDurationUtil
				or Cap.HasSecrecyQueries
		end
	end
	Utils.DetectCapabilities()
end

--------------------------------------------------------------------------------
-- Formatting & Time
--------------------------------------------------------------------------------

function Utils.FormatTime(seconds)
	return F and F:FormatDuration(seconds, true)
		or (function()
			if seconds == nil then
				return ""
			end
			if seconds > 3600 then
				return string.format("%dh", math.ceil(seconds / 3600))
			elseif seconds > 60 then
				return string.format("%dm", math.ceil(seconds / 60))
			end
			return string.format("%.1f", seconds)
		end)()
end

-- 12.0.1: Use SecondsFormatter for native secret-safe duration text
function Utils.FormatDurationSafe(seconds)
	if Utils.Cap.HasSecondsFormatter and SecondsFormatter then
		local ok, result = pcall(SecondsFormatter.Format, SecondsFormatter, seconds)
		if ok then
			return result
		end
	end
	return Utils.FormatTime(seconds)
end

function Utils.GetTimerFont(size)
	if F and F.GetTimerFont then
		return F:GetTimerFont(size)
	end
	return "GameFontHighlightOutline"
end

--------------------------------------------------------------------------------
-- Safe API & Guards (FenCore.Secrets > FenUI > fallback)
--------------------------------------------------------------------------------

function Utils.IsValueSecret(value)
	-- Primary: Use Midnight's dedicated issecretvalue() global (12.0+)
	if issecretvalue then
		return issecretvalue(value) == true
	end
	
	-- FenCore.Secrets fallback
	if Secrets then
		return Secrets.IsSecret(value)
	end
	-- FenUI fallback
	if F and F.IsValueSecret then
		return F:IsValueSecret(value)
	end

	-- Midnight Beta: Secret values are a distinct type that is NOT "number"
	-- but may be returned from APIs expecting numbers.
	if
		Utils.IS_MIDNIGHT
		and type(value) ~= "number"
		and type(value) ~= "nil"
		and type(value) ~= "boolean"
		and type(value) ~= "string"
		and type(value) ~= "table"
		and type(value) ~= "function"
	then
		return true
	end

	-- Built-in fallback: check if comparing value errors
	local ok = pcall(function()
		return value == value
	end)
	return not ok
end

function Utils.SafeCompare(a, b, op)
	-- FenCore.Secrets is the canonical source
	if Secrets then
		return Secrets.SafeCompare(a, b, op)
	end
	-- FenUI fallback
	if F and F.SafeCompare then
		return F:SafeCompare(a, b, op)
	end
	-- Built-in fallback with pcall protection
	local ok, result = pcall(function()
		if op == ">" then
			return a > b
		elseif op == "<" then
			return a < b
		elseif op == ">=" then
			return a >= b
		elseif op == "<=" then
			return a <= b
		elseif op == "~=" then
			return a ~= b
		else
			return a == b
		end
	end)
	return ok and result or false
end

-- Check if we're in a context where secret values may exist
-- M+: entire run is secured (even between pulls!)
-- Raids: during boss encounters
-- PvP: entire match
function Utils.MayHaveSecretValues()
	if not Utils.IS_MIDNIGHT then
		return false
	end
	-- M+: entire run secured
	if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
		return true
	end
	-- Raids: during boss encounters
	if IsEncounterInProgress and IsEncounterInProgress() then
		return true
	end
	-- PvP: entire match
	local _, instanceType = IsInInstance()
	if instanceType == "pvp" or instanceType == "arena" then
		return true
	end
	-- Fallback: combat in instances
	if InCombatLockdown() then
		if instanceType == "party" or instanceType == "raid" then
			return true
		end
	end
	return false
end

-- 12.0.1: Proactive secrecy checks - know if data will be secret BEFORE calling API
function Utils.WillSpellCooldownBeSecret(spellID)
	if not Utils.IS_MIDNIGHT then
		return false
	end
	if C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret then
		local ok, result = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
		if ok then
			return result
		end
	end
	return Utils.MayHaveSecretValues()
end

function Utils.WillActionCooldownBeSecret(actionID)
	if not Utils.IS_MIDNIGHT then
		return false
	end
	if C_Secrets and C_Secrets.ShouldActionCooldownBeSecret then
		local ok, result = pcall(C_Secrets.ShouldActionCooldownBeSecret, actionID)
		if ok then
			return result
		end
	end
	return Utils.MayHaveSecretValues()
end

function Utils.HideSafe(frame)
	if F then
		F:HideSafe(frame)
	else
		frame:Hide()
	end
end
function Utils.SetCooldownSafe(f, s, d)
	if F then
		F:SetCooldownSafe(f, s, d)
	end
end
function Utils.GetDurationSafe(u, s, f)
	return F and F:GetDurationSafe(u, s, f)
end
function Utils.SetTimerSafe(b, d, i, dr)
	return F and F:SetTimerSafe(b, d, i, dr)
end
function Utils.GetUnitHealthSafe(u)
	return F and F:GetUnitHealthSafe(u)
end

-- Passthrough for cached/safe wrappers
function Utils.GetSpellCooldownSafe(s)
	return F and F:GetSpellCooldownSafe(s)
end
function Utils.GetActionCooldownSafe(a)
	return F and F:GetActionCooldownSafe(a)
end
function Utils.GetSpellChargesSafe(s)
	return F and F:GetSpellChargesSafe(s)
end
function Utils.GetSpellTextureSafe(s)
	return F and F:GetSpellTextureSafe(s)
end
function Utils.GetItemSpellSafe(itemInfo)
	-- Try FenUI first
	if F and F.GetItemSpellSafe then
		return F:GetItemSpellSafe(itemInfo)
	end
	-- Built-in fallback
	if not itemInfo or not C_Item or not C_Item.GetItemSpell then
		return nil
	end
	local ok, name, spellID = pcall(C_Item.GetItemSpell, itemInfo)
	if ok then
		return name, spellID
	end
	return nil
end

function Utils.GetInventoryItemCooldownSafe(unit, slot)
	-- Try FenUI first
	if F and F.GetInventoryItemCooldownSafe then
		return F:GetInventoryItemCooldownSafe(unit, slot)
	end
	-- Built-in fallback
	if not unit or not slot then
		return 0, 0, false
	end
	if GetInventoryItemCooldown then
		local ok, start, duration, enabled = pcall(GetInventoryItemCooldown, unit, slot)
		if ok then
			return start or 0, duration or 0, enabled
		end
	end
	return 0, 0, false
end

function Utils.IsSpellOverlayedSafe(s)
	return F and F:IsSpellOverlayedSafe(s)
end
function Utils.GetActionDisplayCountSafe(a)
	-- Try FenUI first
	if F and F.GetActionDisplayCountSafe then
		local count = F:GetActionDisplayCountSafe(a)
		-- Check for secret value before comparing
		if count and not Utils.IsValueSecret(count) and count > 0 then
			return count
		end
	end
	-- Built-in fallback using legacy GetActionCount (works for items)
	if GetActionCount then
		local ok, count = pcall(GetActionCount, a)
		if ok and count and not Utils.IsValueSecret(count) and type(count) == "number" then
			return count
		end
	end
	-- Midnight: Try C_ActionBar.GetActionDisplayCount directly
	if C_ActionBar and C_ActionBar.GetActionDisplayCount then
		local ok, count = pcall(C_ActionBar.GetActionDisplayCount, a)
		if ok and count and not Utils.IsValueSecret(count) then
			if type(count) == "table" then
				local val = count.count or count.displayCount
				if val and not Utils.IsValueSecret(val) then
					return val
				end
				return 0
			end
			return count
		end
	end
	return 0
end
function Utils.GetActionBarPageSafe()
	return F and F:GetActionBarPageSafe() or 1
end
function Utils.GetActionTextureSafe(a)
	return F and F:GetActionTextureSafe(a)
end
function Utils.IsUsableActionSafe(a)
	return F and F:IsUsableActionSafe(a)
end
function Utils.IsActionInRangeSafe(a)
	return F and F:IsActionInRangeSafe(a)
end
function Utils.GetSpecializationSafe()
	return F and F:GetSpecializationSafe()
end

--------------------------------------------------------------------------------
-- UI Utilities
--------------------------------------------------------------------------------

function Utils.HideTexture(t)
	if F then
		F:HideTexture(t)
	else
		t:Hide()
	end
end
function Utils.ApplyIconCrop(t, w, h)
	if F then
		F:ApplyIconCrop(t, w, h)
	end
end
function Utils.StripBlizzardDecorations(f)
	if F then
		F:StripBlizzardDecorations(f)
	end
end
function Utils.DeepCopy(o)
	-- FenCore.Tables is the canonical source
	if FenCore and FenCore.Tables and FenCore.Tables.DeepCopy then
		return FenCore.Tables.DeepCopy(o)
	end
	-- FenUI fallback
	if F and F.DeepCopy then
		return F:DeepCopy(o)
	end
	-- Built-in fallback
	if type(o) ~= "table" then
		return o
	end
	local copy = {}
	for k, v in pairs(o) do
		if type(v) == "table" then
			copy[k] = Utils.DeepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

--------------------------------------------------------------------------------
-- ActionHud Specifics
--------------------------------------------------------------------------------

function Utils.CreateHealCalculator()
	if type(CreateUnitHealPredictionCalculator) == "function" then
		return CreateUnitHealPredictionCalculator()
	end
	return nil
end

function Utils.GetUnitHealsSafe(unit, calculator)
	local function Pass(v)
		if type(v) == "nil" then
			return 0
		end
		return v
	end

	if calculator and UnitGetDetailedHealPrediction then
		local ok = pcall(UnitGetDetailedHealPrediction, unit, "player", calculator)
		if ok then
			local h1, h2, h3, h4 = calculator:GetIncomingHeals()
			local abs = calculator.GetTotalAbsorbs and calculator:GetTotalAbsorbs()
			return Pass(h1), Pass(h2), Pass(h3), Pass(h4), Pass(abs)
		end
	end

	if UnitGetIncomingHeals then
		local h = UnitGetIncomingHeals(unit)
		local a = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)
		return Pass(h), Pass(h), 0, Pass(h), Pass(a)
	end

	return 0, 0, 0, 0, 0
end

function Utils.IsPowerTypeSafe(pType)
	if not Utils.IS_MIDNIGHT then
		return true
	end
	if not pType then
		return false
	end
	local safeTypes = {
		[Enum.PowerType.ComboPoints] = true,
		[Enum.PowerType.Runes] = true,
		[Enum.PowerType.SoulShards] = true,
		[Enum.PowerType.HolyPower] = true,
		[Enum.PowerType.Chi] = true,
		[Enum.PowerType.ArcaneCharges] = true,
		[Enum.PowerType.Essence] = true,
	}
	return safeTypes[pType] == true
end

function Utils.GetUnitColor(unit, barType, mult)
	mult = mult or 1
	if barType == "HEALTH" then
		if UnitIsPlayer(unit) then
			local _, class = UnitClass(unit)
			local c = RAID_CLASS_COLORS[class]
			if c then
				return c.r * mult, c.g * mult, c.b * mult
			end
		else
			if UnitIsEnemy("player", unit) then
				return 0.8 * mult, 0, 0
			elseif UnitIsFriend("player", unit) then
				return 0, 0.8 * mult, 0
			else
				return 0.8 * mult, 0.8 * mult, 0
			end
		end
		return 0, 0.8 * mult, 0
	elseif barType == "POWER" or barType == "MANA" then
		local pType, pToken, altR, altG, altB = UnitPowerType(unit)
		local info = PowerBarColor[pToken]
		if info then
			return info.r * mult, info.g * mult, info.b * mult
		elseif altR then
			return altR * mult, altG * mult, altB * mult
		end
		return 0, 0, 0.8 * mult
	end
	return 1, 1, 1
end

local totemDataCache = { expirationTime = 0, duration = 0, modRate = 1, slot = 0 }
function Utils.GetTotemDataForSpellID(spellID)
	if not spellID then
		return nil
	end
	local spellTexture = Utils.GetSpellTextureSafe(spellID)
	if not spellTexture then
		return nil
	end

	for slot = 1, MAX_TOTEMS or 4 do
		local haveTotem, totemName, startTime, duration, icon = GetTotemInfo(slot)
		if haveTotem and duration and duration > 0 then
			if icon == spellTexture then
				totemDataCache.expirationTime = startTime + duration
				totemDataCache.duration = duration
				totemDataCache.modRate = 1
				totemDataCache.slot = slot
				return totemDataCache
			end
		end
	end
	return nil
end

-- Cache management (ActionHud specific as it uses locals)
function Utils.InvalidateTextureCache()
	if F and F.InvalidateTextureCache then
		F:InvalidateTextureCache()
	end
end

return Utils

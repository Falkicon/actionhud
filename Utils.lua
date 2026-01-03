local addonName, ns = ...

ns.Utils = {}
local Utils = ns.Utils

-- Use shared FenUI utilities if available
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
-- Environment & Capability (Inherited)
--------------------------------------------------------------------------------

Utils.IS_MIDNIGHT = F and F.IS_MIDNIGHT or (((select(4, GetBuildInfo())) or 0) >= 120000)
Utils.Cap = F and F.Cap or {}

if not F then
    -- Fallback detection if FenUI is missing
    function Utils.DetectCapabilities()
        local Cap = Utils.Cap
        Cap.HasSecondsFormatter = (type(SecondsFormatter) ~= "nil")
        Cap.HasHealCalculator = (type(CreateUnitHealPredictionCalculator) ~= "nil")
        if not Utils.IS_MIDNIGHT then Cap.IsAuraLegacy = true else
            Cap.IsAuraLegacy = (C_UnitAuras and type(C_UnitAuras.GetAuraDurationRemaining) ~= "nil")
        end
        Cap.HasBooleanColor = (C_CurveUtil and type(C_CurveUtil.EvaluateColorFromBoolean) ~= "nil")
        Cap.HasDurationUtil = (C_DurationUtil and type(C_DurationUtil.CreateDuration) ~= "nil")
        Cap.HasSecrecyQueries = (type(GetSpellAuraSecrecy) ~= "nil")
        if not Utils.IS_MIDNIGHT then Cap.IsRoyal = false else
            Cap.IsRoyal = Cap.HasSecondsFormatter or not Cap.IsAuraLegacy or Cap.HasDurationUtil or Cap.HasSecrecyQueries
        end
    end
    Utils.DetectCapabilities()
end

--------------------------------------------------------------------------------
-- Formatting & Time
--------------------------------------------------------------------------------

function Utils.FormatTime(seconds)
    return F and F:FormatDuration(seconds, true) or (function()
        if seconds == nil then return "" end
        if seconds > 3600 then return string.format("%dh", math.ceil(seconds / 3600))
        elseif seconds > 60 then return string.format("%dm", math.ceil(seconds / 60)) end
        return string.format("%.1f", seconds)
    end)()
end

function Utils.GetTimerFont(size)
    return F and F:GetTimerFont(size) or "GameFontHighlightOutline"
end

--------------------------------------------------------------------------------
-- Safe API & Guards
--------------------------------------------------------------------------------

function Utils.IsValueSecret(value)
    if F and F.IsValueSecret then return F:IsValueSecret(value) end
    -- Fallback: check if comparing value errors (secret values error on comparison)
    local ok = pcall(function() return value == value end)
    return not ok
end

function Utils.SafeCompare(a, b, op)
    if F and F.SafeCompare then return F:SafeCompare(a, b, op) end
    -- Fallback with pcall protection for secret values
    local ok, result = pcall(function()
        if op == ">" then return a > b
        elseif op == "<" then return a < b
        elseif op == ">=" then return a >= b
        elseif op == "<=" then return a <= b
        elseif op == "~=" then return a ~= b
        else return a == b
        end
    end)
    return ok and result or nil
end
function Utils.HideSafe(frame) if F then F:HideSafe(frame) else frame:Hide() end end
function Utils.SetCooldownSafe(f, s, d) if F then F:SetCooldownSafe(f, s, d) end end
function Utils.GetDurationSafe(u, s, f) return F and F:GetDurationSafe(u, s, f) end
function Utils.SetTimerSafe(b, d, i, dr) return F and F:SetTimerSafe(b, d, i, dr) end
function Utils.GetUnitHealthSafe(u) return F and F:GetUnitHealthSafe(u) end

-- Passthrough for cached/safe wrappers
function Utils.GetSpellCooldownSafe(s) return F and F:GetSpellCooldownSafe(s) end
function Utils.GetActionCooldownSafe(a) return F and F:GetActionCooldownSafe(a) end
function Utils.GetSpellChargesSafe(s) return F and F:GetSpellChargesSafe(s) end
function Utils.GetSpellTextureSafe(s) return F and F:GetSpellTextureSafe(s) end
function Utils.GetItemSpellSafe(i) return F and F:GetItemSpellSafe(i) end
function Utils.GetInventoryItemCooldownSafe(u, s) return F and F:GetInventoryItemCooldownSafe(u, s) end
function Utils.IsSpellOverlayedSafe(s) return F and F:IsSpellOverlayedSafe(s) end
function Utils.GetActionDisplayCountSafe(a) return F and F:GetActionDisplayCountSafe(a) end
function Utils.GetActionBarPageSafe() return F and F:GetActionBarPageSafe() or 1 end
function Utils.GetActionTextureSafe(a) return F and F:GetActionTextureSafe(a) end
function Utils.IsUsableActionSafe(a) return F and F:IsUsableActionSafe(a) end
function Utils.IsActionInRangeSafe(a) return F and F:IsActionInRangeSafe(a) end
function Utils.GetSpecializationSafe() return F and F:GetSpecializationSafe() end

--------------------------------------------------------------------------------
-- UI Utilities
--------------------------------------------------------------------------------

function Utils.HideTexture(t) if F then F:HideTexture(t) else t:Hide() end end
function Utils.ApplyIconCrop(t, w, h) if F then F:ApplyIconCrop(t, w, h) end end
function Utils.StripBlizzardDecorations(f) if F then F:StripBlizzardDecorations(f) end end
function Utils.DeepCopy(o) return F and F:DeepCopy(o) or o end

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
		if type(v) == "nil" then return 0 end
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
	if not Utils.IS_MIDNIGHT then return true end
	if not pType then return false end
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
			if c then return c.r * mult, c.g * mult, c.b * mult end
		else
			if UnitIsEnemy("player", unit) then return 0.8 * mult, 0, 0
			elseif UnitIsFriend("player", unit) then return 0, 0.8 * mult, 0
			else return 0.8 * mult, 0.8 * mult, 0 end
		end
		return 0, 0.8 * mult, 0
	elseif barType == "POWER" or barType == "MANA" then
		local pType, pToken, altR, altG, altB = UnitPowerType(unit)
		local info = PowerBarColor[pToken]
		if info then return info.r * mult, info.g * mult, info.b * mult
		elseif altR then return altR * mult, altG * mult, altB * mult end
		return 0, 0, 0.8 * mult
	end
	return 1, 1, 1
end

local totemDataCache = { expirationTime = 0, duration = 0, modRate = 1, slot = 0 }
function Utils.GetTotemDataForSpellID(spellID)
	if not spellID then return nil end
	local spellTexture = Utils.GetSpellTextureSafe(spellID)
	if not spellTexture then return nil end

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
    if F and F.InvalidateTextureCache then F:InvalidateTextureCache() end
end

return Utils

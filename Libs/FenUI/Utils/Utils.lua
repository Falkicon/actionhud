--------------------------------------------------------------------------------
-- FenUI.Utils
-- Main namespace and loader for modular utilities.
--------------------------------------------------------------------------------

FenUI.Utils = FenUI.Utils or {}
local Utils = FenUI.Utils

-- Simple version tracking for the utils library
Utils.VERSION = "1.0.0"

--------------------------------------------------------------------------------
-- Environment & Capability
--------------------------------------------------------------------------------

local function GetInterfaceVersion()
	if type(_G.GetBuildInfo) ~= "function" then
		return 0
	end

	local ok, _, _, _, interfaceVersion = pcall(_G.GetBuildInfo)
	if not ok then
		return 0
	end
	return tonumber(interfaceVersion) or 0
end

--- Refresh environment flags used by the safe API and formatting modules.
--- Embedded copies cannot rely on the standalone FenUI addon's initialization.
---@return table capabilities
function Utils:DetectCapabilities()
	self.IS_MIDNIGHT = GetInterfaceVersion() >= 120000

	local Cap = self.Cap or {}
	self.Cap = Cap
	Cap.HasSecondsFormatter = (_G.C_StringUtil and type(_G.C_StringUtil.CreateSecondsFormatter) == "function")
		or type(_G.CreateSecondsFormatter) == "function"
	Cap.HasHealCalculator = type(_G.CreateUnitHealPredictionCalculator) == "function"
	if not self.IS_MIDNIGHT then
		Cap.IsAuraLegacy = true
	else
		Cap.IsAuraLegacy = _G.C_UnitAuras and type(_G.C_UnitAuras.GetAuraDurationRemaining) == "function" or false
	end
	Cap.HasBooleanColor = _G.C_CurveUtil and type(_G.C_CurveUtil.EvaluateColorFromBoolean) == "function" or false
	Cap.HasDurationUtil = _G.C_DurationUtil and type(_G.C_DurationUtil.CreateDuration) == "function" or false
	Cap.HasSecrecyQueries = _G.C_Secrets and type(_G.C_Secrets.ShouldSpellCooldownBeSecret) == "function" or false
	Cap.IsRoyal = self.IS_MIDNIGHT
		and (Cap.HasSecondsFormatter or not Cap.IsAuraLegacy or Cap.HasDurationUtil or Cap.HasSecrecyQueries)
		or false

	return Cap
end

Utils:DetectCapabilities()

function Utils:IsValueSecret(value)
	if _G.issecretvalue then
		return _G.issecretvalue(value) == true
	end
	local ok = pcall(function()
		return value == value
	end)
	return not ok
end

function Utils:SafeCompare(a, b, operator)
	local ok, result = pcall(function()
		if operator == ">" then
			return a > b
		elseif operator == "<" then
			return a < b
		elseif operator == ">=" then
			return a >= b
		elseif operator == "<=" then
			return a <= b
		elseif operator == "~=" then
			return a ~= b
		end
		return a == b
	end)
	if ok then
		return result
	end
	return false
end

--- Returns the utils module
---@return table
function FenUI:GetUtils()
	return self.Utils
end

return Utils

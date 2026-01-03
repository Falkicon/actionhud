--------------------------------------------------------------------------------
-- FenCoreCompat.lua
-- Graceful FenCore integration for ActionHud
-- Provides fallbacks when FenCore is not available
--------------------------------------------------------------------------------

---@class ActionHudFenCore
local Compat = {}

local FenCore = _G.FenCore

--------------------------------------------------------------------------------
-- Math
-- Pure mathematical utilities
--------------------------------------------------------------------------------

if FenCore and FenCore.Math then
	Compat.Math = FenCore.Math
else
	-- Fallback implementation
	local Math = {}

	function Math.Clamp(value, minValue, maxValue)
		if type(value) ~= "number" then
			return minValue
		end
		return math.max(minValue, math.min(maxValue, value))
	end

	function Math.Lerp(a, b, t)
		return a + (b - a) * t
	end

	function Math.Round(value, decimals)
		decimals = decimals or 0
		local mult = 10 ^ decimals
		return math.floor(value * mult + 0.5) / mult
	end

	Compat.Math = Math
end

--------------------------------------------------------------------------------
-- Secrets
-- Handle WoW 12.0+ secret values
--------------------------------------------------------------------------------

if FenCore and FenCore.Secrets then
	Compat.Secrets = FenCore.Secrets
else
	-- Fallback implementation
	local Secrets = {}

	function Secrets.IsSecret(value)
		return type(issecretvalue) == "function" and issecretvalue(value)
	end

	function Secrets.SafeCompare(a, b, op)
		if Secrets.IsSecret(a) or Secrets.IsSecret(b) then
			return nil
		end
		if a == nil or b == nil then
			return nil
		end
		if op == ">" then
			return a > b
		elseif op == "<" then
			return a < b
		elseif op == ">=" then
			return a >= b
		elseif op == "<=" then
			return a <= b
		elseif op == "==" then
			return a == b
		elseif op == "~=" then
			return a ~= b
		end
		return nil
	end

	function Secrets.SafeToString(value)
		if Secrets.IsSecret(value) then
			return "???"
		end
		return tostring(value)
	end

	Compat.Secrets = Secrets
end

--------------------------------------------------------------------------------
-- Environment
-- WoW client detection
--------------------------------------------------------------------------------

if FenCore and FenCore.Environment then
	Compat.Environment = FenCore.Environment
else
	-- Fallback implementation
	local Environment = {}

	function Environment.GetInterfaceVersion()
		return select(4, GetBuildInfo()) or 0
	end

	function Environment.IsMidnight()
		return Environment.GetInterfaceVersion() >= 120000
	end

	Compat.Environment = Environment
end

--------------------------------------------------------------------------------
-- Time
-- Duration formatting
--------------------------------------------------------------------------------

if FenCore and FenCore.Time then
	Compat.Time = FenCore.Time
else
	-- Fallback implementation
	local Time = {}

	function Time.FormatCooldown(seconds)
		if not seconds or seconds <= 0 then
			return ""
		end
		if seconds >= 3600 then
			return string.format("%dh", math.ceil(seconds / 3600))
		elseif seconds >= 60 then
			return string.format("%dm", math.ceil(seconds / 60))
		else
			return string.format("%.1f", seconds)
		end
	end

	function Time.FormatCooldownShort(seconds)
		if not seconds or seconds <= 0 then
			return ""
		end
		if seconds >= 3600 then
			return string.format("%dh", math.ceil(seconds / 3600))
		elseif seconds >= 60 then
			return string.format("%dm", math.ceil(seconds / 60))
		elseif seconds >= 10 then
			return string.format("%d", math.ceil(seconds))
		else
			return string.format("%.1f", seconds)
		end
	end

	Compat.Time = Time
end

--------------------------------------------------------------------------------
-- Export to global for ActionHud access
--------------------------------------------------------------------------------

ActionHudFenCore = Compat

return Compat

-- ActionHud Core Layer
-- Pure Lua logic with no WoW API dependencies (sandbox-compatible)

---@class ActionHudCore
ActionHudCore = ActionHudCore or {}

-- FenCore integration (with graceful fallback via FenCoreCompat)
local FC = ActionHudFenCore

-- =============================================================================
-- Safe Comparisons (handles nil values gracefully)
-- =============================================================================

--- Safe comparison that handles nil values
--- Note: This is different from FenCore.Secrets.SafeCompare which handles secret values.
--- This function returns false (not nil) for nil inputs, making it safe for conditional checks.
---@param a number|nil First value
---@param b number|nil Second value
---@param op string Operator: ">", "<", ">=", "<=", "==", "~="
---@return boolean result False if either value is nil
function ActionHudCore.SafeCompare(a, b, op)
	if a == nil or b == nil then
		return false
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
	return false
end

-- =============================================================================
-- Value Clamping and Validation (uses FenCore.Math when available)
-- =============================================================================

--- Clamp a value to a range
---@param value number|nil Value to clamp
---@param min number Minimum value
---@param max number Maximum value
---@return number clamped Clamped value (returns min if value is nil or not a number)
function ActionHudCore.Clamp(value, min, max)
	if FC and FC.Math and FC.Math.Clamp then
		if type(value) ~= "number" then
			return min
		end
		return FC.Math.Clamp(value, min, max)
	end
	-- Fallback
	if type(value) ~= "number" then
		return min
	end
	return math.max(min, math.min(max, value))
end

-- =============================================================================
-- Settings Validators
-- =============================================================================

--- Validate icon size settings
---@param width number|nil Icon width
---@param height number|nil Icon height
---@return table validated { width: number, height: number }
function ActionHudCore.ValidateIconSize(width, height)
	return {
		width = ActionHudCore.Clamp(width, 10, 100),
		height = ActionHudCore.Clamp(height, 10, 100),
	}
end

--- Validate font size setting
---@param size number|nil Font size
---@return number validated Clamped to 4-24 range
function ActionHudCore.ValidateFontSize(size)
	return ActionHudCore.Clamp(size, 4, 24)
end

--- Validate opacity setting
---@param opacity number|nil Opacity value
---@return number validated Clamped to 0-1 range
function ActionHudCore.ValidateOpacity(opacity)
	return ActionHudCore.Clamp(opacity, 0, 1)
end

--- Validate cooldown font size setting
---@param size number|nil Cooldown font size
---@return number validated Clamped to 4-16 range
function ActionHudCore.ValidateCooldownFontSize(size)
	return ActionHudCore.Clamp(size, 4, 16)
end

--- Validate offset value
---@param offset number|nil X or Y offset
---@return number validated Clamped to -1000 to 1000 range
function ActionHudCore.ValidateOffset(offset)
	return ActionHudCore.Clamp(offset, -1000, 1000)
end

--- Validate gap size between modules
---@param gap number|nil Gap size
---@return number validated Clamped to 0-50 range
function ActionHudCore.ValidateGap(gap)
	return ActionHudCore.Clamp(gap, 0, 50)
end

return ActionHudCore

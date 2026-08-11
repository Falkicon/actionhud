--[[
	ActionHud - Restricted Action Bar Cooldown Tests
	Run from the addon root: lua Tests/test_actionbars_cooldown.lua
]]

_G = _G or {}

local secretValues = {}
local function SecretTiming(name)
	local value = setmetatable({ name = name }, {
		__add = function()
			error("secret timing value was used in arithmetic")
		end,
		__lt = function()
			error("secret timing value was compared")
		end,
		__le = function()
			error("secret timing value was compared")
		end,
	})
	secretValues[value] = true
	return value
end

local ActionBars
local ActionHud = {}
function ActionHud.NewModule()
	ActionBars = {}
	return ActionBars
end

LibStub = function(name)
	if name == "AceAddon-3.0" then
		return {
			GetAddon = function()
				return ActionHud
			end,
		}
	end
end

GetTime = function()
	return 0
end
GetBonusBarOffset = function()
	return 0
end
GetActionInfo = function()
	return nil
end
GetMacroSpell = function()
	return nil
end

local ns = {
	Utils = {
		GetActionBarPageSafe = function()
			return 1
		end,
		GetActionTextureSafe = function()
			return nil
		end,
		GetActionCooldownSafe = function()
			return 0, 0, false, 1
		end,
		GetActionDisplayCountSafe = function()
			return nil
		end,
		IsUsableActionSafe = function()
			return true, false
		end,
		IsActionInRangeSafe = function()
			return nil
		end,
		IsValueSecret = function(value)
			return secretValues[value] == true
		end,
		SafeCompare = function(a, b, operator)
			if secretValues[a] or secretValues[b] then
				error("secret timing value reached SafeCompare")
			end
			if operator == ">" then
				return a > b
			elseif operator == "<=" then
				return a <= b
			elseif operator == "==" then
				return a == b
			end
			return false
		end,
	},
}

local function LoadActionBars()
	local file = assert(io.open("ActionBars.lua", "r"))
	local content = file:read("*a")
	file:close()
	local loader = loadstring or load
	local chunk = assert(loader(content, "ActionBars.lua"))
	chunk("ActionHud", ns)
end

local function AssertEqual(expected, actual, message)
	if expected ~= actual then
		error(string.format("%s\nExpected: %s\nActual: %s", message, tostring(expected), tostring(actual)))
	end
end

local function NewCooldownFrame()
	local frame = { shown = false, clearCount = 0 }
	function frame:SetDrawEdge(drawEdge)
		self.drawEdge = drawEdge
	end
	function frame:SetCooldownFromDurationObject(durationObject, clearIfZero)
		self.durationObject = durationObject
		self.clearIfZero = clearIfZero
	end
	function frame:Clear()
		self.clearCount = self.clearCount + 1
		self.durationObject = nil
	end
	function frame:Show()
		self.shown = true
	end
	function frame:Hide()
		self.shown = false
	end
	return frame
end

local function RestrictedInfo(isNormalActive, isChargeActive, isLocActive, shouldReplaceNormal)
	return {
		startTime = SecretTiming("normal start"),
		duration = SecretTiming("normal duration"),
		isEnabled = true,
		isActive = isNormalActive,
		modRate = SecretTiming("normal mod rate"),
	}, {
		currentCharges = SecretTiming("current charges"),
		maxCharges = 2,
		cooldownStartTime = SecretTiming("charge start"),
		cooldownDuration = SecretTiming("charge duration"),
		chargeModRate = SecretTiming("charge mod rate"),
		isActive = isChargeActive,
	}, {
		startTime = SecretTiming("loc start"),
		duration = SecretTiming("loc duration"),
		modRate = SecretTiming("loc mod rate"),
		isActive = isLocActive,
		shouldReplaceNormalCooldown = shouldReplaceNormal,
	}
end

local function RunRestrictedCase(options)
	local calls = { normal = 0, charge = 0, lossOfControl = 0 }
	local normalDuration = { kind = "normal" }
	local chargeDuration = { kind = "charge" }
	local locDuration = { kind = "lossOfControl" }

	C_ActionBar = {
		GetActionCooldown = function()
			return options.cooldownInfo
		end,
		GetActionCharges = function()
			return options.chargeInfo
		end,
		GetActionLossOfControlCooldownInfo = function()
			return options.lossOfControlInfo
		end,
		GetActionCooldownDuration = function()
			calls.normal = calls.normal + 1
			return normalDuration
		end,
		GetActionChargeDuration = function()
			calls.charge = calls.charge + 1
			return chargeDuration
		end,
		GetActionLossOfControlCooldownDuration = function()
			calls.lossOfControl = calls.lossOfControl + 1
			return locDuration
		end,
	}

	local button = { hasAction = true, actionID = 42, cd = NewCooldownFrame() }
	ActionBars:UpdateCooldown(button)
	return button, calls, {
		normal = normalDuration,
		charge = chargeDuration,
		lossOfControl = locDuration,
	}
end

LoadActionBars()
print("Running ActionBars restricted cooldown tests...")

do
	local cooldownInfo, chargeInfo, lossOfControlInfo = RestrictedInfo(false, true, false, false)
	local button, calls, durations = RunRestrictedCase({
		cooldownInfo = cooldownInfo,
		chargeInfo = chargeInfo,
		lossOfControlInfo = lossOfControlInfo,
	})
	AssertEqual(durations.charge, button.cd.durationObject, "active charge should use charge duration")
	AssertEqual(0, calls.normal, "inactive normal duration should not be requested")
	AssertEqual(1, calls.charge, "charge duration should be requested once")
	AssertEqual(0, calls.lossOfControl, "inactive LoC duration should not be requested")
end

do
	local cooldownInfo, chargeInfo, lossOfControlInfo = RestrictedInfo(true, true, true, true)
	local button, calls, durations = RunRestrictedCase({
		cooldownInfo = cooldownInfo,
		chargeInfo = chargeInfo,
		lossOfControlInfo = lossOfControlInfo,
	})
	AssertEqual(durations.lossOfControl, button.cd.durationObject, "LoC replacement should use LoC duration")
	AssertEqual(0, calls.normal, "replaced normal duration should not be requested")
	AssertEqual(0, calls.charge, "replaced charge duration should not be requested")
	AssertEqual(1, calls.lossOfControl, "LoC duration should be requested once")
end

do
	local cooldownInfo, chargeInfo, lossOfControlInfo = RestrictedInfo(true, false, false, false)
	local button, calls, durations = RunRestrictedCase({
		cooldownInfo = cooldownInfo,
		chargeInfo = chargeInfo,
		lossOfControlInfo = lossOfControlInfo,
	})
	AssertEqual(durations.normal, button.cd.durationObject, "ordinary cooldown should use normal duration")
	AssertEqual(1, calls.normal, "normal duration should be requested once")
	AssertEqual(0, calls.charge, "inactive charge duration should not be requested")
	AssertEqual(0, calls.lossOfControl, "inactive LoC duration should not be requested")
end

do
	local cooldownInfo, chargeInfo, lossOfControlInfo = RestrictedInfo(false, false, false, false)
	local button, calls = RunRestrictedCase({
		cooldownInfo = cooldownInfo,
		chargeInfo = chargeInfo,
		lossOfControlInfo = lossOfControlInfo,
	})
	AssertEqual(nil, button.cd.durationObject, "inactive zero-span state should clear the display")
	AssertEqual(false, button.cd.shown, "inactive zero-span state should remain hidden")
	AssertEqual(1, button.cd.clearCount, "inactive zero-span state should clear once")
	AssertEqual(0, calls.normal, "inactive normal duration should not be requested")
	AssertEqual(0, calls.charge, "inactive charge duration should not be requested")
	AssertEqual(0, calls.lossOfControl, "inactive LoC duration should not be requested")
end

do
	local cooldownInfo = { startTime = 10, duration = 30, isEnabled = true, isActive = true, modRate = 1 }
	local chargeInfo = {
		currentCharges = 1,
		maxCharges = 2,
		cooldownStartTime = 10,
		cooldownDuration = 30,
		chargeModRate = 1,
		isActive = true,
	}
	local lossOfControlInfo = {
		startTime = 0,
		duration = 0,
		modRate = 1,
		isActive = false,
		shouldReplaceNormalCooldown = false,
	}
	local applied = false
	ActionButton_ApplyCooldown = function(normalFrame, normalInfo, chargeFrame, charges, lossFrame, locInfo)
		applied = normalFrame
			and chargeFrame
			and normalInfo == cooldownInfo
			and charges == chargeInfo
			and lossFrame == nil
			and locInfo == lossOfControlInfo
	end
	C_ActionBar = {
		GetActionCooldown = function()
			return cooldownInfo
		end,
		GetActionCharges = function()
			return chargeInfo
		end,
		GetActionLossOfControlCooldownInfo = function()
			return lossOfControlInfo
		end,
	}
	CreateFrame = function()
		local frame = NewCooldownFrame()
		frame.SetHideCountdownNumbers = function() end
		frame.SetDrawSwipe = function() end
		frame.SetAllPoints = function() end
		frame.SetFrameLevel = function() end
		return frame
	end

	local button = {
		hasAction = true,
		actionID = 42,
		cd = NewCooldownFrame(),
		GetFrameLevel = function()
			return 1
		end,
	}
	ActionBars:UpdateCooldown(button)
	AssertEqual(true, applied, "unrestricted cooldowns should keep using ActionButton_ApplyCooldown")
	ActionButton_ApplyCooldown = nil
end

do
	local cooldownInfo = { startTime = 10, duration = 30, isEnabled = true, isActive = true, modRate = 1 }
	local chargeInfo = {
		currentCharges = 0,
		maxCharges = 0,
		cooldownStartTime = 0,
		cooldownDuration = 0,
		chargeModRate = 1,
		isActive = false,
	}
	local lossOfControlInfo = {
		startTime = 0,
		duration = 0,
		modRate = 1,
		isActive = false,
		shouldReplaceNormalCooldown = false,
	}
	local createCount = 0
	local appliedChargeFrame = "unset"
	ActionButton_ApplyCooldown = function(_, _, chargeFrame)
		appliedChargeFrame = chargeFrame
	end
	C_ActionBar = {
		GetActionCooldown = function()
			return cooldownInfo
		end,
		GetActionCharges = function()
			return chargeInfo
		end,
		GetActionLossOfControlCooldownInfo = function()
			return lossOfControlInfo
		end,
	}
	CreateFrame = function()
		createCount = createCount + 1
		local frame = NewCooldownFrame()
		frame.SetHideCountdownNumbers = function() end
		frame.SetDrawSwipe = function() end
		frame.SetAllPoints = function() end
		frame.SetFrameLevel = function() end
		return frame
	end

	local button = {
		hasAction = true,
		actionID = 42,
		cd = NewCooldownFrame(),
		GetFrameLevel = function()
			return 1
		end,
	}
	ActionBars:UpdateCooldown(button)
	AssertEqual(1, createCount, "Blizzard's helper requires a secondary cooldown frame for every action")
	AssertEqual(button.chargeCooldown, appliedChargeFrame, "the required secondary cooldown frame must be passed")
	ActionBars:UpdateCooldown(button)
	AssertEqual(1, createCount, "the secondary cooldown frame should be reused after its first allocation")
	ActionButton_ApplyCooldown = nil
end

do
	local restrictedText = SecretTiming("display count")
	local displayText = restrictedText
	C_ActionBar = {
		GetActionDisplayCount = function()
			return displayText
		end,
	}
	local count = {}
	function count:SetText(value)
		self.text = value
	end
	local button = { actionID = 42, count = count }

	ActionBars:UpdateCount(button)
	AssertEqual(restrictedText, count.text, "restricted count text should pass directly to FontString")
	AssertEqual(nil, button._countText, "restricted count text must not be retained in addon state")

	-- Also recover safely if an older session has already contaminated the cache.
	button._countText = restrictedText
	displayText = ""
	ActionBars:UpdateCount(button)
	AssertEqual("", button._countText, "ordinary count text should replace a restricted cached value")
	AssertEqual("", count.text, "ordinary count text should still reach FontString")
end

print("SUCCESS: ActionBars restricted cooldown compositor verified!")

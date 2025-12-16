local addonName = "ActionHud"

-- Blizzard Settings (Retail 10.0+). No external libraries.

local function GetProfile()
	ActionHudDB = ActionHudDB or {}
	ActionHudDB.profile = ActionHudDB.profile or {}
    
    local p = ActionHudDB.profile
    
    -- Defaults (mirrored from Core.lua for initial setup)
    if p.iconWidth == nil then p.iconWidth = 20 end
    if p.iconHeight == nil then p.iconHeight = 15 end
    if p.cooldownFontSize == nil then p.cooldownFontSize = 6 end
    if p.countFontSize == nil then p.countFontSize = 6 end
    if p.opacity == nil then p.opacity = 0.0 end
    
    if p.padding == nil then p.padding = 0 end
    if p.locked == nil then p.locked = false end
    
    return p
end

local function Clamp(n, minV, maxV)
	if n < minV then return minV end
	if n > maxV then return maxV end
	return n
end

local function Round(num, decimals)
    local mult = 10^(decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

local function ApplyIfReady(methodName, ...)
	if ActionHudFrame and ActionHudFrame[methodName] then
		local ok = pcall(ActionHudFrame[methodName], ActionHudFrame, ...)
		return ok
	end
    -- Fallback for simple re-layout if method absent
    if ActionHudFrame and ActionHudFrame.UpdateLayout then
         ActionHudFrame:UpdateLayout()
    end
	return false
end

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end

	local category = Settings.RegisterVerticalLayoutCategory("ActionHud")

	local function OnSettingChanged(_, _)
		-- Placeholder hook
	end

	-- ============================================================
	-- General Settings
	-- ============================================================

	-- Lock frame
	do
		local name = "Lock frame"
		local variable = "ActionHud_Locked"
		local defaultValue = false

		local function GetValue()
			return GetProfile().locked
		end

		local function SetValue(value)
			GetProfile().locked = value and true or false
            ApplyIfReady("UpdateLockState")
		end

		local setting = Settings.RegisterProxySetting(category, variable, type(defaultValue), name, defaultValue, GetValue, SetValue)
		setting:SetValueChangedCallback(OnSettingChanged)
		Settings.CreateCheckbox(category, setting, "Prevents dragging the ActionHud HUD.")
	end

	-- Icon Width
	do
		local name = "Icon Width"
		local variable = "ActionHud_IconWidth"
		local defaultValue = 20
		local minValue, maxValue, step = 10, 30, 1

		local function GetValue()
			return GetProfile().iconWidth or defaultValue
		end

		local function SetValue(value)
			value = Clamp(tonumber(value) or defaultValue, minValue, maxValue)
			GetProfile().iconWidth = value
			ApplyIfReady("UpdateLayout")
		end

		local setting = Settings.RegisterProxySetting(category, variable, type(defaultValue), name, defaultValue, GetValue, SetValue)
		setting:SetValueChangedCallback(OnSettingChanged)

		local options = Settings.CreateSliderOptions(minValue, maxValue, step)
		if options and options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and MinimalSliderWithSteppersMixin.Label.Right then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end

		Settings.CreateSlider(category, setting, options, "Width of the action icons.")
	end

	-- Icon Height
	do
		local name = "Icon Height"
		local variable = "ActionHud_IconHeight"
		local defaultValue = 15
		local minValue, maxValue, step = 10, 30, 1

		local function GetValue()
			return GetProfile().iconHeight or defaultValue
		end

		local function SetValue(value)
			value = Clamp(tonumber(value) or defaultValue, minValue, maxValue)
			GetProfile().iconHeight = value
			ApplyIfReady("UpdateLayout")
		end

		local setting = Settings.RegisterProxySetting(category, variable, type(defaultValue), name, defaultValue, GetValue, SetValue)
		setting:SetValueChangedCallback(OnSettingChanged)

		local options = Settings.CreateSliderOptions(minValue, maxValue, step)
		if options and options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label and MinimalSliderWithSteppersMixin.Label.Right then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end

		Settings.CreateSlider(category, setting, options, "Height of the action icons (crop top/bottom if smaller than width).")
	end
    
    -- Cooldown Font Size
	do
		local name = "Cooldown Font Size"
		local variable = "ActionHud_CDFontSize"
		local defaultValue = 6
		local minValue, maxValue, step = 6, 16, 1

		local function GetValue()
			return GetProfile().cooldownFontSize or defaultValue
		end

		local function SetValue(value)
			value = Clamp(tonumber(value) or defaultValue, minValue, maxValue)
			GetProfile().cooldownFontSize = value
            -- Force layout update or full refresh usually required for font propagation in some cases
			ApplyIfReady("UpdateLayout") 
		end

		local setting = Settings.RegisterProxySetting(category, variable, type(defaultValue), name, defaultValue, GetValue, SetValue)
		setting:SetValueChangedCallback(OnSettingChanged)

		local options = Settings.CreateSliderOptions(minValue, maxValue, step)
		if options and options.SetLabelFormatter then
             options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
		Settings.CreateSlider(category, setting, options, "Font size for cooldown numbers.")
	end

    -- Stack Count Font Size
	do
		local name = "Stack Count Font Size"
		local variable = "ActionHud_CountFontSize"
		local defaultValue = 6
		local minValue, maxValue, step = 6, 16, 1

		local function GetValue()
			return GetProfile().countFontSize or defaultValue
		end

		local function SetValue(value)
			value = Clamp(tonumber(value) or defaultValue, minValue, maxValue)
			GetProfile().countFontSize = value
			ApplyIfReady("UpdateLayout")
		end

		local setting = Settings.RegisterProxySetting(category, variable, type(defaultValue), name, defaultValue, GetValue, SetValue)
		setting:SetValueChangedCallback(OnSettingChanged)

		local options = Settings.CreateSliderOptions(minValue, maxValue, step)
		if options and options.SetLabelFormatter then
             options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
		Settings.CreateSlider(category, setting, options, "Font size for stack counts (bottom right).")
	end

    -- Opacity / Alpha (Stored as 0.0-1.0, Displayed as 0-100)
	do
		local name = "Background Opacity"
		local variable = "ActionHud_Alpha"
		local defaultValue = 0.0
		local minValue, maxValue, step = 0, 100, 5

		local function GetValue()
            local val = GetProfile().opacity or defaultValue
			return math.floor(val * 100 + 0.5)
		end

		local function SetValue(value)
			value = Clamp(tonumber(value) or 0, minValue, maxValue)
            -- Save as float 0.0 - 1.0
			GetProfile().opacity = value / 100
			ApplyIfReady("UpdateOpacity")
		end

		local setting = Settings.RegisterProxySetting(category, variable, type(defaultValue), name, defaultValue * 100, GetValue, SetValue)
		setting:SetValueChangedCallback(OnSettingChanged)

		local options = Settings.CreateSliderOptions(minValue, maxValue, step)
		if options and options.SetLabelFormatter then
             options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
		Settings.CreateSlider(category, setting, options, "Opacity of the empty button background (0-100%).")
	end
    
    -- Proc Glow Opacity
	do
		local name = "Proc Glow Opacity (Yellow)"
		local variable = "ActionHud_ProcGlowAlpha"
		local defaultValue = 1.0
		local minValue, maxValue, step = 0, 100, 5

		local function GetValue()
            local val = GetProfile().procGlowAlpha or defaultValue
			return math.floor(val * 100 + 0.5)
		end

		local function SetValue(value)
			value = Clamp(tonumber(value) or 100, minValue, maxValue)
			GetProfile().procGlowAlpha = value / 100
			ApplyIfReady("UpdateLayout")
		end

		local setting = Settings.RegisterProxySetting(category, variable, type(defaultValue), name, defaultValue * 100, GetValue, SetValue)
		setting:SetValueChangedCallback(OnSettingChanged)

		local options = Settings.CreateSliderOptions(minValue, maxValue, step)
		if options and options.SetLabelFormatter then
             options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
		Settings.CreateSlider(category, setting, options, "Opacity of the 1px Yellow Proc border (0-100%).")
	end

    -- Assist Glow Opacity
	do
		local name = "Assist Glow Opacity (Blue)"
		local variable = "ActionHud_AssistGlowAlpha"
		local defaultValue = 1.0
		local minValue, maxValue, step = 0, 100, 5

		local function GetValue()
            local val = GetProfile().assistGlowAlpha or defaultValue
			return math.floor(val * 100 + 0.5)
		end

		local function SetValue(value)
			value = Clamp(tonumber(value) or 100, minValue, maxValue)
			GetProfile().assistGlowAlpha = value / 100
			ApplyIfReady("UpdateLayout")
		end

		local setting = Settings.RegisterProxySetting(category, variable, type(defaultValue), name, defaultValue * 100, GetValue, SetValue)
		setting:SetValueChangedCallback(OnSettingChanged)

		local options = Settings.CreateSliderOptions(minValue, maxValue, step)
		if options and options.SetLabelFormatter then
             options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
		Settings.CreateSlider(category, setting, options, "Opacity of the 2px Blue Assisted Highlight border (0-100%).")
	end


	Settings.RegisterAddOnCategory(category)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, name)
    -- Just check if name is 'ActionHud', or assume valid if core loaded
	if event == "ADDON_LOADED" and name == "ActionHud" then
		RegisterSettings()
	end
end)

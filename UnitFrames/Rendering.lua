-- Event-driven values, prediction, status icons, and final layout rendering.
local addonName, ns = ...
local UnitFrames = LibStub("AceAddon-3.0"):GetAddon("ActionHud"):GetModule("UnitFrames")
local Utils = ns.Utils
local IdentitySafety = ns.UnitFrameIdentitySafety
local FormatValue = IdentitySafety.FormatValue

-- Helper to safely return a value or a default, avoiding boolean tests on secrets
local function Pass(v, default)
	if type(v) == "nil" then
		return default or 0
	end
	return v
end

function UnitFrames:UpdateFrameValues(f, updateKind)
	local updateAll = updateKind == nil
	local updateHealth = updateAll or updateKind == "health"
	local updatePower = updateAll or updateKind == "power" or updateKind == "powerLayout"
	local updatePowerLayout = updateAll or updateKind == "powerLayout"
	local updateStatus = updateAll or updateKind == "status"
	local unit = f.unit
	local unitExists, identityAvailable = IdentitySafety.IsTruthy(UnitExists(unit))
	if not identityAvailable then
		-- Do not drive ordinary frame state from a restricted identity result.
		return
	end
	if not unitExists then
		-- Can't modify secure frames during combat
		if not InCombatLockdown() then
			f:Hide()
		end
		return
	end

	local db = self.db.profile.ufConfig[f.unitId]
	if not db or not db.enabled then
		if not InCombatLockdown() then
			f:Hide()
		end
		return
	end
	if not InCombatLockdown() then
		f:Show()
	end
	local perfStart = ns.RecordPerformance and debugprofilestop()

	local curH, maxH
	if updateHealth then
		curH = UnitHealth(unit) -- @scan-ignore: midnight-friendly-unit
		maxH = UnitHealthMax(unit) -- @scan-ignore: midnight-friendly-unit
		f.health:SetMinMaxValues(0, Pass(maxH, 1))
		f.health:SetValue(Pass(curH, 0))
	end
	if updateStatus then
		local r, g, b = IdentitySafety.GetUnitColor(unit, "HEALTH", 0.85)
		f.health:SetStatusBarColor(r, g, b)
	end

	-- 2. Power Bar
	local curP, maxP
	if updatePower then
		curP = UnitPower(unit) -- @scan-ignore: midnight-friendly-unit
		maxP = UnitPowerMax(unit) -- @scan-ignore: midnight-friendly-unit
		f.power:SetMinMaxValues(0, Pass(maxP, 1))
		f.power:SetValue(Pass(curP, 0))
	end
	if updateStatus or updatePowerLayout then
		local powerR, powerG, powerB = IdentitySafety.GetUnitColor(unit, "POWER", 0.85)
		f.power:SetStatusBarColor(powerR, powerG, powerB)
	end

	-- Power visibility and anchors only change when max/display power changes.
	if updatePowerLayout or f._showPower == nil then
		local showPower = false
		local hasPower = false
		if db.powerBarEnabled then
			if
				Utils.IsValueSecret(curP)
				or Utils.IsValueSecret(maxP)
				or type(curP) ~= "number"
				or type(maxP) ~= "number"
			then
				showPower = true
				hasPower = true
			else
				showPower = maxP > 0
				hasPower = maxP > 0
			end
		end
		if f._showPower ~= showPower then
			f._showPower = showPower
			f.power:SetShown(showPower)
		end

		local powerHeight = (db.powerBarEnabled and hasPower) and db.powerBarHeight or 0
		local classHeight = 0
		if f.unitId == "player" and db.classBarEnabled then
			local hasSecondaryPower = IdentitySafety.HasSecondaryPower("player")
			if hasSecondaryPower then
				classHeight = db.classBarHeight or 0
			end
		end

		local actualFrameHeight = db.height
		if not hasPower and db.powerBarEnabled then
			actualFrameHeight = actualFrameHeight - db.powerBarHeight
		end
		if actualFrameHeight < 1 then
			actualFrameHeight = 1
		end

		local healthHeight = actualFrameHeight - powerHeight - classHeight
		if healthHeight < 1 then
			healthHeight = 1
		end

		if
			f._actualFrameHeight ~= actualFrameHeight
			or f._healthHeight ~= healthHeight
			or f._powerHeight ~= powerHeight
			or f._classHeight ~= classHeight
		then
			f._healthHeight = healthHeight
			f._powerHeight = powerHeight
			f._classHeight = classHeight
			if not InCombatLockdown() then
				f:SetHeight(actualFrameHeight)
				f._actualFrameHeight = actualFrameHeight
				local container = self.containers and self.containers[f.unitId]
				if container then
					container:SetHeight(actualFrameHeight)
				end
			else
				-- Keep the applied height invalid until protected resizing is allowed.
				f._actualFrameHeight = nil
				if not self._pendingEnabledState then
					self._pendingEnabledState = true
					self:UpdateLayout()
				end
			end

			f.health:ClearAllPoints()
			f.health:SetPoint("TOPLEFT", f, "TOPLEFT")
			f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT")
			f.health:SetHeight(healthHeight)

			f.power:ClearAllPoints()
			f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT")
			f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT")
			f.power:SetHeight(powerHeight)

			f.class:ClearAllPoints()
			f.class:SetPoint("TOPLEFT", f.power, "BOTTOMLEFT")
			f.class:SetPoint("TOPRIGHT", f.power, "BOTTOMRIGHT")
			f.class:SetHeight(classHeight)
		end

		local showClass = false
		if f.unitId == "player" and db.classBarEnabled then
			showClass = IdentitySafety.HasSecondaryPower("player")
		end
		if f._showClass ~= showClass then
			f._showClass = showClass
			f.class:SetShown(showClass)
		end
	end

	-- Class resource values can change on ordinary power events without needing
	-- to rebuild the surrounding unit-frame layout.
	if updatePower and f._showClass then
			local curC = UnitPower("player", nil, true) -- @scan-ignore: midnight-player-only
			local maxC = UnitPowerMax("player", nil, true) -- @scan-ignore: midnight-player-only
			f.class:SetMinMaxValues(0, Pass(maxC, 1))
			f.class:SetValue(Pass(curC, 0))
	end

	-- 4. Heal Prediction & Absorbs
	if updateHealth then
		-- Get absorbs directly like DandersFrames does (StatusBar handles secrets natively)
		local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) -- @scan-ignore: midnight-friendly-unit

		-- Show absorb values without comparing restricted numbers.
		local showAbsorb = false
		if absorbs ~= nil then
			showAbsorb = Utils.IsValueSecret(absorbs) or (type(absorbs) == "number" and absorbs ~= 0)
		end

		if showAbsorb then
			f.health.absorb:SetMinMaxValues(0, Pass(maxH, 1))
			f.health.absorb:SetValue(absorbs)
			f.health.absorb:Show()
		else
			f.health.absorb:Hide()
		end

		-- Heal Prediction (only for incoming heals, not absorbs)
		local incomingHeals = 0
		if UnitGetIncomingHeals then
			incomingHeals = UnitGetIncomingHeals(unit) -- @scan-ignore: midnight-friendly-unit
		end

		if type(incomingHeals) == "number" and not Utils.IsValueSecret(incomingHeals) and incomingHeals > 0
			and type(curH) == "number" and not Utils.IsValueSecret(curH) and type(maxH) == "number"
		then
			f.health.predict:SetMinMaxValues(0, Pass(maxH, 1))
			f.health.predict:SetValue(curH + incomingHeals)
			f.health.predict:Show()
		else
			f.health.predict:Hide()
		end
	end

	-- 5. Text Display (The "Gold Standard" Pattern)
	-- Health Text
	if updateAll and db.healthText.name.enabled then
		local rawName = GetUnitName(unit, true)
		local name = IdentitySafety.Get(rawName)
		local fontString = f.healthElements.name.fontString
		pcall(fontString.SetText, fontString, name)
	end

	if updateAll and db.healthText.level.enabled then
		local rawLevel = UnitLevel(unit)
		local level = IdentitySafety.Get(rawLevel)
		local fontString = f.healthElements.level.fontString
		pcall(fontString.SetText, fontString, level)
	end

	if updateHealth and db.healthText.value.enabled then
		local displayH = UnitHealth(unit, true) -- @scan-ignore: midnight-friendly-unit
		local displayMaxH = UnitHealthMax(unit, true) -- @scan-ignore: midnight-friendly-unit
		local hStr = FormatValue(displayH)
		local mStr = FormatValue(displayMaxH)
		local fontString = f.healthElements.value.fontString
		pcall(fontString.SetFormattedText, fontString, "%s/%s", hStr, mStr)
	end

	-- Percent display is disabled due to Midnight secret value issues
	-- Keeping values only for now
	if updateAll and f.healthElements.percent then
		f.healthElements.percent.fontString:SetText("")
		f.healthElements.percent.fontString:Hide()
	end

	-- Power Text
	if updatePower and db.powerText.value.enabled and f.powerElements.value then
		local displayP = UnitPower(unit, nil, true) -- @scan-ignore: midnight-friendly-unit
		local displayMaxP = UnitPowerMax(unit, nil, true) -- @scan-ignore: midnight-friendly-unit
		local pStr = FormatValue(displayP)
		local pmStr = FormatValue(displayMaxP)
		local fontString = f.powerElements.value.fontString
		pcall(fontString.SetFormattedText, fontString, "%s/%s", pStr, pmStr)
	end

	-- Percent display is disabled due to Midnight secret value issues
	-- Keeping values only for now
	if updateAll and f.powerElements.percent then
		f.powerElements.percent.fontString:SetText("")
		f.powerElements.percent.fontString:Hide()
	end

	-- 6. Status Icons
	if updateStatus then
		local showAllIcons = self.db.profile.ufShowAllIcons or false
		for iconId, tex in pairs(f.icons) do
			local config = db.icons and db.icons[iconId]
			if config and config.enabled then
				local show, texture, texCoord = IdentitySafety.GetStatusIconState(iconId, unit, showAllIcons)
				if texCoord and tex._texCoord ~= texCoord then
					tex:SetTexCoord(unpack(texCoord))
					tex._texCoord = texCoord
				end
				if texture and tex._texture ~= texture then
					tex:SetTexture(texture)
					tex._texture = texture
				end
				if show then
					if not tex._shown then
						tex:Show()
						tex._shown = true
					end
				elseif tex._shown ~= false then
					tex:Hide()
					tex._shown = false
				end
			else
				if tex._shown ~= false then
					tex:Hide()
					tex._shown = false
				end
			end
		end
	end
	if perfStart then ns.RecordPerformance("UnitFramesUpdate", perfStart) end
end

function UnitFrames:RenderLayout()
	self:UpdateAll()
	self:ApplyBlizzardFrameVisibility()
end

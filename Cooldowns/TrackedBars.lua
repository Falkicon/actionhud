local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedBars = addon:NewModule("TrackedBars", "AceEvent-3.0")
local Manager = ns.CooldownManager
local Utils = ns.Utils

-- Style-only approach: We hook into Blizzard's BuffBarCooldownViewer frame
-- and apply custom styling. Position is controlled by Blizzard's EditMode.
-- This is similar to how ClassyMap styles the minimap without moving it.

local BLIZZARD_FRAME_NAME = "BuffBarCooldownViewer"

local isStylingActive = false
local hooksInstalled = false

function TrackedBars:OnInitialize()
	self.db = addon.db
end

function TrackedBars:OnEnable()
	addon:Log("TrackedBars:OnEnable (style-only mode)", "discovery")

	-- Register for combat end to apply deferred styling
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")

	-- Delay initial setup to ensure Blizzard frames are loaded
	C_Timer.After(0.5, function()
		self:SetupStyling()
	end)
end

function TrackedBars:OnDisable()
	-- Note: Can't fully undo styling due to hooksecurefunc limitations
	isStylingActive = false
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

-- When combat ends, apply styling to any frames that were acquired during combat
function TrackedBars:OnCombatEnd()
	if isStylingActive then
		self:ForceStyleAllItems()
	end
end

-- Get the Blizzard frame we're styling
function TrackedBars:GetBlizzardFrame()
	return _G[BLIZZARD_FRAME_NAME]
end

-- Install hooks on the Blizzard frame (only once, can't be removed)
function TrackedBars:InstallHooks()
	if hooksInstalled then
		return true
	end

	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		addon:Log("TrackedBars: BuffBarCooldownViewer not found for hooks", "discovery")
		return false
	end

	-- Hook RefreshLayout to re-apply our styling after Blizzard updates
	hooksecurefunc(blizzFrame, "RefreshLayout", function()
		if isStylingActive then
			self:ApplyStyling()
		end
	end)

	-- Hook OnAcquireItemFrame to style individual items as they're created
	hooksecurefunc(blizzFrame, "OnAcquireItemFrame", function(_, itemFrame)
		if isStylingActive then
			-- Use async injection to avoid taint cascade in combat
			C_Timer.After(0, function()
				local success, err = pcall(function()
					self:StyleItemFrame(itemFrame)
				end)
				if not success then
					addon:Log("TrackedBars: Error styling item frame: " .. tostring(err), "frames")
				end
			end)
		end
	end)

	hooksInstalled = true
	addon:Log("TrackedBars: Hooks installed on BuffBarCooldownViewer", "discovery")
	return true
end

-- Apply styling to the frame and all existing items
function TrackedBars:ApplyStyling()
	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		return
	end

	-- Main frame properties are safe to set in hooks
	-- (Add any main frame styling here if needed)
end

-- Force style all active items (unsafe in Blizzard hooks, call only from settings/enable)
function TrackedBars:ForceStyleAllItems()
	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame or not blizzFrame.itemFramePool then
		return
	end

	local count = 0
	local success, err = pcall(function()
		for itemFrame in blizzFrame.itemFramePool:EnumerateActive() do
			self:StyleItemFrame(itemFrame)
			count = count + 1
		end
	end)

	if not success then
		addon:Log("TrackedBars: ForceStyleAllItems failed: " .. tostring(err), "frames")
	end
end

-- Style an individual bar item frame
function TrackedBars:StyleItemFrame(itemFrame)
	if not itemFrame then
		return
	end

	-- On Royal clients, we only style if we have the new native timer APIs
	-- to prevent secret value crashes.
	if Utils.Cap.IsRoyal and not itemFrame.Bar.SetTimerDuration then
		return
	end

	local p = self.db.profile

	-- Stripping decorations (Utils helper handles combat safety)
	self:StripBlizzardDecorations(itemFrame)

	-- Compact mode: Hide the bar, keep the icon
	if p.barsCompactMode then
		if itemFrame.Bar then
			if InCombatLockdown() then
				itemFrame.Bar:SetAlpha(0)
			else
				itemFrame.Bar:Hide()
			end
		end

		-- Timer on icon: Reparent Duration FontString to the Icon frame
		if p.barsTimerOnIcon and itemFrame.Bar and itemFrame.Bar.Duration then
			local duration = itemFrame.Bar.Duration
			-- ONLY reparent and move anchors outside combat to avoid taint
			if not InCombatLockdown() then
				duration:SetParent(itemFrame.Icon)
				duration:ClearAllPoints()
				duration:SetPoint("CENTER", itemFrame.Icon, "CENTER", 0, 0)
				duration:SetJustifyH("CENTER")
				duration:SetJustifyV("MIDDLE")
				duration:Show()
				-- Use a readable font with outline for visibility on icon
				duration:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
				duration:SetDrawLayer("OVERLAY", 7)

				-- Move stack count to bottom-right corner to avoid overlap with centered timer
				if itemFrame.Icon and itemFrame.Icon.Applications then
					local apps = itemFrame.Icon.Applications
					apps:ClearAllPoints()
					apps:SetPoint("BOTTOMRIGHT", itemFrame.Icon, "BOTTOMRIGHT", -1, 1)
					apps:SetJustifyH("RIGHT")
				end
			end
		end
	else
		-- Normal mode: Show the bar
		if itemFrame.Bar and not InCombatLockdown() then
			itemFrame.Bar:Show()
		end

		-- Apply custom timer font size if specified
		local timerSize = p.barsTimerFontSize or "medium"
		if timerSize then
			local fontName = Utils.GetTimerFont(timerSize)
			local fontObject = fontName and _G[fontName]
			if fontObject then
				if itemFrame.Bar and itemFrame.Bar.Duration then
					itemFrame.Bar.Duration:SetFontObject(fontObject)
				end
				if itemFrame.Bar and itemFrame.Bar.Name then
					itemFrame.Bar.Name:SetFontObject(fontObject)
				end
			end
		end
	end

	-- Apply custom count font size if specified (numeric)
	local countSize = p.barsCountFontSize or 10
	if countSize and type(countSize) == "number" then
		local iconFrame = itemFrame.Icon
		if iconFrame and iconFrame.Applications then
			iconFrame.Applications:SetFont("Fonts\\FRIZQT__.TTF", countSize, "OUTLINE")
		end
	end

	-- Apply standard icon crop (safe texture coordinate change)
	if itemFrame.Icon and itemFrame.Icon.Icon then
		Utils.ApplyIconCrop(itemFrame.Icon.Icon, 1, 1)
	end
end

-- Remove Blizzard's decorative textures (mask, overlay, shadow, bar background)
-- Called every time to ensure decorations stay hidden
function TrackedBars:StripBlizzardDecorations(itemFrame)
	if not itemFrame then
		return
	end

	-- Strip decorations from the Icon frame
	if itemFrame.Icon then
		Utils.StripBlizzardDecorations(itemFrame.Icon)
	end

	-- Strip decorations from the Bar frame
	if itemFrame.Bar then
		Utils.StripBlizzardDecorations(itemFrame.Bar)
	end
end

-- Main setup function
function TrackedBars:SetupStyling()
	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		addon:Log("TrackedBars: BuffBarCooldownViewer not available yet", "discovery")
		C_Timer.After(1.0, function()
			self:SetupStyling()
		end)
		return
	end

	local p = self.db.profile
	local blizzEnabled = Manager:IsBlizzardCooldownViewerEnabled()

	if not p.styleTrackedBars or not blizzEnabled then
		isStylingActive = false
		addon:Log("TrackedBars: Styling disabled", "discovery")
		return
	end

	-- Install hooks (only once)
	if not self:InstallHooks() then
		return
	end

	isStylingActive = true

	-- Apply initial styling to existing items
	-- This is safe here because it's called from OnEnable/C_Timer, not a Blizzard hook
	self:ForceStyleAllItems()

	addon:Log("TrackedBars: Styling active", "discovery")
end

-- Update styling (called when settings change)
function TrackedBars:UpdateLayout()
	self:SetupStyling()

	-- Debug Container Visual
	local blizzFrame = self:GetBlizzardFrame()
	if blizzFrame then
		Manager:UpdateFrameDebug(blizzFrame, { r = 0, g = 1, b = 0 }) -- Green for Bars
		addon:UpdateLayoutOutline(blizzFrame, "Tracked Bars")
	end

	-- Force re-apply styling to all existing frames if active
	if isStylingActive then
		self:ForceStyleAllItems()
	end
end

local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local TrackedDefensives = addon:NewModule("TrackedDefensives", "AceEvent-3.0")
local Utils = ns.Utils

-- Style-only approach: We hook into Blizzard's ExternalDefensivesFrame
-- and apply custom styling. Position is controlled by Blizzard's EditMode.
-- This frame only exists in WoW 12.0 (Midnight) and later.

local BLIZZARD_FRAME_NAME = "ExternalDefensivesFrame"

local isStylingActive = false
local hooksInstalled = false

function TrackedDefensives:OnInitialize()
	self.db = addon.db
end

function TrackedDefensives:OnEnable()
	-- Only enable if the frame exists (12.0+)
	if not _G[BLIZZARD_FRAME_NAME] then
		addon:Log("TrackedDefensives: ExternalDefensivesFrame not available (requires 12.0+)", "discovery")
		return
	end

	addon:Log("TrackedDefensives:OnEnable (style-only mode)", "discovery")

	-- Delay initial setup to ensure Blizzard frames are loaded
	C_Timer.After(0.5, function()
		self:SetupStyling()
	end)
end

function TrackedDefensives:OnDisable()
	isStylingActive = false
end

-- Get the Blizzard frame we're styling
function TrackedDefensives:GetBlizzardFrame()
	return _G[BLIZZARD_FRAME_NAME]
end

-- Install hooks on the Blizzard frame (only once, can't be removed)
function TrackedDefensives:InstallHooks()
	if hooksInstalled then
		return true
	end

	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		addon:Log("TrackedDefensives: ExternalDefensivesFrame not found for hooks", "discovery")
		return false
	end

	-- The ExternalDefensivesFrame uses AuraContainer for icons
	-- Hook into the container's layout updates
	if blizzFrame.AuraContainer then
		-- Hook the container's layout function if it exists
		if blizzFrame.AuraContainer.UpdateAuraFrames then
			hooksecurefunc(blizzFrame.AuraContainer, "UpdateAuraFrames", function()
				if isStylingActive then
					self:ApplyStyling()
				end
			end)
		end
	end

	-- Also hook Show to catch initial display
	hooksecurefunc(blizzFrame, "Show", function()
		if isStylingActive then
			C_Timer.After(0.1, function()
				self:ApplyStyling()
			end)
		end
	end)

	hooksInstalled = true
	addon:Log("TrackedDefensives: Hooks installed on ExternalDefensivesFrame", "discovery")
	return true
end

-- Apply styling to the frame and all existing items
function TrackedDefensives:ApplyStyling()
	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		return
	end

	-- Main frame properties safe to set in hooks
end

-- Force style all active items (unsafe in hooks, call only from settings/enable)
function TrackedDefensives:ForceStyleAllItems()
	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame or not blizzFrame.AuraContainer then
		return
	end

	local children = { blizzFrame.AuraContainer:GetChildren() }
	for _, child in ipairs(children) do
		self:StyleItemFrame(child)
	end
end

-- Style an individual item frame (aura icon)
function TrackedDefensives:StyleItemFrame(itemFrame)
	if not itemFrame then
		return
	end

	local p = self.db.profile

	-- Remove Blizzard's decorative elements
	self:StripBlizzardDecorations(itemFrame)

	-- Apply custom timer font size if specified
	-- SetCountdownFont requires a font NAME string
	local timerSize = p.defensivesTimerFontSize or "medium"
	if timerSize then
		local fontName = Utils.GetTimerFont(timerSize)
		if fontName then
			-- Try common cooldown locations
			if itemFrame.Cooldown then
				itemFrame.Cooldown:SetCountdownFont(fontName)
			end
			if itemFrame.cooldown then
				itemFrame.cooldown:SetCountdownFont(fontName)
			end
		end
	end

	-- Apply custom count font size if specified (numeric)
	local countSize = p.defensivesCountFontSize or 10
	if countSize and type(countSize) == "number" then
		-- Try common count locations
		if itemFrame.Count then
			itemFrame.Count:SetFont("Fonts\\FRIZQT__.TTF", countSize, "OUTLINE")
		end
		if itemFrame.count then
			itemFrame.count:SetFont("Fonts\\FRIZQT__.TTF", countSize, "OUTLINE")
		end
	end
end

-- Remove Blizzard's decorative textures
-- Called every time to ensure decorations stay hidden
function TrackedDefensives:StripBlizzardDecorations(itemFrame)
	if not itemFrame then
		return
	end

	Utils.StripBlizzardDecorations(itemFrame)

	-- Apply standard icon crop to the icon texture
	if itemFrame.Icon then
		Utils.ApplyIconCrop(itemFrame.Icon, 1, 1)
	end
	if itemFrame.icon then
		Utils.ApplyIconCrop(itemFrame.icon, 1, 1)
	end
end

-- Main setup function
function TrackedDefensives:SetupStyling()
	local blizzFrame = self:GetBlizzardFrame()
	if not blizzFrame then
		addon:Log("TrackedDefensives: ExternalDefensivesFrame not available", "discovery")
		return
	end

	local p = self.db.profile

	if not p.styleExternalDefensives then
		isStylingActive = false
		addon:Log("TrackedDefensives: Styling disabled", "discovery")
		return
	end

	-- Install hooks (only once)
	if not self:InstallHooks() then
		return
	end

	isStylingActive = true

	-- Apply initial styling to existing items
	self:ForceStyleAllItems()

	addon:Log("TrackedDefensives: Styling active", "discovery")
end

-- Update styling (called when settings change)
function TrackedDefensives:UpdateLayout()
	self:SetupStyling()

	-- Debug Container Visual
	local blizzFrame = self:GetBlizzardFrame()
	if blizzFrame then
		addon:UpdateFrameDebug(blizzFrame, { r = 1, g = 0, b = 1 }) -- Magenta for Defensives
		addon:UpdateLayoutOutline(blizzFrame, "External Defensives")
	end

	-- Force re-apply styling to all existing frames if active
	if isStylingActive then
		self:ForceStyleAllItems()
	end
end

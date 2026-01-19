local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local Trinkets = addon:NewModule("Trinkets", "AceEvent-3.0")
local Utils = ns.Utils

local container
local trinketFrames = {}
local TRINKET_SLOTS = { 13, 14 }

-- Local upvalues for performance
local GetInventoryItemID = GetInventoryItemID
local C_Item = C_Item
local C_Spell = C_Spell
local InCombatLockdown = InCombatLockdown
local GetInventoryItemCooldown = Utils.GetInventoryItemCooldownSafe

function Trinkets:OnInitialize()
	self.db = addon.db
end

function Trinkets:OnEnable()
	self:CreateFrames()

	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "UpdateTrinkets")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateTrinkets")
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "UpdateCooldowns")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")

	-- Ensure we update on load
	C_Timer.After(0.5, function()
		self:UpdateTrinkets()
		self:UpdateLayout()
	end)
end

function Trinkets:CreateFrames()
	if container then
		return
	end

	local main = _G["ActionHudFrame"]
	if not main then
		return
	end

	-- Create container using DraggableContainer for independent positioning support
	local DraggableContainer = ns.DraggableContainer
	if DraggableContainer then
		container = DraggableContainer:Create({
			moduleId = "trinkets",
			parent = main,
			db = self.db,
			xKey = "trinketsXOffset",
			yKey = "trinketsYOffset",
			defaultX = 150,
			defaultY = 0,
			size = { width = 68, height = 32 },
		})
	end

	-- Fallback if DraggableContainer not available
	if not container then
		container = CreateFrame("Frame", "ActionHudTrinkets", main)
	end

	for i = 1, 2 do
		local f = CreateFrame("Frame", nil, container)
		f:SetSize(32, 32)

		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetAllPoints()

		f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
		f.cooldown:SetAllPoints()
		f.cooldown:SetDrawEdge(false)
		f.cooldown:SetHideCountdownNumbers(false)

		f.slot = TRINKET_SLOTS[i]
		trinketFrames[i] = f
	end
end

function Trinkets:UpdateTrinkets()
	if not container then
		return
	end

	local p = self.db.profile
	if not p.trinketsEnabled then
		container:Hide()
		return
	end

	local visibleCount = 0
	for i = 1, 2 do
		local f = trinketFrames[i]
		local itemID = GetInventoryItemID("player", f.slot)

		-- In 11.0+, GetInventoryItemID might return 0 instead of nil
		if itemID and itemID > 0 then
			local itemSpellName, itemSpellID = Utils.GetItemSpellSafe(itemID)

			addon:Log(
				string.format("Trinket slot %d: ID=%d, SpellID=%s", f.slot, itemID, tostring(itemSpellID or "nil")),
				"discovery"
			)

			if itemSpellID then
				local itemIcon = C_Item.GetItemIconByID(itemID)
				f.icon:SetTexture(itemIcon)
				Utils.ApplyIconCrop(f.icon, p.trinketsIconWidth, p.trinketsIconHeight)

				f.itemSpellID = itemSpellID
				f:Show()
				visibleCount = visibleCount + 1
			else
				f:Hide()
				f.itemSpellID = nil
			end
		else
			f:Hide()
			f.itemSpellID = nil
		end
	end

	if visibleCount > 0 then
		container:Show()
		self:UpdateLayout()
	else
		container:Hide()
	end

	self:UpdateCooldowns()
end

function Trinkets:UpdateCooldowns()
	if not container or not container:IsShown() then
		return
	end

	for i = 1, 2 do
		local f = trinketFrames[i]
		if f:IsShown() then
			local startTime, duration, enabled = Utils.GetInventoryItemCooldownSafe("player", f.slot)

			-- In Midnight, if enabled is a secret value, assume it's true to show the swipe.
			local isEnabled = enabled
			if Utils.IsValueSecret(enabled) then
				isEnabled = true
			end

			-- Handle secret duration or normal comparison
			local showSwipe = isEnabled
				and duration
				and (Utils.IsValueSecret(duration) or Utils.SafeCompare(duration, 0, ">"))

			if showSwipe then
				f.cooldown:SetCooldown(startTime, duration)
				f.cooldown:Show()
			else
				f.cooldown:Clear()
			end

			-- Alpha/Glow logic based on usability
			if f.itemSpellID then
				local isUsable = C_Spell.IsSpellUsable(f.itemSpellID)
				-- If usability is secret, keep at full alpha
				local alpha = 1.0
				if not Utils.IsValueSecret(isUsable) and isUsable == false then
					alpha = 0.6
				end
				f:SetAlpha(alpha)
			else
				f:SetAlpha(1.0)
			end
		end
	end
end

function Trinkets:OnCombatStart() end

function Trinkets:OnCombatEnd()
	self:UpdateCooldowns()
end

function Trinkets:UpdateLayout()
	if not container then
		return
	end

	local p = self.db.profile
	if not p.trinketsEnabled then
		container:Hide()
		return
	end

	local spacing = 2

	local width = p.trinketsIconWidth
	local height = p.trinketsIconHeight

	-- Check if we're in stack mode
	local LM = addon:GetModule("LayoutManager", true)
	local inStack = LM and LM:IsModuleInStack("trinkets")
	local main = _G["ActionHudFrame"]

	-- First pass: count visible trinkets and prepare frames
	local visibleFrames = {}
	for i = 1, 2 do
		local f = trinketFrames[i]
		if f:IsShown() then
			f:SetSize(width, height)
			Utils.ApplyIconCrop(f.icon, width, height)
			local fontName = Utils.GetTimerFont(p.trinketsTimerFontSize)
			f.cooldown:SetCountdownFont(fontName)
			table.insert(visibleFrames, f)
		end
	end

	-- Calculate container size based on visible count (min 1 for positioning)
	local visibleCount = math.max(#visibleFrames, 1)
	local actualWidth = (visibleCount * width) + ((visibleCount - 1) * spacing)

	container:ClearAllPoints()

	if inStack and LM then
		-- Stack mode: use full HUD width from LayoutManager
		local containerWidth = LM:GetMaxWidth()
		if containerWidth <= 0 then
			containerWidth = 120 -- Fallback
		end
		local yOffset = LM:GetModulePosition("trinkets")
		container:SetSize(containerWidth, height)
		container:SetPoint("TOP", main, "TOP", 0, yOffset)
		container:EnableMouse(false)

		-- Center icons within full-width container
		if #visibleFrames > 0 then
			local startX = -actualWidth / 2
			for i, f in ipairs(visibleFrames) do
				f:ClearAllPoints()
				local xPos = startX + ((i - 1) * (width + spacing))
				f:SetPoint("LEFT", container, "CENTER", xPos, 0)
			end
		end

		-- Report height to LayoutManager
		LM:SetModuleHeight("trinkets", height)
	else
		-- Independent mode: fit to visible content
		container:SetSize(actualWidth, height)

		-- DraggableContainer handles positioning
		local DraggableContainer = ns.DraggableContainer
		if DraggableContainer then
			DraggableContainer:UpdatePosition(container)
			DraggableContainer:UpdateOverlay(container)
		else
			-- Fallback positioning
			local xOffset = p.trinketsXOffset
			local yOffset = p.trinketsYOffset
			container:SetPoint("CENTER", main, "CENTER", xOffset, yOffset)
		end

		-- Position icons based on grow direction
		if #visibleFrames > 0 then
			local growDir = p.trinketsGrowDirection or "RIGHT"
			for i, f in ipairs(visibleFrames) do
				f:ClearAllPoints()
				if growDir == "LEFT" then
					-- Grow left: first icon on right, others to the left
					if i == 1 then
						f:SetPoint("RIGHT", container, "RIGHT", 0, 0)
					else
						f:SetPoint("RIGHT", visibleFrames[i - 1], "LEFT", -spacing, 0)
					end
				else
					-- Grow right (default): first icon on left, others to the right
					if i == 1 then
						f:SetPoint("LEFT", container, "LEFT", 0, 0)
					else
						f:SetPoint("LEFT", visibleFrames[i - 1], "RIGHT", spacing, 0)
					end
				end
			end
		end

		-- Release height reservation when not in stack
		local LM = addon:GetModule("LayoutManager", true)
		if LM then
			LM:SetModuleHeight("trinkets", 0)
		end
	end

	if #visibleFrames > 0 then
		container:Show()
	else
		container:Hide()
	end

	-- Debug outline
	addon:UpdateLayoutOutline(container, "Trinkets", "trinkets")
end

-- Stack layout functions - return real values when module is enabled
function Trinkets:CalculateHeight()
	local p = self.db.profile
	if not p.trinketsEnabled then
		return 0
	end
	return p.trinketsIconHeight or 32
end

function Trinkets:GetLayoutWidth()
	local p = self.db.profile
	if not p.trinketsEnabled then
		return 0
	end
	-- Width of both trinkets + spacing
	local spacing = 2
	return (p.trinketsIconWidth or 32) * 2 + spacing
end

function Trinkets:ApplyLayoutPosition()
	self:UpdateLayout()
end

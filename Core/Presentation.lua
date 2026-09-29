local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ActionHud")
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")

-- Readability settings and style presets. Presets only touch the presentation
-- keys listed in GROUPS: selections, enablement, sounds, and positions are never
-- included. Applying a preset records the previous values so the most recent
-- application can be undone. Nothing here runs automatically on upgrade.
local Presentation = {}
ns.Presentation = Presentation

local UF_FRAMES = { "player", "target", "targettarget", "focus" }
local UF_BLOCKS = { "healthText", "powerText" }
local UF_ELEMENTS = { "name", "level", "value", "percent" }

local function UnitFramePaths(field)
	local paths = {}
	for _, frame in ipairs(UF_FRAMES) do
		for _, block in ipairs(UF_BLOCKS) do
			for _, element in ipairs(UF_ELEMENTS) do
				local config = ns.defaults.profile.ufConfig[frame]
				if config and config[block] and config[block][element] then
					paths[#paths + 1] = { "ufConfig", frame, block, element, field }
				end
			end
		end
	end
	return paths
end

-- Each group is one player-facing setting. `paths` lists the profile keys it writes.
-- `module` names the settings tab that owns it; modules only support what they list.
local GROUPS = {
	{ id = "pbIcon", module = L["Player Buffs"], label = L["Icon size"], paths = { { "playerBuffsIconSize" } } },
	{ id = "pbSpacing", module = L["Player Buffs"], label = L["Icon spacing"], paths = { { "playerBuffsSpacing" } } },
	{ id = "pbTimer", module = L["Player Buffs"], label = L["Countdown text size"], paths = { { "playerBuffsTimerFontSize" } } },
	{ id = "pbCount", module = L["Player Buffs"], label = L["Stack text size"], paths = { { "playerBuffsCountFontSize" } } },
	{ id = "pbOutline", module = L["Player Buffs"], label = L["Text outline"], paths = { { "playerBuffsTextOutline" } } },
	{ id = "pbBackground", module = L["Player Buffs"], label = L["Slot background"], paths = { { "playerBuffsBackgroundOpacity" } } },
	{ id = "pbBorder", module = L["Player Buffs"], label = L["Slot border"], paths = { { "playerBuffsBorderSize" } } },
	{ id = "abCooldown", module = L["Action Bars"], label = L["Cooldown text size"], paths = { { "cooldownFontSize" } } },
	{ id = "abCount", module = L["Action Bars"], label = L["Stack text size"], paths = { { "countFontSize" } } },
	{ id = "abBackground", module = L["Action Bars"], label = L["Slot background"], paths = { { "opacity" } } },
	{ id = "trTimer", module = L["Trinket Bar"], label = L["Countdown text size"], paths = { { "trinketsTimerFontSize" } } },
	{ id = "coIcon", module = L["Consumables"], label = L["Icon size"], paths = { { "consumablesIconSize" } } },
	{ id = "coCount", module = L["Consumables"], label = L["Count text size"], paths = { { "consumablesCountFontSize" } } },
	{ id = "coTimer", module = L["Consumables"], label = L["Countdown text size"], paths = { { "consumablesTimerFontSize" } } },
	{ id = "ufSize", module = L["Unit Frames"], label = L["Text size"], paths = UnitFramePaths("size") },
	{ id = "ufOutline", module = L["Unit Frames"], label = L["Text outline"], paths = UnitFramePaths("outline") },
}
local GROUP_BY_ID = {}
for _, group in ipairs(GROUPS) do GROUP_BY_ID[group.id] = group end

-- Starting points; exact values come from visual testing and can be tuned here.
local PRESETS = {
	{ id = "large", name = L["Large Text"],
		description = L["Bigger icons and text for easier reading."],
		values = { pbIcon = 36, pbSpacing = 4, pbTimer = 16, pbCount = 16, pbOutline = true, pbBackground = 0.35,
			abCooldown = 12, abCount = 12, trTimer = "large", coIcon = 36, coCount = 16, coTimer = "large",
			ufSize = 14 } },
	{ id = "contrast", name = L["High Contrast"],
		description = L["Solid slot backgrounds, borders, and outlined text so icons stand out."],
		values = { pbTimer = 14, pbCount = 14, pbOutline = true, pbBackground = 0.75, pbBorder = 2,
			abBackground = 0.6, trTimer = "large", coCount = 14, coTimer = "large", ufOutline = "OUTLINE" } },
	{ id = "compact", name = L["Compact"],
		description = L["Smaller icons and text to use less screen space."],
		values = { pbIcon = 22, pbSpacing = 1, pbTimer = 10, pbCount = 10, pbBackground = 0,
			abCooldown = 7, abCount = 7, trTimer = "small", coIcon = 22, coCount = 10, coTimer = "small",
			ufSize = 10 } },
}
local PRESET_BY_ID = {}
for _, preset in ipairs(PRESETS) do PRESET_BY_ID[preset.id] = preset end

function Presentation:GetPresets() return PRESETS end
function Presentation:GetPreset(id) return PRESET_BY_ID[id] end
function Presentation:GetGroups() return GROUPS end

local function GetPath(root, path)
	local node = root
	for index = 1, #path do
		if type(node) ~= "table" then return nil end
		node = node[path[index]]
	end
	return node
end

local function SetPath(root, path, value)
	local node = root
	for index = 1, #path - 1 do
		if type(node[path[index]]) ~= "table" then return false end
		node = node[path[index]]
	end
	node[path[#path]] = value
	return true
end

local function Display(value)
	if type(value) == "boolean" then return value and L["On"] or L["Off"] end
	if type(value) == "number" then return tostring(math.floor(value * 100 + 0.5) / 100) end
	return tostring(value)
end

-- Effective single value for a group (first path); presets override when given.
function Presentation:GetValue(groupId, presetId)
	local preset = presetId and PRESET_BY_ID[presetId]
	if preset and preset.values[groupId] ~= nil then return preset.values[groupId] end
	local group = GROUP_BY_ID[groupId]
	return group and GetPath(addon.db.profile, group.paths[1])
end

-- What applying a preset would change: one row per differing group.
function Presentation:GetChanges(presetId)
	local preset = PRESET_BY_ID[presetId]
	local changes = {}
	if not preset then return changes end
	for _, group in ipairs(GROUPS) do
		local target = preset.values[group.id]
		if target ~= nil then
			local differs, current = false, GetPath(addon.db.profile, group.paths[1])
			for _, path in ipairs(group.paths) do
				if GetPath(addon.db.profile, path) ~= target then differs = true end
			end
			if differs then
				changes[#changes + 1] = { module = group.module, label = group.label,
					from = Display(current), to = Display(target) }
			end
		end
	end
	return changes
end

function Presentation:DescribeChanges(presetId)
	local changes = self:GetChanges(presetId)
	if #changes == 0 then return L["This preset would not change anything in the current profile."] end
	local lines = {}
	for _, change in ipairs(changes) do
		lines[#lines + 1] = string.format("%s: %s (%s -> %s)", change.module, change.label, change.from, change.to)
	end
	return table.concat(lines, "\n")
end

local function Refresh()
	addon:RefreshLayout()
	local playerBuffs = addon:GetModule("PlayerBuffs", true)
	if playerBuffs and playerBuffs.ApplyStyle then playerBuffs:ApplyStyle() end
	Presentation:RefreshSample()
end

function Presentation:ApplyPreset(presetId)
	local preset = PRESET_BY_ID[presetId]
	if not preset then return false end
	local profile = addon.db.profile
	local saved = {}
	for _, group in ipairs(GROUPS) do
		local target = preset.values[group.id]
		if target ~= nil then
			for _, path in ipairs(group.paths) do
				local old = GetPath(profile, path)
				if old ~= nil and old ~= target then saved[#saved + 1] = { path = path, old = old, new = target } end
			end
		end
	end
	if #saved == 0 then return false end
	-- Only the newest application is kept; earlier undo data is replaced.
	local undo = { preset = presetId, values = {} }
	for index, entry in ipairs(saved) do
		undo.values[index] = { path = entry.path, old = entry.old }
		SetPath(profile, entry.path, entry.new)
	end
	profile.presentationUndo = undo
	Refresh()
	return true
end

function Presentation:CanUndo()
	local undo = addon.db.profile.presentationUndo
	return type(undo) == "table" and type(undo.values) == "table" and #undo.values > 0
end

function Presentation:GetUndoName()
	local undo = addon.db.profile.presentationUndo
	local preset = undo and PRESET_BY_ID[undo.preset]
	return preset and preset.name
end

function Presentation:Undo()
	if not self:CanUndo() then return false end
	local profile = addon.db.profile
	for _, entry in ipairs(profile.presentationUndo.values) do
		SetPath(profile, entry.path, entry.old)
	end
	profile.presentationUndo = nil
	Refresh()
	return true
end

--------------------------------------------------------------------------------
-- Synthetic sample. Uses invented timers and stacks and never reads game state,
-- so it shows how the style reads, not whether a buff works.
--------------------------------------------------------------------------------

local sample
local SAMPLE_ICONS = { 136048, 132333, 135987 }
local FONT_PATH = "Fonts\\ARIALN.TTF"

local function Flags(outline)
	return outline and "OUTLINE" or ""
end

local function BuildSample()
	local frame = CreateFrame("Frame", "ActionHudPresentationSample", UIParent)
	frame:SetSize(360, 230)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints()
	frame.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
	frame.title = frame:CreateFontString(nil, "OVERLAY")
	frame.title:SetFont(FONT_PATH, 13, "OUTLINE")
	frame.title:SetPoint("TOPLEFT", 10, -8)
	frame.title:SetPoint("TOPRIGHT", -34, -8)
	frame.title:SetJustifyH("LEFT")
	frame.note = frame:CreateFontString(nil, "OVERLAY")
	frame.note:SetFont(FONT_PATH, 11, "")
	frame.note:SetPoint("BOTTOMLEFT", 10, 8)
	frame.note:SetPoint("BOTTOMRIGHT", -10, 8)
	frame.note:SetJustifyH("LEFT")
	frame.note:SetText(L["Sample with invented timers and stacks. It does not check live buffs or sounds."])
	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", 2, 2)
	frame.slots = {}
	for index = 1, 3 do
		local slot = CreateFrame("Frame", nil, frame)
		slot.bg = slot:CreateTexture(nil, "BACKGROUND")
		slot.bg:SetAllPoints()
		slot.icon = slot:CreateTexture(nil, "ARTWORK")
		slot.icon:SetAllPoints()
		slot.icon:SetTexture(SAMPLE_ICONS[index])
		slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		slot.border = {}
		for edge = 1, 4 do slot.border[edge] = slot:CreateTexture(nil, "OVERLAY") end
		slot.timer = slot:CreateFontString(nil, "OVERLAY")
		slot.timer:SetPoint("CENTER", slot, "CENTER")
		slot.count = slot:CreateFontString(nil, "OVERLAY")
		slot.count:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
		slot.label = slot:CreateFontString(nil, "OVERLAY")
		slot.label:SetFont(FONT_PATH, 10, "")
		slot.label:SetPoint("TOP", slot, "BOTTOM", 0, -2)
		frame.slots[index] = slot
	end
	frame.actionBar = CreateFrame("Frame", nil, frame)
	frame.actionBar.icon = frame.actionBar:CreateTexture(nil, "ARTWORK")
	frame.actionBar.icon:SetAllPoints()
	frame.actionBar.icon:SetTexture(135987)
	frame.actionBar.cooldown = frame.actionBar:CreateFontString(nil, "OVERLAY")
	frame.actionBar.cooldown:SetPoint("CENTER")
	frame.actionBar.count = frame.actionBar:CreateFontString(nil, "OVERLAY")
	frame.actionBar.count:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.actionBar.label = frame.actionBar:CreateFontString(nil, "OVERLAY")
	frame.actionBar.label:SetFont(FONT_PATH, 10, "")
	frame.actionBar.label:SetPoint("TOP", frame.actionBar, "BOTTOM", 0, -2)
	frame:Hide()
	return frame
end

local function PaintSlot(slot, iconSize, values, state)
	slot:SetSize(iconSize, iconSize)
	slot.bg:SetColorTexture(0, 0, 0, math.max(values.background, state == "inactive" and 0.35 or 0))
	slot.icon:SetAlpha(state == "inactive" and 0.25 or 1)
	slot.icon:SetDesaturated(state == "inactive")
	local border = values.border
	local top, bottom, left, right = slot.border[1], slot.border[2], slot.border[3], slot.border[4]
	for _, edge in ipairs(slot.border) do edge:SetColorTexture(1, 1, 1, 0.95); edge:SetShown(border > 0) end
	top:ClearAllPoints(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(math.max(border, 1))
	bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(math.max(border, 1))
	left:ClearAllPoints(); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(math.max(border, 1))
	right:ClearAllPoints(); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(math.max(border, 1))
	local flags = Flags(values.outline)
	slot.timer:SetFont(FONT_PATH, values.timer, flags)
	slot.count:SetFont(FONT_PATH, values.count, flags)
	slot.timer:SetText(state == "active" and "12" or "")
	slot.count:SetText(state == "active" and "3" or "")
	slot.label:SetText(state == "inactive" and L["Inactive"] or L["Active"])
end

function Presentation:GetSampleValues(presetId)
	local timer = self:GetValue("pbTimer", presetId)
	return {
		icon = self:GetValue("pbIcon", presetId),
		spacing = self:GetValue("pbSpacing", presetId),
		timer = (type(timer) == "number" and timer > 0) and timer or 12,
		count = self:GetValue("pbCount", presetId),
		outline = self:GetValue("pbOutline", presetId) == true,
		background = self:GetValue("pbBackground", presetId) or 0,
		border = self:GetValue("pbBorder", presetId) or 0,
		abCooldown = self:GetValue("abCooldown", presetId),
		abCount = self:GetValue("abCount", presetId),
	}
end

function Presentation:RefreshSample()
	if not sample or not sample:IsShown() then return end
	local values = self:GetSampleValues(sample.presetId)
	local preset = sample.presetId and PRESET_BY_ID[sample.presetId]
	sample.title:SetText(preset and string.format(L["Preview: %s (not applied)"], preset.name) or L["Preview: current settings"])
	local iconSize = math.max(16, math.min(64, values.icon or 28))
	local spacing = values.spacing or 2
	local states = { "active", "active", "inactive" }
	for index, slot in ipairs(sample.slots) do
		slot:ClearAllPoints()
		slot:SetPoint("TOPLEFT", sample, "TOPLEFT", 14 + (index - 1) * (iconSize + spacing), -34)
		PaintSlot(slot, iconSize, values, states[index])
	end
	local abSize = 32
	sample.actionBar:SetSize(abSize, abSize)
	sample.actionBar:ClearAllPoints()
	sample.actionBar:SetPoint("TOPLEFT", sample, "TOPLEFT", 14, -34 - iconSize - 34)
	sample.actionBar.cooldown:SetFont(FONT_PATH, values.abCooldown or 8, "OUTLINE")
	sample.actionBar.count:SetFont(FONT_PATH, values.abCount or 8, "OUTLINE")
	sample.actionBar.cooldown:SetText("8")
	sample.actionBar.count:SetText("2")
	sample.actionBar.label:SetText(L["Action bar sample"])
end

function Presentation:ShowSample(presetId)
	if not sample then sample = BuildSample() end
	sample.presetId = presetId
	sample:Show()
	self:RefreshSample()
end

function Presentation:HideSample()
	if sample then sample:Hide() end
end

function Presentation:IsSampleShown()
	return sample ~= nil and sample:IsShown()
end

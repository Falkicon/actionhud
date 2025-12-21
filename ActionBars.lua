local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local AB = ActionHud:NewModule("ActionBars", "AceEvent-3.0")

local Utils = ns.Utils

-- Local upvalues for performance (hot-path optimization)
local ipairs = ipairs
local GetTime = GetTime
local GetActionBarPage = GetActionBarPage
local GetBonusBarOffset = GetBonusBarOffset
local GetActionInfo = GetActionInfo
local GetActionTexture = GetActionTexture
local GetActionCooldown = GetActionCooldown
local GetActionCount = GetActionCount
local GetMacroSpell = GetMacroSpell
local IsUsableAction = IsUsableAction
local IsActionInRange = IsActionInRange
local math_floor = math.floor

local buttons = {}
local container = nil  -- ActionBars container frame
local layoutCache = {} -- Cache for Edit Mode settings to avoid frequent API calls

-- Helper to fetch Edit Mode settings for a bar
function AB:GetEditModeSettings(barID)
    -- Default to 6x2 (compact) if not syncing or API fails
    local settings = { numRows = 2, numIcons = 12, orientation = 0 }
    
    -- In Midnight, avoid C_EditMode in instances/combat to prevent secret value errors and taint
    if Utils.IS_MIDNIGHT then
        local inInstance, instanceType = IsInInstance()
        if InCombatLockdown() or (inInstance and (instanceType == "raid" or instanceType == "party" or instanceType == "arena")) then
            if layoutCache[barID] then return layoutCache[barID] end
            return settings
        end
    end

    -- Primary method: Find the system frame directly from Edit Mode Manager
    -- This is the most reliable way as it works for both Preset and User layouts.
    if EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames then
        for _, frame in ipairs(EditModeManagerFrame.registeredSystemFrames) do
            if frame.system == Enum.EditModeSystem.ActionBar and frame.systemIndex == barID then
                if frame.GetSettingValue then
                    local rows = frame:GetSettingValue(Enum.EditModeActionBarSetting.NumRows)
                    local icons = frame:GetSettingValue(Enum.EditModeActionBarSetting.NumIcons)
                    local orient = frame:GetSettingValue(Enum.EditModeActionBarSetting.Orientation)
                    
                    if not Utils.IsValueSecret(rows) then settings.numRows = rows end
                    if not Utils.IsValueSecret(icons) then settings.numIcons = icons end
                    if not Utils.IsValueSecret(orient) then settings.orientation = orient end
                    
                    layoutCache[barID] = settings
                    return settings
                end
            end
        end
    end

    -- Secondary method: Parse GetLayouts()
    if not C_EditMode or not C_EditMode.GetLayouts then return settings end

    local ok, layouts = pcall(C_EditMode.GetLayouts)
    if not ok or not layouts then return settings end
    
    -- Find the active layout (could be User or Preset)
    local activeLayout
    if layouts.activeLayoutType == Enum.EditModeLayoutType.Preset then
        -- Presets are handled by the Manager, not returned in the layouts list
        -- We'll try to find it in the manager's combined list if available
        if EditModeManagerFrame and EditModeManagerFrame.layoutInfo then
            activeLayout = EditModeManagerFrame.layoutInfo.layouts[layouts.activeLayoutIndex]
        end
    else
        activeLayout = layouts.layouts[layouts.activeLayoutIndex]
    end

    if activeLayout then
        for _, systemInfo in ipairs(activeLayout.systems) do
            if systemInfo.system == Enum.EditModeSystem.ActionBar and systemInfo.systemIndex == barID then
                for _, settingInfo in ipairs(systemInfo.settings) do
                    local val = settingInfo.value
                    if not Utils.IsValueSecret(val) then
                        if settingInfo.setting == Enum.EditModeActionBarSetting.NumRows then
                            settings.numRows = val
                        elseif settingInfo.setting == Enum.EditModeActionBarSetting.NumIcons then
                            settings.numIcons = val
                        elseif settingInfo.setting == Enum.EditModeActionBarSetting.Orientation then
                            settings.orientation = val
                        end
                    end
                end
                break
            end
        end
    end
    
    -- Update cache
    layoutCache[barID] = settings
    return settings
end

function AB:ClearLayoutCache()
    wipe(layoutCache)
end

function AB:OnEnable()
    -- Create container frame
    local parent = ActionHud.frame
    if not parent then return end
    
    if not container then
        container = CreateFrame("Frame", "ActionHudActionBars", parent)
    end
    
    -- Create Buttons if not already existing
    if #buttons == 0 then
        self:CreateButtons(container)
    end
    
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshAll")
    self:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
        -- Clear cache and delay update to ensure Blizzard's internal state is fully saved
        AB:ClearLayoutCache()
        C_Timer.After(0.5, function() AB:UpdateLayout() end)
    end)
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "RefreshAll")
    self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", "RefreshAll")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "UpdateStateAll")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "UpdateStateAll")
    self:RegisterEvent("ACTIONBAR_UPDATE_STATE", "UpdateStateAll")
    self:RegisterEvent("ACTIONBAR_UPDATE_USABLE", "UpdateStateAll")
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "UpdateStateAll")
    
    -- Hook Edit Mode exit to force a layout refresh
    if EditModeManagerFrame then
        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            AB:ClearLayoutCache()
            AB:UpdateLayout()
        end)
    end

    self:UpdateLayout()
    self:RefreshAll()
end

-- Get container frame
function AB:GetContainer()
    return container
end

-- Calculate the height of this module for LayoutManager
function AB:CalculateHeight()
    if not self:IsEnabled() then return 0 end
    local p = ActionHud.db.profile
    
    local bar1 = self:GetEditModeSettings(1)
    local bar6 = self:GetEditModeSettings(2)
    
    local rows1 = math.max(tonumber(bar1.numRows) or 2, 1)
    local rows6 = math.max(tonumber(bar6.numRows) or 2, 1)
    
    local h1 = rows1 * p.iconHeight
    local h2 = rows6 * p.iconHeight
    local gap = 0 -- No gap between blocks
    
    return h1 + h2 + gap
end

-- Get the width of this module for LayoutManager
function AB:GetLayoutWidth()
    local p = ActionHud.db.profile
    
    local bar1 = self:GetEditModeSettings(1)
    local bar6 = self:GetEditModeSettings(2)
    
    local icons1 = tonumber(bar1.numIcons) or 12
    local rows1 = math.max(tonumber(bar1.numRows) or 2, 1)
    local icons6 = tonumber(bar6.numIcons) or 12
    local rows6 = math.max(tonumber(bar6.numRows) or 2, 1)
    
    local w1 = math.ceil(icons1 / rows1) * p.iconWidth
    local w2 = math.ceil(icons6 / rows6) * p.iconWidth
    
    return math.max(w1, w2)
end

-- Apply position from LayoutManager
function AB:ApplyLayoutPosition()
    if not container then return end
    local LM = ActionHud:GetModule("LayoutManager", true)
    if not LM then return end
    
    local yOffset = LM:GetModulePosition("actionBars")
    container:ClearAllPoints()
    -- Center horizontally within main frame
    container:SetPoint("TOP", ActionHud.frame, "TOP", 0, yOffset)
    container:Show()
    
    ActionHud:Log(string.format("ActionBars positioned: yOffset=%d", yOffset), "layout")
end

function AB:CreateButtons(parent)
    -- Create 24 buttons (max for 2 bars)
    for i = 1, 24 do
        local btn = CreateFrame("Frame", nil, parent)
        
        -- Icon
        btn.icon = btn:CreateTexture(nil, "BACKGROUND")
        btn.icon:SetAllPoints()
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        
        -- Cooldown
        btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        btn.cd:SetAllPoints()
        btn.cd:SetDrawEdge(true)
        
        -- Count
        btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        btn.count:SetPoint("BOTTOMRIGHT", 0, 0)
        btn.count:SetJustifyH("RIGHT")
        
        -- Proc Glow (Yellow)
        btn.glow = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        btn.glow:SetAllPoints()
        btn.glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        btn.glow:SetBackdropBorderColor(1, 1, 0, 1)
        btn.glow:SetFrameLevel(btn:GetFrameLevel() + 12)
        btn.glow:Hide()
        
        buttons[i] = btn
    end
    
    -- Setup Assist Hook
    if AssistedCombatManager then
        hooksecurefunc(AssistedCombatManager, "SetAssistedHighlightFrameShown", function(mgr, actionButton, shown)
            if not actionButton or not actionButton.action then return end
            
            local targetID = actionButton.action
            -- Handle secret value comparison in Midnight
            if Utils.IsValueSecret(targetID) then return end

            for _, b in ipairs(buttons) do
                if b.actionID == targetID then
                    if not b.assistGlow then
                        b.assistGlow = CreateFrame("Frame", nil, b, "BackdropTemplate")
                        b.assistGlow:SetAllPoints()
                        b.assistGlow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
                        b.assistGlow:SetBackdropBorderColor(0, 0.8, 1, 1)
                        b.assistGlow:SetFrameLevel(b:GetFrameLevel() + 5)
                        b.assistGlow:Hide()
                    end
                    if b.assistGlow then
                        -- Apply Alpha
                        b.assistGlow:SetBackdropBorderColor(0, 0.8, 1, ActionHud.db.profile.assistGlowAlpha)
                        if shown then b.assistGlow:Show() else b.assistGlow:Hide() end
                    end
                end
            end
        end)
    end
end

local lastUpdate = 0
function AB:UpdateLayout()
    -- Throttle updates to once per frame max, and avoid during sensitive Edit Mode events if possible
    local now = GetTime()
    if now == lastUpdate then return end
    lastUpdate = now

    local p = ActionHud.db.profile
    if not container then return end

    -- Debug Container Visual
    ActionHud:UpdateFrameDebug(container, {r=1, g=1, b=0}) -- Yellow for ActionBars
    ActionHud:UpdateLayoutOutline(container, "Action Bars")

    -- Hide all buttons initially
    for _, btn in ipairs(buttons) do btn:Hide() end

    -- Fetch settings for Bar 1 and Bar 6
    local bar1 = self:GetEditModeSettings(1)
    local bar6 = self:GetEditModeSettings(2)

    ActionHud:Log(string.format("Layout Sync: Bar1(%dx%d) Bar6(%dx%d)", bar1.numIcons, bar1.numRows, bar6.numIcons, bar6.numRows), "layout")

    local blocks = {}
    if p.barPriority == "bar6" then
        table.insert(blocks, { settings = bar6, startSlot = 61, id = "bar6" })
        table.insert(blocks, { settings = bar1, startSlot = 1, id = "bar1" })
    else
        table.insert(blocks, { settings = bar1, startSlot = 1, id = "bar1" })
        table.insert(blocks, { settings = bar6, startSlot = 61, id = "bar6" })
    end

    local totalHeight = self:CalculateHeight()
    local totalWidth = self:GetLayoutWidth()
    container:SetSize(totalWidth, totalHeight)

    -- Report height to LayoutManager
    local LM = ActionHud:GetModule("LayoutManager", true)
    if LM then
        LM:SetModuleHeight("actionBars", totalHeight)
    end

    local currentY = 0
    local buttonIdx = 1
    local gapBetweenBlocks = 0

    for _, block in ipairs(blocks) do
        local s = block.settings
        local numIcons = tonumber(s.numIcons) or 12
        local numRows = math.max(tonumber(s.numRows) or 2, 1)
        local iconsPerRow = math.ceil(numIcons / numRows)
        local blockWidth = iconsPerRow * p.iconWidth
        local blockHeight = numRows * p.iconHeight
        
        -- Alignment X Offset
        local xOffset = 0
        if p.barAlignment == "CENTER" then
            xOffset = (totalWidth - blockWidth) / 2
        elseif p.barAlignment == "RIGHT" then
            xOffset = totalWidth - blockWidth
        end

        for i = 1, numIcons do
            local btn = buttons[buttonIdx]
            if btn then
                btn:SetSize(p.iconWidth, p.iconHeight)
                
                local col = (i - 1) % iconsPerRow
                local row = math_floor((i - 1) / iconsPerRow)
                
                local visualRow = numRows - 1 - row
                local slotOffset = i - 1

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", container, "TOPLEFT", xOffset + (col * p.iconWidth), -(currentY + (visualRow * p.iconHeight)))
                btn:Show()
                btn:EnableMouse(false)

                btn.baseSlot = block.startSlot + slotOffset
                btn.actionID = btn.baseSlot 
                
                -- Visuals
                Utils.ApplyIconCrop(btn.icon, p.iconWidth, p.iconHeight)
                local font = "Fonts\\FRIZQT__.TTF"
                if btn.count then btn.count:SetFont(font, p.countFontSize, "OUTLINE") end
                if btn.cd then
                    for _, r in ipairs({btn.cd:GetRegions()}) do
                        if r:GetObjectType() == "FontString" then r:SetFont(font, p.cooldownFontSize, "OUTLINE") end
                    end
                end
                if btn.glow then btn.glow:SetBackdropBorderColor(1, 1, 0, p.procGlowAlpha) end
                if btn.assistGlow then btn.assistGlow:SetBackdropBorderColor(0, 0.8, 1, p.assistGlowAlpha) end
                
                buttonIdx = buttonIdx + 1
            end
        end
        currentY = currentY + blockHeight + gapBetweenBlocks
    end

    -- Update action data for all shown buttons
    self:RefreshAll()
    self:UpdateOpacity()

    -- Trigger LayoutManager to reposition other modules if our height changed
    if LM then
        LM:TriggerLayoutUpdate()
    end
end

function AB:UpdateOpacity()
    local alpha = ActionHud.db.profile.opacity
    for _, btn in ipairs(buttons) do
        if btn.icon and not btn.hasAction then
             btn.icon:SetColorTexture(0, 0, 0, alpha)
        end
    end
end

function AB:OnDisable()
    if container then container:Hide() end
    for _, btn in ipairs(buttons) do
        btn:Hide()
    end
end

function AB:RefreshAll()
    if not self:IsEnabled() then return end
    ActionHud:Log("ActionBars: RefreshAll", "events")
    for _, btn in ipairs(buttons) do
        if btn:IsShown() then
            self:UpdateAction(btn)
            self:UpdateCooldown(btn)
            self:UpdateState(btn)
        end
    end
end

function AB:ACTIONBAR_SLOT_CHANGED(event, arg1)
    ActionHud:Log(string.format("ActionBars: %s (slot=%s)", event, tostring(arg1)), "events")
    for _, btn in ipairs(buttons) do
        if btn.baseSlot == arg1 or btn.actionID == arg1 or arg1 == 0 then
            self:UpdateAction(btn)
            self:UpdateCooldown(btn)
            self:UpdateState(btn)
        end
    end
end

function AB:SPELL_UPDATE_COOLDOWN()
    -- Only update buttons with actions (skip empty slots to reduce overhead)
    for _, btn in ipairs(buttons) do
        if btn.hasAction then
            self:UpdateCooldown(btn)
        end
    end
end

function AB:UpdateStateAll()
    ActionHud:Log("ActionBars: UpdateStateAll", "events")
    -- Only update buttons with actions (skip empty slots to reduce overhead)
    for _, btn in ipairs(buttons) do
        if btn.hasAction then
            self:UpdateState(btn)
        end
    end
end

-- Specific Update Functions
function AB:UpdateAction(btn)
    local slot = btn.baseSlot
    if not slot then return end
    
    local actionID = slot
    
    -- Paging logic
    if slot >= 1 and slot <= 12 then
         local page = GetActionBarPage()
         local offset = GetBonusBarOffset()
         
         -- Handle secret values in Midnight
         if Utils.IsValueSecret(page) then page = 1 end
         if Utils.IsValueSecret(offset) then offset = 0 end

         if offset > 0 and page == 1 then
              if offset == 1 then page = 7
              elseif offset == 2 then page = 8
              elseif offset == 3 then page = 9
              elseif offset == 4 then page = 10
              elseif offset == 5 then page = 11
              elseif offset == 6 then page = 12
              end
         end
         if page and page > 1 then actionID = (page - 1) * 12 + slot end
    end
    
    btn.actionID = actionID
    local type, id = GetActionInfo(actionID)
    if type == "spell" then btn.spellID = id
    elseif type == "macro" then btn.spellID = GetMacroSpell(actionID)
    else btn.spellID = nil end
    
    local texture = GetActionTexture(actionID)
    if texture then
        btn.hasAction = true
        btn.icon:SetTexture(texture)
        btn.icon:Show()
        btn:SetAlpha(1)
        Utils.ApplyIconCrop(btn.icon, ActionHud.db.profile.iconWidth, ActionHud.db.profile.iconHeight)
    else
        btn.hasAction = false
        btn.icon:Hide()
        btn.cd:Hide()
        btn.count:SetText("")
        btn.glow:Hide()
        if btn.assistGlow then btn.assistGlow:Hide() end
        btn.icon:SetColorTexture(0, 0, 0, ActionHud.db.profile.opacity)
        btn.icon:Show()
    end
end

function AB:UpdateCooldown(btn)
    if not btn.hasAction then return end
    local start, duration = GetActionCooldown(btn.actionID)
    
    local startIsSecret = Utils.IsValueSecret(start)
    local durationIsSecret = Utils.IsValueSecret(duration)
    
    if start and duration then
        local hasRealCD = false
        if not startIsSecret and not durationIsSecret then
            hasRealCD = start > 0 and duration > 0
        else
            hasRealCD = true
        end
        
        if hasRealCD then
            if not startIsSecret and not durationIsSecret then
                local gcdInfo = Utils.GetSpellCooldownSafe(61304)
                if gcdInfo and not Utils.IsValueSecret(gcdInfo.startTime) and not Utils.IsValueSecret(gcdInfo.duration) then
                    if gcdInfo.startTime == start and gcdInfo.duration == duration then
                        btn.cd:SetDrawEdge(false)
                    else
                        if duration <= 1.5 then btn.cd:SetDrawEdge(false) else btn.cd:SetDrawEdge(true) end
                    end
                else
                    btn.cd:SetDrawEdge(false)
                end
            else
                btn.cd:SetDrawEdge(false)
            end
            
            btn.cd:SetCooldown(start, duration)
            btn.cd:Show()
            return
        end
    end
    
    if btn.spellID then
        local chargeInfo = Utils.GetSpellChargesSafe(btn.spellID)
        if chargeInfo then
            local cdStart = chargeInfo.cooldownStartTime
            local cdDuration = chargeInfo.cooldownDuration
            local cdStartSecret = Utils.IsValueSecret(cdStart)
            local cdDurationSecret = Utils.IsValueSecret(cdDuration)
            
            local hasChargeCooldown = false
            if not cdStartSecret and not cdDurationSecret then
                hasChargeCooldown = cdStart > 0 and (GetTime() < cdStart + cdDuration)
            else
                hasChargeCooldown = cdStart ~= nil
            end
            
            if hasChargeCooldown then
                btn.cd:SetDrawEdge(true)
                btn.cd:SetCooldown(cdStart, cdDuration)
                btn.cd:Show()
                return
            end
        end
    end
    
    btn.cd:Hide()
end

function AB:UpdateState(btn)
   if not btn.hasAction then return end
   local actionID = btn.actionID
   
   local count = GetActionCount(actionID)
   local countIsSecret = Utils.IsValueSecret(count)
   
   -- Get charge info once and reuse (avoid duplicate API call)
   local chargeInfo = btn.spellID and Utils.GetSpellChargesSafe(btn.spellID)
   
   if not countIsSecret and (not count or count <= 1) then
       if chargeInfo then 
           count = chargeInfo.currentCharges
           countIsSecret = Utils.IsValueSecret(count)
       end
   end
   
   if countIsSecret then
       btn.count:SetText("...") 
   else
       local showCount = false
       if count and count > 1 then
           showCount = true
       end
       if chargeInfo and not countIsSecret then
           local maxCharges = chargeInfo.maxCharges
           if not Utils.IsValueSecret(maxCharges) and maxCharges > 1 then
               showCount = true
           end
       end
       btn.count:SetText(showCount and count or "")
   end
   
   local isUsable, noMana = IsUsableAction(actionID)
   if not isUsable and not noMana then
       btn.icon:SetDesaturated(true)
       btn.icon:SetVertexColor(0.4, 0.4, 0.4)
   elseif noMana then
       btn.icon:SetDesaturated(false)
       btn.icon:SetVertexColor(0.5, 0.5, 1.0)
   else
       btn.icon:SetDesaturated(false)
       btn.icon:SetVertexColor(1, 1, 1)
   end
   
   if ActionButton_GetInRange and ActionButton_GetInRange(actionID) == false then 
       if IsActionInRange(actionID) == false then btn.icon:SetVertexColor(0.8, 0.1, 0.1) end
   end
   
   local isOverlayed = false
   if btn.spellID then
        isOverlayed = Utils.IsSpellOverlayedSafe(btn.spellID)
   end
   if isOverlayed then btn.glow:Show() else btn.glow:Hide() end
end

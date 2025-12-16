local addonName, ns = ...

-- Configuration
-- We now load defaults but overlay SavedVariables
ActionHudDB = ActionHudDB or {}
ActionHudDB.profile = ActionHudDB.profile or {}

-- Persistent Config Table (Avoids garbage generation)
local CFG = {
    slots = {
        7, 8, 9, 10, 11, 12,
        1, 2, 3, 4, 5, 6,
        67, 68, 69, 70, 71, 72,
        61, 62, 63, 64, 65, 66
    }
}

local function UpdateConfigCache()
    local p = ActionHudDB.profile
    CFG.iconWidth = p.iconWidth or 20
    CFG.iconHeight = p.iconHeight or 15
    CFG.padding = 0
    CFG.columns = 6
    CFG.xOffset = p.xOffset or 0
    CFG.yOffset = p.yOffset or -220
    CFG.locked = p.locked
    if CFG.locked == nil then CFG.locked = false end
    CFG.opacity = p.opacity or 0.0
    CFG.procGlowAlpha = p.procGlowAlpha or 1.0
    CFG.assistGlowAlpha = p.assistGlowAlpha or 1.0
    CFG.cooldownFontSize = p.cooldownFontSize or 6
    CFG.countFontSize = p.countFontSize or 6
end

-- Initialize CFG immediately (will be updated again on Initialize)
UpdateConfigCache()

-- Main Frame
local main = CreateFrame("Frame", "ActionHudFrame", UIParent)
main:SetSize(CFG.columns * CFG.iconWidth, 4 * CFG.iconHeight)
main:SetPoint("CENTER", CFG.xOffset, CFG.yOffset)
main:SetClampedToScreen(true)
main:EnableMouse(false) -- Default to false, updated in LockState
main:SetMovable(true)
main:RegisterForDrag("LeftButton")

-- Drag Background (Visual indicator when unlocked)
main.dragBg = main:CreateTexture(nil, "BACKGROUND")
main.dragBg:SetAllPoints()
main.dragBg:SetColorTexture(0, 1, 0, 0.3)
main.dragBg:Hide()

main:SetScript("OnDragStart", function(self)
    -- Double check lock state just in case
    if not ActionHudDB.profile.locked then
        self:StartMoving()
    end
end)
main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Save Position
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    -- We need to save to DB.
    ActionHudDB.profile.xOffset = xOfs
    ActionHudDB.profile.yOffset = yOfs
end)

local buttons = {}
local function ApplyIconCrop(btn)
    -- Use raw icon cropping logic
    -- Standard trim 0.08 to 0.92
    local ratio = CFG.iconWidth / CFG.iconHeight
    if ratio > 1 then
        -- Wider: Crop Height
        local scale = CFG.iconHeight / CFG.iconWidth -- < 1
        -- range = 0.84 * scale
        local range = 0.84 * scale
        local mid = 0.5
        local top = mid - (range/2)
        local bottom = mid + (range/2)
        btn.icon:SetTexCoord(0.08, 0.92, top, bottom)
    elseif ratio < 1 then
        -- Taller: Crop Width
        local scale = CFG.iconWidth / CFG.iconHeight
        local range = 0.84 * scale
        local mid = 0.5
        local left = mid - (range/2)
        local right = mid + (range/2)
        btn.icon:SetTexCoord(left, right, 0.08, 0.92)
    else
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function UpdateLayout(self)
    UpdateConfigCache() -- Ensure CFG is fresh from DB
    
    self:SetSize(CFG.columns * CFG.iconWidth, 4 * CFG.iconHeight)
    
    for i, btn in ipairs(buttons) do
        btn:SetSize(CFG.iconWidth, CFG.iconHeight)
        local col = (i - 1) % CFG.columns
        local row = math.floor((i - 1) / CFG.columns)
        btn:SetPoint("TOPLEFT", col * (CFG.iconWidth + CFG.padding), -row * (CFG.iconHeight + CFG.padding))
        
        -- Ensure buttons don't block clicks to main frame
        btn:EnableMouse(false)
        
        -- Apply Crop
        ApplyIconCrop(btn)
        
        -- Update Glow Size if it exists (yellow proc)
        if btn.glow then 
             -- Yellow Glow is now a Backdrop Frame following Button Size
             -- We need to ensure backdrop size/edge scales if we wanted 2px visual
             btn.glow:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1, -- Target 1px wide
             })
             btn.glow:SetBackdropBorderColor(1, 1, 0, CFG.procGlowAlpha)
        end
        
        -- Update Assist Glow Alpha if it exists
        if btn.assistGlow then
             btn.assistGlow:SetBackdropBorderColor(0, 0.8, 1, CFG.assistGlowAlpha)
        end
        
        -- Refresh Fonts
        if btn.count then
             local fontName, _, fontFlags = btn.count:GetFont()
             btn.count:SetFont(fontName, CFG.countFontSize, fontFlags)
        end
        if btn.cd then
             local frames = { btn.cd:GetRegions() }
             for _, region in ipairs(frames) do
                if region:GetObjectType() == "FontString" then
                    local fontName, _, fontFlags = region:GetFont()
                    region:SetFont(fontName, CFG.cooldownFontSize, fontFlags)
                end
             end
        end
        
        -- Update Assist Glow (it tracks SetAllPoints automatically if it's a Backdrop Frame)
        -- No update needed for assistGlow since it is CreateFrame with SetAllPoints
    end
end

-- Export methods for SettingsUI
function main:UpdateLayout()
    UpdateLayout(self)
end
function main:UpdateLockState()
    UpdateConfigCache() -- Ensure local CFG is updated
    local locked = CFG.locked
    self:EnableMouse(not locked)
    if not locked then
        self.dragBg:Show()
    else
        self.dragBg:Hide()
    end
end
function main:UpdateOpacity()
    UpdateConfigCache()
    local alpha = CFG.opacity
    for _, btn in ipairs(buttons) do
        -- Only affect background texture color alpha
        if btn.icon then
            -- If texture is nil (empty slot), set color texture
            if not btn.hasAction then
               btn.icon:SetColorTexture(0, 0, 0, alpha)
            end
        end
    end
end

-- Slash Command for Debugging
SLASH_ACTIONHUD1 = "/actionhud"
SlashCmdList["ACTIONHUD"] = function(msg)
    -- ... debug ...
end

-- Initialize on Login to sync SVs
local function Initialize()
    UpdateConfigCache() -- Critical: Sync CFG with loaded SVs
    
    -- Apply SVs to Main Frame Point if saved
    if CFG.xOffset and CFG.yOffset then
        main:ClearAllPoints()
        main:SetPoint("CENTER", CFG.xOffset, CFG.yOffset)
    end
    
    main:UpdateLayout()
    main:UpdateLockState()
    main:UpdateOpacity()
end
SLASH_ACTIONHUD1 = "/actionhud"
SlashCmdList["ACTIONHUD"] = function(msg)
    local output = "ActionHud Debug Dump:\n"
    local page = GetActionBarPage()
    local bonus = GetBonusBarOffset()
    output = output .. string.format("Current Page: %s, BonusOffset: %s\n", tostring(page), tostring(bonus))
    
    local count = 0
    -- Dump ALL visible buttons (1-24) to see Glow status
    output = output .. "Checking all 24 HUD buttons:\n"
    for i = 1, 24 do 
        local btn = buttons[i] 
        if btn then
            local actionID = btn.actionID
            local type, id = GetActionInfo(actionID)
            local name = "nil"
            if type == "spell" then name = C_Spell.GetSpellName(id) end
            
            -- Check overlay status for debug
            local isOverlayed = false
            local spellID = (type == "spell" and id) or (type == "macro" and GetMacroSpell(id))
            if spellID then
                 if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
                    isOverlayed = C_SpellActivationOverlay.IsSpellOverlayed(spellID)
                 end
            end
            
            -- Only print if meaningful (has action)
            if actionID and actionID > 0 then
                 output = output .. string.format("Btn %d (Slot %d -> ID %d): %s [Glow: %s]\n", i, btn.baseSlot, actionID, tostring(name), tostring(isOverlayed))
            end
        end
    end
    
    -- Add Page Calculation Check for Slot 1 specifically
    output = output .. "\nPage Calculation Check:\n"
    local rawPage = GetActionBarPage()
    local offset = (rawPage - 1) * 12
    output = output .. string.format("Page: %d, Offset: %d\nSlot 1 Should Be: %d", rawPage, offset, offset+1)

    error(output)
end
main:SetSize(CFG.columns * CFG.iconWidth, 4 * CFG.iconHeight)
main:SetPoint("CENTER", CFG.xOffset, CFG.yOffset)
main:SetClampedToScreen(true)
main:EnableMouse(false) -- Click-through



-- Create Button Grid (Initial)
local cfgInitial = CFG -- Use the cache
for i, actionID in ipairs(CFG.slots) do
    local btn = CreateFrame("Frame", nil, main)
    btn:SetSize(cfgInitial.iconWidth, cfgInitial.iconHeight)
    
    local col = (i - 1) % cfgInitial.columns
    local row = math.floor((i - 1) / cfgInitial.columns)
    
    btn:SetPoint("TOPLEFT", col * (cfgInitial.iconWidth + cfgInitial.padding), -row * (cfgInitial.iconHeight + cfgInitial.padding))
    
    -- Icon
    btn.icon = btn:CreateTexture(nil, "BACKGROUND")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Zoom in slightly
    
    -- Cooldown
    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints()
    btn.cd:SetDrawEdge(true) -- Enable "Cold Line" / Swipe Edge
    
    -- Count/Stacks (Bottom Right)
    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.count:SetPoint("BOTTOMRIGHT", 0, 0)
    btn.count:SetFont("Fonts\\FRIZQT__.TTF", cfgInitial.countFontSize or 10, "OUTLINE") -- Use Hardcoded Font Path if global missing
    btn.count:SetJustifyH("RIGHT")

    
    -- Proc Glow (Yellow) - Outer Narrow Border
    -- We use a dedicated frame to ensure z-order and crisp lines (no fuzzy texture padding)
    btn.glow = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.glow:SetAllPoints()
    btn.glow:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1, 
                      -- Let's enable border scaling.
    })
    btn.glow:SetBackdropBorderColor(1, 1, 0, 1) -- Bright Yellow
    -- We want Proc Glow to be OUTSIDE or INSIDE? "Above it". 
    -- If Blue (Assist) is 4px, let's make that one thicker.
    -- Let's try: Blue = Thick Inner, Yellow = Thin Outer? Or vice-versa.
    -- User: "Suggested (Blue) glow goes to 4px wide... Proc glow is above it at 2px wide"
    -- This implies stacking.
    
    -- Make Yellow Glow Frame slightly larger? Or inset?
    -- If we keep them same size, they overlap.
    -- Let's make Yellow Glow standard 1px/2px on the very edge.
    btn.glow:SetFrameLevel(btn:GetFrameLevel() + 12) -- Topmost
    btn.glow:Hide()
    
    btn.baseSlot = actionID -- Store the visual slot (e.g. 1)
    btn.actionID = actionID -- Initialize
    buttons[i] = btn
end

-- Update Functions
-- Helper for protected calls
local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        -- In debug mode, we might print this, but for now we swallow or log to a savedvar
        -- print("ActionHud Error:", result) 
        return nil
    end
    return result
end

-- Update Functions
-- Granular Update Functions

-- 1. Full Update (Texture, Attributes) - Expensive, Rare (Slot changes)
local function UpdateAction(btn)
    local slot = btn.baseSlot
    local actionID = slot
    
    -- Paging Logic
    if slot >= 1 and slot <= 12 then
        local page = GetActionBarPage()
        local offset = GetBonusBarOffset()
        if offset > 0 and page == 1 then
             if offset == 1 then page = 7
             elseif offset == 2 then page = 8
             elseif offset == 3 then page = 9
             elseif offset == 4 then page = 10
             elseif offset == 5 then page = 11
             elseif offset == 6 then page = 12
             end
        end
        if page and page > 1 then
             actionID = (page - 1) * 12 + slot
        end
    end
    
    btn.actionID = actionID
    
    -- Cache SpellID for Cooldown Logic
    local type, id = GetActionInfo(actionID)
    if type == "spell" then
        btn.spellID = id
    elseif type == "macro" then
        btn.spellID = GetMacroSpell(actionID)
    else
        btn.spellID = nil
    end
    
    local texture = GetActionTexture(actionID)
    if texture then
        btn.hasAction = true
        btn.icon:SetTexture(texture)
        btn.icon:Show()
        btn:SetAlpha(1)
        ApplyIconCrop(btn)
    else
        btn.hasAction = false
        btn.icon:Hide()
        btn.cd:Hide()
        btn.count:SetText("")
        btn.glow:Hide()
        if btn.assistGlow then btn.assistGlow:Hide() end
        btn.icon:SetColorTexture(0, 0, 0, ActionHudDB.profile.opacity or 0.0)
        btn.icon:Show()
    end
end

-- 2. Cooldown Update - Frequent (SPELL_UPDATE_COOLDOWN)
local function UpdateCooldown(btn)
    if not btn.hasAction then return end
    
    local start, duration = GetActionCooldown(btn.actionID)
    -- If standard cooldown is active (e.g. GCD or full CD), show it
    if start and duration and start > 0 and duration > 0 then
        -- Check if it is the Global Cooldown
        local gcdInfo = C_Spell.GetSpellCooldown(61304) -- Standard GCD spell
        if gcdInfo and gcdInfo.startTime == start and gcdInfo.duration == duration then
             btn.cd:SetDrawEdge(false) -- No swipe edge for GCD
        else
             -- Check for short shared lockouts (Skyriding buffer is ~0.5s - 1.0s) which should NOT have a spark
             if duration <= 1.5 then
                 -- This is likely a shared lockout buffer or GCD variant
                 btn.cd:SetDrawEdge(false)
             else
                 btn.cd:SetDrawEdge(true) -- Show swipe edge for real CDs (>1.5s)
             end
        end
        
        btn.cd:SetCooldown(start, duration)
        btn.cd:Show()
    else
        -- Fallback: Check for Charge Cooldown (The "Cold Line")
        if btn.spellID then
            local chargeInfo = C_Spell.GetSpellCharges(btn.spellID)
            if chargeInfo and chargeInfo.cooldownStartTime > 0 and (GetTime() < chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) then
                -- Only show if actual recharge is happening
                btn.cd:SetDrawEdge(true) -- User confirmed they want the spark for charges refilling
                btn.cd:SetCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration)
                btn.cd:Show()
                return -- Exit early
            end
        end
        
        btn.cd:Hide()
    end
end

-- 3. State Update (Usable, Range, Count, Glow) - Model changes, Usable events
local function UpdateState(btn)
    if not btn.hasAction then return end
    local actionID = btn.actionID
    
    -- Count
    local count = GetActionCount(actionID)
    if not count or count <= 1 then
        local type, spellID = GetActionInfo(actionID)
        if type == "spell" or (type == "macro" and GetMacroSpell(actionID)) then
             local actualSpellID = (type == "spell" and spellID) or GetMacroSpell(actionID)
             if actualSpellID then
                 local chargeInfo = C_Spell.GetSpellCharges(actualSpellID)
                 if chargeInfo then count = chargeInfo.currentCharges end
             end
        end
    end
    
    if count and count > 0 then
         if count > 1 then
             btn.count:SetText(count)
         elseif count == 1 then
              -- Check max charges for Skyriding '1/3' case
             local type, spellID = GetActionInfo(actionID)
             if type == "macro" then spellID = GetMacroSpell(actionID) end
             if spellID then
                 local chargeInfo = C_Spell.GetSpellCharges(spellID)
                 if chargeInfo and chargeInfo.maxCharges > 1 then
                     btn.count:SetText(count)
                 else
                     btn.count:SetText("")
                 end
             else
                 btn.count:SetText("")
             end
         else
            btn.count:SetText("")
         end
    else
        btn.count:SetText("")
    end

    -- Usable
    local isUsable, notEnoughMana = IsUsableAction(actionID)
    if not isUsable and not notEnoughMana then
         btn.icon:SetDesaturated(true)
         btn.icon:SetVertexColor(0.4, 0.4, 0.4) 
    elseif notEnoughMana then
         btn.icon:SetDesaturated(false)
         btn.icon:SetVertexColor(0.5, 0.5, 1.0)
    else
         btn.icon:SetDesaturated(false)
         btn.icon:SetVertexColor(1, 1, 1)
    end

    -- Range (Only if usable)
    -- Range check is expensive, maybe rely on Usable? 
    -- Standard buttons do range check on UpdateUsable? No, they use OnUpdate usually. 
    -- We are event driven. ACTIONBAR_UPDATE_RANGE doesn't exist.
    -- We can check here, but it won't update as you run unless an event fires.
    -- Events firing: UPDATE_USABLE often fires on range change? No.
    -- Compromise: Check range here. It will update when you cast/target/usable change.
    if ActionButton_GetInRange and ActionButton_GetInRange(btn.actionID) == false then 
         local inRange = IsActionInRange(actionID)
         if inRange == false then
            btn.icon:SetVertexColor(0.8, 0.1, 0.1)
         end
    end

    -- Glow (Proc)
    local isOverlayed = false
    local type, id = GetActionInfo(actionID)
    local spellID = (type == "spell" and id) or (type == "macro" and GetMacroSpell(id))
    
    if spellID then
        if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
            isOverlayed = C_SpellActivationOverlay.IsSpellOverlayed(spellID)
        elseif C_Spell and C_Spell.IsSpellOverlayed then
            isOverlayed = C_Spell.IsSpellOverlayed(spellID)
        else
            isOverlayed = IsSpellOverlayed(spellID)
        end
    end
    
    if isOverlayed then
        btn.glow:Show()
    else
        btn.glow:Hide()
    end
end

-- Refresh All Helper
local function RefreshAll()
    for _, btn in ipairs(buttons) do
        UpdateAction(btn)
        UpdateCooldown(btn)
        UpdateState(btn)
    end
end

local function OnEvent(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        Initialize()
        RefreshAll()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" then
         RefreshAll()
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        for _, btn in ipairs(buttons) do
            -- Check baseSlot (static) OR actionID (dynamic/paged)
            if btn.baseSlot == arg1 or btn.actionID == arg1 or arg1 == 0 then
                UpdateAction(btn)
                UpdateCooldown(btn)
                UpdateState(btn)
            end
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- Fast Path: Only update Cooldown frames
        for _, btn in ipairs(buttons) do
             UpdateCooldown(btn)
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        -- Only update State (Glows)
        for _, btn in ipairs(buttons) do
            UpdateState(btn)
        end
    elseif event == "ACTIONBAR_UPDATE_STATE" or event == "ACTIONBAR_UPDATE_USABLE" or event == "SPELL_UPDATE_CHARGES" then
        -- Update State (Usable, Count, Range-ish)
         for _, btn in ipairs(buttons) do
            UpdateState(btn)
        end
    end
end

main:RegisterEvent("PLAYER_LOGIN")
main:RegisterEvent("PLAYER_ENTERING_WORLD")
main:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
main:RegisterEvent("ACTIONBAR_PAGE_CHANGED") -- Handle Stance/Form Swaps
main:RegisterEvent("UPDATE_BONUS_ACTIONBAR") -- Handle Vehicle/Possess
main:RegisterEvent("SPELL_UPDATE_COOLDOWN")
main:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
main:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
main:RegisterEvent("ACTIONBAR_UPDATE_STATE")
main:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
main:RegisterEvent("SPELL_UPDATE_CHARGES")
main:SetScript("OnEvent", OnEvent)

-- Hook for Assisted Highlight (Blue Glow)
-- The default UI calls AssistedCombatManager:SetAssistedHighlightFrameShown(actionButton, shown)
if AssistedCombatManager then
    hooksecurefunc(AssistedCombatManager, "SetAssistedHighlightFrameShown", function(self, actionButton, shown)
        if not actionButton or not actionButton.action then return end
        local targetActionID = actionButton.action
        
        for _, btn in ipairs(buttons) do
            if btn.actionID == targetActionID then
                if not btn.assistGlow then
                    -- Create Simple Blue Border Frame (Assisted Highlight)
                    -- Note: btn.assistGlow is created once per session on first need
                    btn.assistGlow = CreateFrame("Frame", nil, btn, "BackdropTemplate")
                    btn.assistGlow:SetAllPoints()
                    btn.assistGlow:SetBackdrop({
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 2, -- 2px Wide
                    })
                    btn.assistGlow:SetBackdropBorderColor(0, 0.8, 1, CFG.assistGlowAlpha or 1) -- Cyan/Blue
                    -- Lower than Yellow (Proc) but above base
                    btn.assistGlow:SetFrameLevel(btn:GetFrameLevel() + 5) 
                    btn.assistGlow:Hide()
                end
                
                if shown then
                    btn.assistGlow:Show()
                else
                    btn.assistGlow:Hide()
                end
            end
        end
    end)
end

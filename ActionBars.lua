local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local AB = ActionHud:NewModule("ActionBars", "AceEvent-3.0")

-- Midnight (12.0) compatibility (per Secret Values guide 13)
local IS_MIDNIGHT = (select(4, GetBuildInfo()) >= 120000)

-- Helper: Check if value is a Midnight secret value
-- Returns true if value is secret and cannot be compared/formatted
local function IsValueSecret(value)
    if not IS_MIDNIGHT then return false end
    if not issecretvalue then return false end
    return issecretvalue(value) == true
end

-- Helper: Safe comparison that handles secret values
-- Returns nil if comparison is not possible
local function SafeCompare(a, b, op)
    if IsValueSecret(a) or IsValueSecret(b) then return nil end
    if op == ">" then return a > b
    elseif op == "<" then return a < b
    elseif op == ">=" then return a >= b
    elseif op == "<=" then return a <= b
    elseif op == "==" then return a == b
    end
    return nil
end

-- Safe API wrappers with pcall (per API Resilience guide 09)
local function SafeGetSpellCooldown(spellID)
    if not spellID then return nil end
    if not C_Spell or not C_Spell.GetSpellCooldown then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and info then return info end
    return nil
end

local function SafeGetSpellCharges(spellID)
    if not spellID then return nil end
    if not C_Spell or not C_Spell.GetSpellCharges then return nil end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if ok and info then return info end
    return nil
end

local function SafeIsSpellOverlayed(spellID)
    if not spellID then return false end
    -- Try new API first
    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
        local ok, result = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
        if ok then return result end
    end
    -- Fallback to old API
    if IsSpellOverlayed then
        local ok, result = pcall(IsSpellOverlayed, spellID)
        if ok then return result end
    end
    return false
end

-- hardcoded slots for now
local defaultSlots = {
    7, 8, 9, 10, 11, 12,
    1, 2, 3, 4, 5, 6,
    67, 68, 69, 70, 71, 72,
    61, 62, 63, 64, 65, 66
}

local buttons = {}

function AB:OnEnable()
    -- Create Button Grid
    local parent = ActionHud.frame
    if not parent then
        -- This should exist by now if Core initialized it
        return 
    end
    
    -- Create Buttons if not already existing
    if #buttons == 0 then
        self:CreateButtons(parent)
    end
    
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshAll")
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "RefreshAll")
    self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", "RefreshAll")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "UpdateStateAll")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "UpdateStateAll")
    self:RegisterEvent("ACTIONBAR_UPDATE_STATE", "UpdateStateAll")
    self:RegisterEvent("ACTIONBAR_UPDATE_USABLE", "UpdateStateAll")
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "UpdateStateAll")
    
    self:UpdateLayout()
    self:RefreshAll()
end

function AB:CreateButtons(parent)
    for i, actionID in ipairs(defaultSlots) do
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
        
        btn.baseSlot = actionID
        btn.actionID = actionID
        buttons[i] = btn
    end
    
    -- Setup Assist Hook
    if AssistedCombatManager then
        hooksecurefunc(AssistedCombatManager, "SetAssistedHighlightFrameShown", function(mgr, actionButton, shown)
            if not actionButton or not actionButton.action then return end
            local targetID = actionButton.action
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

function AB:UpdateLayout()
    local p = ActionHud.db.profile
    local cols = 6
    local padding = 0
    
    local parent = ActionHud.frame
    if not parent then return end
    
    parent:SetSize(cols * p.iconWidth, 4 * p.iconHeight)
    
    for i, btn in ipairs(buttons) do
        btn:SetSize(p.iconWidth, p.iconHeight)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        btn:SetPoint("TOPLEFT", col * (p.iconWidth + padding), -row * (p.iconHeight + padding))
        btn:EnableMouse(false)
        
        -- Crop
        self:ApplyIconCrop(btn, p.iconWidth, p.iconHeight)
        
        -- Fonts
        local font = "Fonts\\FRIZQT__.TTF"
        if btn.count then btn.count:SetFont(font, p.countFontSize, "OUTLINE") end
        if btn.cd then
            for _, r in ipairs({btn.cd:GetRegions()}) do
                if r:GetObjectType() == "FontString" then r:SetFont(font, p.cooldownFontSize, "OUTLINE") end
            end
        end
        
        -- Glow Opacity
        if btn.glow then btn.glow:SetBackdropBorderColor(1, 1, 0, p.procGlowAlpha) end
        if btn.assistGlow then btn.assistGlow:SetBackdropBorderColor(0, 0.8, 1, p.assistGlowAlpha) end
    end
    
    -- Sync Opacity on Layout update
    self:UpdateOpacity()
end

function AB:ApplyIconCrop(btn, w, h)
    local ratio = w / h
    if ratio > 1 then
         local scale = h / w
         local range = 0.84 * scale
         local mid = 0.5
         btn.icon:SetTexCoord(0.08, 0.92, mid - range/2, mid + range/2)
    elseif ratio < 1 then
         local scale = w / h
         local range = 0.84 * scale
         local mid = 0.5
         btn.icon:SetTexCoord(mid - range/2, mid + range/2, 0.08, 0.92)
    else
         btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

function AB:UpdateOpacity()
    local alpha = ActionHud.db.profile.opacity
    for _, btn in ipairs(buttons) do
        if btn.icon and not btn.hasAction then
             btn.icon:SetColorTexture(0, 0, 0, alpha)
        else
            -- If has action, alpha is controlled by UpdateState/Action usually (1)
        end
    end
end

-- =========================================================================
-- Button Logic
-- =========================================================================

function AB:OnDisable()
    for _, btn in ipairs(buttons) do
        btn:Hide()
    end
end

function AB:RefreshAll()
    if not self:IsEnabled() then return end
    for _, btn in ipairs(buttons) do
        btn:Show()
        self:UpdateAction(btn)
        self:UpdateCooldown(btn)
        self:UpdateState(btn)
    end
end

function AB:ACTIONBAR_SLOT_CHANGED(event, arg1)
    for _, btn in ipairs(buttons) do
        if btn.baseSlot == arg1 or btn.actionID == arg1 or arg1 == 0 then
            self:UpdateAction(btn)
            self:UpdateCooldown(btn)
            self:UpdateState(btn)
        end
    end
end

function AB:SPELL_UPDATE_COOLDOWN()
    for _, btn in ipairs(buttons) do self:UpdateCooldown(btn) end
end

function AB:UpdateStateAll()
    for _, btn in ipairs(buttons) do self:UpdateState(btn) end
end

-- Specific Update Functions
function AB:UpdateAction(btn)
    local slot = btn.baseSlot
    local actionID = slot
    
    -- Paging logic
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
        self:ApplyIconCrop(btn, ActionHud.db.profile.iconWidth, ActionHud.db.profile.iconHeight)
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
    
    -- Check for secret values (Midnight combat)
    local startIsSecret = IsValueSecret(start)
    local durationIsSecret = IsValueSecret(duration)
    
    if start and duration then
        -- Use passthrough for Cooldown:SetCooldown - it accepts secret values
        -- But we can't do comparisons if values are secret
        local hasRealCD = false
        if not startIsSecret and not durationIsSecret then
            hasRealCD = start > 0 and duration > 0
        else
            -- In Midnight, assume we have a CD if values exist and are non-nil
            -- Passthrough will handle display correctly
            hasRealCD = true
        end
        
        if hasRealCD then
            -- GCD Check (Spell ID 61304) - skip if values are secret
            if not startIsSecret and not durationIsSecret then
                local gcdInfo = SafeGetSpellCooldown(61304)
                if gcdInfo and not IsValueSecret(gcdInfo.startTime) and not IsValueSecret(gcdInfo.duration) then
                    if gcdInfo.startTime == start and gcdInfo.duration == duration then
                        btn.cd:SetDrawEdge(false)
                    else
                        if duration <= 1.5 then btn.cd:SetDrawEdge(false) else btn.cd:SetDrawEdge(true) end
                    end
                else
                    btn.cd:SetDrawEdge(false) -- Safe default when secret
                end
            else
                btn.cd:SetDrawEdge(false) -- Safe default when secret
            end
            
            -- Passthrough: Cooldown:SetCooldown accepts secret values
            btn.cd:SetCooldown(start, duration)
            btn.cd:Show()
            return
        end
    end
    
    -- Charges fallback
    if btn.spellID then
        local chargeInfo = SafeGetSpellCharges(btn.spellID)
        if chargeInfo then
            local cdStart = chargeInfo.cooldownStartTime
            local cdDuration = chargeInfo.cooldownDuration
            local cdStartSecret = IsValueSecret(cdStart)
            local cdDurationSecret = IsValueSecret(cdDuration)
            
            local hasChargeCooldown = false
            if not cdStartSecret and not cdDurationSecret then
                -- Safe comparison
                hasChargeCooldown = cdStart > 0 and (GetTime() < cdStart + cdDuration)
            else
                -- In Midnight, if we have charge info, assume cooldown is active
                -- Passthrough will display correctly
                hasChargeCooldown = cdStart ~= nil
            end
            
            if hasChargeCooldown then
                btn.cd:SetDrawEdge(true)
                -- Passthrough: SetCooldown accepts secret values
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
   
   -- Count - handle secret values
   local count = GetActionCount(actionID)
   local countIsSecret = IsValueSecret(count)
   
   if not countIsSecret and (not count or count <= 1) then
       if btn.spellID then
           local c = SafeGetSpellCharges(btn.spellID)
           if c then 
               count = c.currentCharges
               countIsSecret = IsValueSecret(count)
           end
       end
   end
   
   -- Display count - degrade gracefully if secret
   if countIsSecret then
       btn.count:SetText("...") -- Degraded display for Midnight
   else
       local showCount = false
       if count and count > 1 then
           showCount = true
       end
       if btn.spellID and not countIsSecret then
           local c = SafeGetSpellCharges(btn.spellID)
           if c then
               local maxCharges = c.maxCharges
               if not IsValueSecret(maxCharges) and maxCharges > 1 then
                   showCount = true
               end
           end
       end
       btn.count:SetText(showCount and count or "")
   end
   
   -- Usable
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
   
   -- Range
   if ActionButton_GetInRange and ActionButton_GetInRange(actionID) == false then 
       if IsActionInRange(actionID) == false then btn.icon:SetVertexColor(0.8, 0.1, 0.1) end
   end
   
   -- Glow
   local isOverlayed = false
   if btn.spellID then
        isOverlayed = SafeIsSpellOverlayed(btn.spellID)
   end
   if isOverlayed then btn.glow:Show() else btn.glow:Hide() end
end

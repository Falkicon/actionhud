local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):NewAddon("ActionHud", "AceEvent-3.0", "AceConsole-3.0")
_G.ActionHud = ActionHud -- Global for debugging

-- hardcoded slots for now
local defaultSlots = {
    7, 8, 9, 10, 11, 12,
    1, 2, 3, 4, 5, 6,
    67, 68, 69, 70, 71, 72,
    61, 62, 63, 64, 65, 66
}

local defaults = {
    profile = {
        locked = false,
        iconWidth = 20,
        iconHeight = 15,
        opacity = 0.0,
        procGlowAlpha = 1.0,
        assistGlowAlpha = 1.0,
        cooldownFontSize = 6,
        countFontSize = 6,
        resEnabled = true,
        resShowTarget = true,
        resPosition = "TOP",
        resHealthHeight = 6,
        resPowerHeight = 6,
        resOffset = 6,
        resSpacing = 1,
        xOffset = 0,
        yOffset = -220,
    }
}

function ActionHud:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ActionHudDB", defaults, true)
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    
    self:SetupOptions() -- In SettingsUI.lua
end

function ActionHud:OnProfileChanged()
    self:UpdateLayout()
    self:UpdateLockState()
    self:UpdateOpacity()
end

function ActionHud:OnEnable()
    self:CreateMainFrame()
    
    self:ApplySettings()
    
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
    
    self:RegisterChatCommand("actionhud", "SlashHandler")
    self:RegisterChatCommand("ah", "SlashHandler")
    
    -- Initialize Resources
    if ns.Resources and ns.Resources.Initialize then
         ns.Resources:Initialize(self)
    end
end

function ActionHud:SlashHandler(msg)
    if not msg or msg == "" then
        LibStub("AceConfigDialog-3.0"):Open("ActionHud")
    else
        LibStub("AceConfigCmd-3.0"):HandleCommand("actionhud", "ActionHud", msg)
    end
end

-- =========================================================================
-- Frame Logic
-- =========================================================================

local buttons = {}

function ActionHud:CreateMainFrame()
    if self.frame then return end
    
    local f = CreateFrame("Frame", "ActionHudFrame", UIParent)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    
    f:SetScript("OnDragStart", function(s)
        if not self.db.profile.locked then s:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local _, _, _, x, y = s:GetPoint()
        self.db.profile.xOffset = x
        self.db.profile.yOffset = y
    end)
    
    -- Drag Bg
    f.dragBg = f:CreateTexture(nil, "BACKGROUND")
    f.dragBg:SetAllPoints()
    f.dragBg:SetColorTexture(0, 1, 0, 0.3)
    f.dragBg:Hide()
    
    self.frame = f
    
    -- Create Buttons
    for i, actionID in ipairs(defaultSlots) do
        local btn = CreateFrame("Frame", nil, f)
        
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
                        b.assistGlow:SetBackdropBorderColor(0, 0.8, 1, self.db.profile.assistGlowAlpha)
                        if shown then b.assistGlow:Show() else b.assistGlow:Hide() end
                    end
                end
            end
        end)
    end
end

-- =========================================================================
-- Update Logic
-- =========================================================================

function ActionHud:ApplySettings()
    -- Apply Saved Position
    local p = self.db.profile
    if p.xOffset and p.yOffset then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", p.xOffset, p.yOffset)
    else
        self.frame:SetPoint("CENTER", 0, -220)
    end
    self.frame:Show()
    
    self:UpdateLayout()
    self:UpdateLockState()
    self:UpdateOpacity()
    self:RefreshAll()
end

function ActionHud:UpdateLayout()
    local p = self.db.profile
    local cols = 6
    local padding = 0
    
    self.frame:SetSize(cols * p.iconWidth, 4 * p.iconHeight)
    
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
    
    -- Trigger Resource Update
    if ns.Resources and ns.Resources.UpdateLayout then
        ns.Resources:UpdateLayout()
    end
end

function ActionHud:ApplyIconCrop(btn, w, h)
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

function ActionHud:UpdateLockState()
    local locked = self.db.profile.locked
    self.frame:EnableMouse(not locked)
    if locked then self.frame.dragBg:Hide() else self.frame.dragBg:Show() end
end

function ActionHud:UpdateOpacity()
    local alpha = self.db.profile.opacity
    for _, btn in ipairs(buttons) do
        if btn.icon and not btn.hasAction then
             btn.icon:SetColorTexture(0, 0, 0, alpha)
        end
    end
end

-- =========================================================================
-- Button Logic (RefreshAll, UpdateAction, etc)
-- =========================================================================

function ActionHud:RefreshAll()
    for _, btn in ipairs(buttons) do
        self:UpdateAction(btn)
        self:UpdateCooldown(btn)
        self:UpdateState(btn)
    end
end

function ActionHud:ACTIONBAR_SLOT_CHANGED(event, arg1)
    for _, btn in ipairs(buttons) do
        if btn.baseSlot == arg1 or btn.actionID == arg1 or arg1 == 0 then
            self:UpdateAction(btn)
            self:UpdateCooldown(btn)
            self:UpdateState(btn)
        end
    end
end

function ActionHud:SPELL_UPDATE_COOLDOWN()
    for _, btn in ipairs(buttons) do self:UpdateCooldown(btn) end
end

function ActionHud:UpdateStateAll()
    for _, btn in ipairs(buttons) do self:UpdateState(btn) end
end

-- Specific Update Functions
function ActionHud:UpdateAction(btn)
    local slot = btn.baseSlot
    local actionID = slot
    
    -- Paging
    if slot >= 1 and slot <= 12 then
         local page = GetActionBarPage()
         local offset = GetBonusBarOffset()
         -- Simplified Paging Logic check
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
        self:ApplyIconCrop(btn, self.db.profile.iconWidth, self.db.profile.iconHeight)
    else
        btn.hasAction = false
        btn.icon:Hide()
        btn.cd:Hide()
        btn.count:SetText("")
        btn.glow:Hide()
        if btn.assistGlow then btn.assistGlow:Hide() end
        btn.icon:SetColorTexture(0, 0, 0, self.db.profile.opacity)
        btn.icon:Show()
    end
end

function ActionHud:UpdateCooldown(btn)
    if not btn.hasAction then return end
    local start, duration = GetActionCooldown(btn.actionID)
    if start and duration and start > 0 and duration > 0 then
        -- GCD Check (Spell ID 61304)
        local gcdInfo = C_Spell.GetSpellCooldown(61304)
        if gcdInfo and gcdInfo.startTime == start and gcdInfo.duration == duration then
            btn.cd:SetDrawEdge(false)
        else
            if duration <= 1.5 then btn.cd:SetDrawEdge(false) else btn.cd:SetDrawEdge(true) end
        end
        btn.cd:SetCooldown(start, duration)
        btn.cd:Show()
    else
        -- Charges
        if btn.spellID then
            local chargeInfo = C_Spell.GetSpellCharges(btn.spellID)
            if chargeInfo and chargeInfo.cooldownStartTime > 0 and (GetTime() < chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) then
                 btn.cd:SetDrawEdge(true)
                 btn.cd:SetCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration)
                 btn.cd:Show()
                 return
            end
        end
        btn.cd:Hide()
    end
end

function ActionHud:UpdateState(btn)
   if not btn.hasAction then return end
   local actionID = btn.actionID
   
   -- Count
   local count = GetActionCount(actionID)
   if not count or count <= 1 then
       if btn.spellID then
           local c = C_Spell.GetSpellCharges(btn.spellID)
           if c then count = c.currentCharges end
       end
   end
   btn.count:SetText((count and count > 1) and count or "")
   if btn.spellID then
       local c = C_Spell.GetSpellCharges(btn.spellID)
       if c and c.maxCharges > 1 then btn.count:SetText(count) end
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
        if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
             isOverlayed = C_SpellActivationOverlay.IsSpellOverlayed(btn.spellID)
        else
             isOverlayed = IsSpellOverlayed(btn.spellID)
        end
   end
   if isOverlayed then btn.glow:Show() else btn.glow:Hide() end
end

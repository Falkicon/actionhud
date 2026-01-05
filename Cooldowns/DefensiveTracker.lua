local addonName, ns = ...
local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local DefensiveTracker = addon:NewModule("DefensiveTracker", "AceEvent-3.0")

-- ============================================================================
-- DefensiveTracker: DISABLED - NO WORKING APPROACH FOUND
-- ============================================================================
-- Exhaustive testing (see docs/aura-api-testing.md) confirmed that NO API
-- approach works for tracking secret-valued buffs in WoW 12.0 combat:
--
--   - GetPlayerAuraBySpellID: Returns nil for secret buffs
--   - GetAuraSlots: Blocked in combat (pcall fails)
--   - GetBuffDataByIndex: Blocked in combat (pcall fails)
--   - UNIT_AURA addedAuras: Fields (isHelpful, spellId) are SECRET
--   - Duration Objects: Cannot get auraInstanceID without above working
--
-- Blizzard's CooldownViewer is the only supported way to display these buffs.
-- ============================================================================

-- Test spell IDs (Warrior defensives)
local TEST_SPELLS = {
    [2565] = "Shield Block",
    [190456] = "Ignore Pain",
    [871] = "Shield Wall",
}

-- Results tracking for each approach
local results = {
    -- Approach 1: GetPlayerAuraBySpellID (known to fail for secrets)
    getPlayerAura = { status = "waiting", lastTest = nil, inCombat = nil },
    -- Approach 2: GetBuffDataByIndex loop
    getBuffIndex = { status = "waiting", lastTest = nil, inCombat = nil },
    -- Approach 3: UNIT_AURA incremental (addedAuras cache)
    unitAuraIncremental = { status = "waiting", lastTest = nil, inCombat = nil },
    -- Approach 4: Duration Object + SetTimerDuration (if StatusBar)
    durationObject = { status = "waiting", lastTest = nil, inCombat = nil },
    -- Approach 5: Duration Object + SetCooldown (for Cooldown frames)
    durationCooldown = { status = "waiting", lastTest = nil, inCombat = nil },
}

-- Aura cache for incremental approach
local auraCache = {}

local isActive = false
local testFrame = nil

function DefensiveTracker:OnInitialize()
    self.db = addon.db
end

function DefensiveTracker:OnEnable()
    -- DISABLED: No working approach found for secret-valued buffs
    -- Keep test frame code for future testing if Blizzard changes APIs
    addon:Log("DefensiveTracker: DISABLED (no working API approach)", "discovery")
end

function DefensiveTracker:OnDisable()
    isActive = false
    self:UnregisterAllEvents()
    if testFrame then testFrame:Hide() end
end

-- ============================================================================
-- Test Frame - Shows results for all approaches
-- ============================================================================

function DefensiveTracker:CreateTestFrame()
    if testFrame then return end

    testFrame = CreateFrame("Frame", "ActionHud_DefensiveTest", UIParent)
    testFrame:SetSize(300, 200)
    testFrame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)

    -- Background
    local bg = testFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    -- Title
    local title = testFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", testFrame, "TOP", 0, -5)
    title:SetText("Aura API Tests")
    testFrame.Title = title

    -- Combat indicator
    local combatText = testFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    combatText:SetPoint("TOPRIGHT", testFrame, "TOPRIGHT", -5, -5)
    combatText:SetText("OOC")
    combatText:SetTextColor(0, 1, 0)
    testFrame.CombatText = combatText

    -- Create result rows
    local approaches = {
        { key = "getPlayerAura", label = "1. GetPlayerAuraBySpellID" },
        { key = "getBuffIndex", label = "2. GetBuffDataByIndex" },
        { key = "unitAuraIncremental", label = "3. UNIT_AURA addedAuras" },
        { key = "durationObject", label = "4. Duration + SetTimerDuration" },
        { key = "durationCooldown", label = "5. Duration + SetCooldown" },
    }

    testFrame.rows = {}
    for i, approach in ipairs(approaches) do
        local row = CreateFrame("Frame", nil, testFrame)
        row:SetSize(290, 20)
        row:SetPoint("TOPLEFT", testFrame, "TOPLEFT", 5, -25 - (i * 22))

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetText(approach.label)
        label:SetWidth(180)
        label:SetJustifyH("LEFT")
        row.Label = label

        local status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        status:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        status:SetText("waiting")
        status:SetTextColor(0.5, 0.5, 0.5)
        row.Status = status

        testFrame.rows[approach.key] = row
    end

    -- Icon display area (for successful renders)
    local iconFrame = CreateFrame("Frame", nil, testFrame)
    iconFrame:SetSize(50, 50)
    iconFrame:SetPoint("BOTTOM", testFrame, "BOTTOM", 0, 10)

    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints()
    iconBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(134400) -- Default icon
    iconFrame.Icon = icon

    local cd = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(true)
    cd:SetSwipeColor(0, 0, 0, 0.7)
    cd:SetHideCountdownNumbers(false)
    iconFrame.Cooldown = cd

    testFrame.IconFrame = iconFrame

    -- Status bar for SetTimerDuration test
    local statusBar = CreateFrame("StatusBar", nil, testFrame)
    statusBar:SetSize(100, 12)
    statusBar:SetPoint("BOTTOMLEFT", testFrame, "BOTTOMLEFT", 10, 10)
    statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    statusBar:SetStatusBarColor(0.2, 0.8, 0.2)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)

    local statusBarBg = statusBar:CreateTexture(nil, "BACKGROUND")
    statusBarBg:SetAllPoints()
    statusBarBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    testFrame.StatusBar = statusBar

    testFrame:Show()
    addon:Log("DefensiveTracker: Test frame created at screen center +300x", "discovery")
end

-- ============================================================================
-- Update display
-- ============================================================================

function DefensiveTracker:UpdateDisplay()
    if not testFrame then return end

    -- Update combat indicator
    local inCombat = InCombatLockdown()
    testFrame.CombatText:SetText(inCombat and "COMBAT" or "OOC")
    testFrame.CombatText:SetTextColor(inCombat and 1 or 0, inCombat and 0 or 1, 0)

    -- Update result rows
    for key, data in pairs(results) do
        local row = testFrame.rows[key]
        if row then
            local color = { 0.5, 0.5, 0.5 } -- gray for waiting
            if data.status == "OK" then
                color = { 0, 1, 0 } -- green
            elseif data.status == "FAIL" then
                color = { 1, 0, 0 } -- red
            elseif data.status == "BLOCKED" then
                color = { 1, 0.5, 0 } -- orange
            elseif data.status == "NOSECRET" then
                color = { 1, 1, 0 } -- yellow (works but no secret buffs)
            end
            row.Status:SetText(data.status .. (data.inCombat and " (combat)" or ""))
            row.Status:SetTextColor(unpack(color))
        end
    end
end

-- ============================================================================
-- UNIT_AURA Handler - Tests all approaches
-- ============================================================================

function DefensiveTracker:UNIT_AURA(event, unit, updateInfo)
    if unit ~= "player" then return end
    if not isActive then return end

    local inCombat = InCombatLockdown()

    -- Approach 3: UNIT_AURA incremental (cache from addedAuras)
    if updateInfo then
        if updateInfo.addedAuras then
            for _, aura in ipairs(updateInfo.addedAuras) do
                -- isHelpful and spellId can be SECRET in combat - must wrap in pcall
                local isTestSpell = false
                local spellId = nil
                local ok = pcall(function()
                    -- Try to check isHelpful - may be secret
                    if aura.isHelpful and aura.spellId then
                        spellId = aura.spellId
                        isTestSpell = TEST_SPELLS[spellId] ~= nil
                    end
                end)

                if not ok then
                    -- isHelpful/spellId are SECRET - try spellId alone
                    local ok2 = pcall(function()
                        spellId = aura.spellId
                        isTestSpell = TEST_SPELLS[spellId] ~= nil
                    end)
                    if not ok2 then
                        -- Even spellId is secret - mark as blocked
                        results.unitAuraIncremental = { status = "SECRET", inCombat = inCombat }
                        addon:Log("DefensiveTracker: [3] addedAuras fields are SECRET", "discovery")
                    end
                end

                if isTestSpell and spellId then
                    auraCache[spellId] = aura
                    addon:Log("DefensiveTracker: [3] Cached " .. TEST_SPELLS[spellId] ..
                        " via addedAuras (instanceID=" .. tostring(aura.auraInstanceID) .. ")", "discovery")
                    results.unitAuraIncremental = { status = "OK", inCombat = inCombat }
                end
            end
        end

        if updateInfo.removedAuraInstanceIDs then
            for spellId, aura in pairs(auraCache) do
                for _, removedID in ipairs(updateInfo.removedAuraInstanceIDs) do
                    if aura.auraInstanceID == removedID then
                        addon:Log("DefensiveTracker: [3] Removed " .. (TEST_SPELLS[spellId] or spellId), "discovery")
                        auraCache[spellId] = nil
                        break
                    end
                end
            end
        end
    end

    -- Test all approaches
    self:TestAllApproaches(inCombat)
    self:UpdateDisplay()
end

function DefensiveTracker:TestAllApproaches(inCombat)
    -- Find first test spell to use
    local testSpellID = 2565 -- Shield Block

    -- ========================================
    -- Approach 1: GetPlayerAuraBySpellID
    -- ========================================
    local aura1 = nil
    local ok1 = pcall(function()
        aura1 = C_UnitAuras.GetPlayerAuraBySpellID(testSpellID)
    end)

    if not ok1 then
        results.getPlayerAura = { status = "BLOCKED", inCombat = inCombat }
        addon:Log("DefensiveTracker: [1] GetPlayerAuraBySpellID BLOCKED", "discovery")
    elseif aura1 then
        results.getPlayerAura = { status = "OK", inCombat = inCombat }
        addon:Log("DefensiveTracker: [1] GetPlayerAuraBySpellID found aura", "discovery")
    else
        -- API works but no aura found - could be hidden due to secrets
        results.getPlayerAura = { status = "NOSECRET", inCombat = inCombat }
    end

    -- ========================================
    -- Approach 2: GetBuffDataByIndex
    -- ========================================
    local foundByIndex = false
    local indexCount = 0
    local ok2 = pcall(function()
        for index = 1, 40 do
            local aura = C_UnitAuras.GetBuffDataByIndex("player", index, "HELPFUL")
            if not aura then break end
            indexCount = indexCount + 1
            if aura.spellId and TEST_SPELLS[aura.spellId] then
                foundByIndex = true
            end
        end
    end)

    if not ok2 then
        results.getBuffIndex = { status = "BLOCKED", inCombat = inCombat }
        addon:Log("DefensiveTracker: [2] GetBuffDataByIndex BLOCKED", "discovery")
    elseif foundByIndex then
        results.getBuffIndex = { status = "OK", inCombat = inCombat }
        addon:Log("DefensiveTracker: [2] GetBuffDataByIndex found test buff (" .. indexCount .. " auras)", "discovery")
    else
        results.getBuffIndex = { status = "NOSECRET", inCombat = inCombat }
    end

    -- ========================================
    -- Approach 4 & 5: Duration Object rendering
    -- ========================================
    -- Use cached aura from Approach 3
    for spellId, cachedAura in pairs(auraCache) do
        if cachedAura.auraInstanceID then
            -- Try to get Duration Object
            local durationObj = nil
            local ok4 = pcall(function()
                durationObj = C_UnitAuras.GetUnitAuraDuration("player", cachedAura.auraInstanceID)
            end)

            if not ok4 then
                results.durationObject = { status = "BLOCKED", inCombat = inCombat }
                results.durationCooldown = { status = "BLOCKED", inCombat = inCombat }
                addon:Log("DefensiveTracker: [4/5] GetUnitAuraDuration BLOCKED", "discovery")
            elseif durationObj then
                -- Try SetTimerDuration on StatusBar
                local ok4a = pcall(function()
                    if testFrame.StatusBar.SetTimerDuration then
                        testFrame.StatusBar:SetTimerDuration(durationObj)
                        results.durationObject = { status = "OK", inCombat = inCombat }
                        addon:Log("DefensiveTracker: [4] SetTimerDuration SUCCESS", "discovery")
                    else
                        results.durationObject = { status = "NO_API", inCombat = inCombat }
                        addon:Log("DefensiveTracker: [4] StatusBar has no SetTimerDuration method", "discovery")
                    end
                end)
                if not ok4a then
                    results.durationObject = { status = "FAIL", inCombat = inCombat }
                    addon:Log("DefensiveTracker: [4] SetTimerDuration FAILED", "error")
                end

                -- Try using expirationTime/duration directly with SetCooldown
                local ok5 = pcall(function()
                    local expTime = cachedAura.expirationTime
                    local duration = cachedAura.duration
                    if expTime and duration and duration > 0 then
                        local startTime = expTime - duration
                        testFrame.IconFrame.Cooldown:SetCooldown(startTime, duration)
                        results.durationCooldown = { status = "OK", inCombat = inCombat }
                        addon:Log("DefensiveTracker: [5] SetCooldown SUCCESS (exp=" ..
                            tostring(expTime) .. ", dur=" .. tostring(duration) .. ")", "discovery")

                        -- Update icon
                        if cachedAura.icon then
                            testFrame.IconFrame.Icon:SetTexture(cachedAura.icon)
                        end
                    end
                end)
                if not ok5 then
                    results.durationCooldown = { status = "FAIL", inCombat = inCombat }
                    addon:Log("DefensiveTracker: [5] SetCooldown FAILED (secret math?)", "error")
                end
            else
                results.durationObject = { status = "NOSECRET", inCombat = inCombat }
                results.durationCooldown = { status = "NOSECRET", inCombat = inCombat }
            end

            break -- Only test first cached aura
        end
    end
end

-- ============================================================================
-- Stubs
-- ============================================================================

function DefensiveTracker:SetLayoutMode(enabled)
end

function DefensiveTracker:UpdateSettings()
end

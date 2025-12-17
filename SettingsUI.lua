-- SettingsUI.lua
-- Defines the configuration options using AceConfig-3.0

local addonName, ns = ...
local ActionHud = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
local LSM = LibStub("LibSharedMedia-3.0")

function ActionHud:SetupOptions()
    local options = {
        name = "ActionHud",
        handler = ActionHud,
        type = 'group',
        args = {
            general = {
                name = "General",
                type = "group",
                order = 1,
                args = {
                    locked = {
                        name = "Lock Frame",
                        desc = "Lock the HUD in place.",
                        type = "toggle",
                        order = 1,
                        get = function(info) return self.db.profile.locked end,
                        set = function(info, val) 
                            self.db.profile.locked = val
                            self:UpdateLockState()
                        end,
                    },
                    iconDimensions = {
                        name = "Dimensions",
                        type = "header",
                        order = 10,
                    },
                    iconWidth = {
                        name = "Icon Width",
                        desc = "Width of the action icons.",
                        type = "range",
                        min = 10, max = 50, step = 1,
                        order = 11,
                        get = function(info) return self.db.profile.iconWidth end,
                        set = function(info, val)
                            self.db.profile.iconWidth = val
                            self:UpdateLayout()
                        end,
                    },
                    iconHeight = {
                        name = "Icon Height",
                        desc = "Height of the action icons.",
                        type = "range",
                        min = 10, max = 50, step = 1,
                        order = 12,
                        get = function(info) return self.db.profile.iconHeight end,
                        set = function(info, val)
                            self.db.profile.iconHeight = val
                            self:UpdateLayout()
                        end,
                    },
                    visuals = {
                        name = "Visuals & Opacity",
                        type = "header",
                        order = 20,
                    },
                    opacity = {
                        name = "Background Opacity",
                        desc = "Opacity of empty slots.",
                        type = "range",
                        min = 0, max = 1, step = 0.05,
                        isPercent = true,
                        order = 21,
                        get = function(info) return self.db.profile.opacity end,
                        set = function(info, val)
                            self.db.profile.opacity = val
                            self:UpdateOpacity()
                        end,
                    },
                    procGlowAlpha = {
                        name = "Proc Glow Opacity (Yellow)",
                        type = "range",
                        min = 0, max = 1, step = 0.05,
                        isPercent = true,
                        order = 22,
                        get = function(info) return self.db.profile.procGlowAlpha end,
                        set = function(info, val)
                            self.db.profile.procGlowAlpha = val
                            self:UpdateLayout() -- Glow alpha is applied during layout/update usually, or distinct function
                        end,
                    },
                    assistGlowAlpha = {
                        name = "Assist Glow Opacity (Blue)",
                        type = "range",
                        min = 0, max = 1, step = 0.05,
                        isPercent = true,
                        order = 23,
                        get = function(info) return self.db.profile.assistGlowAlpha end,
                        set = function(info, val)
                            self.db.profile.assistGlowAlpha = val
                            self:UpdateLayout()
                        end,
                    },
                    fonts = {
                        name = "Fonts",
                        type = "header",
                        order = 30,
                    },
                    cooldownFontSize = {
                        name = "Cooldown Font Size",
                        type = "range",
                        min = 6, max = 24, step = 1,
                        order = 31,
                        get = function(info) return self.db.profile.cooldownFontSize end,
                        set = function(info, val)
                            self.db.profile.cooldownFontSize = val
                            self:UpdateLayout()
                        end,
                    },
                    countFontSize = {
                        name = "Stack Count Font Size",
                        type = "range",
                        min = 6, max = 24, step = 1,
                        order = 32,
                        get = function(info) return self.db.profile.countFontSize end,
                        set = function(info, val)
                            self.db.profile.countFontSize = val
                            self:UpdateLayout()
                        end,
                    },
                },
            },
            resources = {
                name = "Resource Bars",
                type = "group",
                order = 2,
                args = {
                    enable = {
                        name = "Enable",
                        type = "toggle",
                        order = 1,
                        get = function(info) return self.db.profile.resEnabled end,
                        set = function(info, val)
                            self.db.profile.resEnabled = val
                            self:UpdateLayout()
                        end,
                    },
                    showTarget = {
                        name = "Show Target Stats",
                        desc = "Split bars to show target health/power.",
                        type = "toggle",
                        order = 2,
                        get = function(info) return self.db.profile.resShowTarget end,
                        set = function(info, val)
                            self.db.profile.resShowTarget = val
                            self:UpdateLayout()
                        end,
                    },
                    position = {
                        name = "Position",
                        type = "select",
                        values = { ["TOP"] = "Top", ["BOTTOM"] = "Bottom" },
                        order = 3,
                        get = function(info) return self.db.profile.resPosition end,
                        set = function(info, val)
                            self.db.profile.resPosition = val
                            self:UpdateLayout()
                        end,
                    },
                    layout = {
                        name = "Layout Dimensions",
                        type = "header",
                        order = 10,
                    },
                    healthHeight = {
                        name = "Health Bar Height",
                        type = "range",
                        min = 1, max = 30, step = 1,
                        order = 11,
                        get = function(info) return self.db.profile.resHealthHeight end,
                        set = function(info, val)
                            self.db.profile.resHealthHeight = val
                            self:UpdateLayout()
                        end,
                    },
                    powerHeight = {
                        name = "Power Bar Height",
                        type = "range",
                        min = 1, max = 30, step = 1,
                        order = 12,
                        get = function(info) return self.db.profile.resPowerHeight end,
                        set = function(info, val)
                            self.db.profile.resPowerHeight = val
                            self:UpdateLayout()
                        end,
                    },
                    offset = {
                        name = "Gap from HUD",
                        type = "range",
                        min = 0, max = 50, step = 1,
                        order = 13,
                        get = function(info) return self.db.profile.resOffset end,
                        set = function(info, val)
                            self.db.profile.resOffset = val
                            self:UpdateLayout()
                        end,
                    },
                    spacing = {
                        name = "Bar Spacing",
                        type = "range",
                        min = 0, max = 10, step = 1,
                        order = 14,
                        get = function(info) return self.db.profile.resSpacing end,
                        set = function(info, val)
                            self.db.profile.resSpacing = val
                            self:UpdateLayout()
                        end,
                    },
                },
            },
        },
    }
    
    -- Register Options
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud", options)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud", "ActionHud")
    
    -- Profiles
    local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("ActionHud_Profiles", profiles)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ActionHud_Profiles", "Profiles", "ActionHud")
end

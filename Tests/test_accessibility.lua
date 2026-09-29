-- Presets, presentation styles, buff evidence, and native aura-sound rules.
-- Offline only: this cannot certify native aura rendering, taint, or sound triggers.
local host = assert(loadfile("Tests/support/wow.lua"))()
local native = assert(loadfile("Tests/support/aura_container.lua"))()(host)
local addon, ns = assert(loadfile("Tests/support/load_addon.lua"))()(host)
local buffs = addon:GetModule("PlayerBuffs")
local sounds = ns.AuraSounds
local presentation = ns.Presentation
local evidence = ns.BuffEvidence
local options = ns.Settings.BuildPlayerBuffsOptions(addon).args
local profile = addon.db.profile
local function flush() host:Flush(); host:AssertNoErrors() end
local function setIDs(text) options.spellIDsGroup.args.spellIDs.set(nil, text); flush() end
local function enable(value) options.enable.set(nil, value); flush() end

-- Upgraded and fresh profiles keep today's appearance; presets are never automatic.
assert(profile.playerBuffsTimerFontSize == 0 and profile.playerBuffsCountFontSize == 12)
assert(profile.playerBuffsTextOutline == true and profile.playerBuffsBackgroundOpacity == 0)
assert(profile.playerBuffsBorderSize == 0 and profile.playerBuffsSoundEnabled == false)
assert(profile.presentationUndo == nil and not presentation:CanUndo())

-- Native aura-sound API contract (Blizzard 12.1.0 UnitAuraDocumentation).
local adds, removes, nextSoundID, active = {}, {}, 100, {}
Enum.UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 }
C_UnitAuras = {
	AddAuraSound = function(trigger, info)
		assert(not host.combat, "AddAuraSound is restricted in combat")
		assert(trigger == 0 and info.unitToken == "player" and type(info.spellID) == "number")
		assert(type(info.soundFileName) == "string" or type(info.soundFileID) == "number")
		nextSoundID = nextSoundID + 1
		active[nextSoundID] = info.spellID
		adds[#adds + 1] = { id = nextSoundID, spellID = info.spellID, file = info.soundFileName }
		return nextSoundID
	end,
	RemoveAuraSound = function(soundID)
		assert(active[soundID], "removed an unknown sound rule")
		active[soundID] = nil
		removes[#removes + 1] = soundID
	end,
}
local function activeCount() local n = 0; for _ in pairs(active) do n = n + 1 end; return n end

profile.playerBuffsXOffset, profile.playerBuffsYOffset = 12, -34
profile.playerBuffsIconSize = 30
setIDs("184364,871"); enable(true)
assert(buffs:GetStatus() == "active" and #native.slots == 2)
local selections, xOffset = profile.playerBuffsSpellIDs, profile.playerBuffsXOffset

-- Style presets: exact preview, selections/positions/sounds preserved, undo.
local changes = presentation:GetChanges("large")
assert(#changes > 5)
assert(presentation:DescribeChanges("large"):find("Icon size", 1, true))
sounds:SetRule(184364, { sound = "bundle:raid" })
profile.playerBuffsSoundEnabled = true
assert(presentation:ApplyPreset("large"))
assert(profile.playerBuffsIconSize == 36 and profile.playerBuffsCountFontSize == 16)
assert(profile.playerBuffsSpellIDs == selections and profile.playerBuffsXOffset == xOffset)
assert(profile.playerBuffsEnabled == true and profile.playerBuffsSoundEnabled == true)
assert(profile.playerBuffSounds["184364"].sound == "bundle:raid", "presets never change audio")
assert(profile.ufConfig.player.healthText.name.size == 14 and profile.trinketsTimerFontSize == "large")
flush()
assert(host.fonts.ActionHudPlayerBuffCountFont.size == 16, "font objects update live")
assert(native.slots[1].anchor:GetWidth() == 36)
assert(presentation:CanUndo() and presentation:GetUndoName())
assert(presentation:Undo())
assert(profile.playerBuffsIconSize == 30 and profile.playerBuffsCountFontSize == 12)
assert(profile.ufConfig.player.healthText.name.size == 11 and profile.trinketsTimerFontSize == "medium")
assert(not presentation:CanUndo() and profile.presentationUndo == nil)
flush()
-- Only the most recent application is undone; manual customization survives a later preset.
assert(presentation:ApplyPreset("large"))
profile.playerBuffsColumns = 3
assert(presentation:ApplyPreset("contrast"))
assert(profile.playerBuffsBorderSize == 2 and profile.playerBuffsBackgroundOpacity == 0.75)
assert(presentation:Undo())
assert(profile.playerBuffsIconSize == 36 and profile.playerBuffsBorderSize == 0 and profile.playerBuffsColumns == 3)
assert(not presentation:CanUndo() and not presentation:Undo(), "only the newest application is retained")
assert(not presentation:ApplyPreset("missing"))
assert(not presentation:ApplyPreset("large"), "re-applying an identical preset changes nothing")
profile.playerBuffsIconSize = 30; flush()

-- Synthetic sample: labeled, never reads game state.
presentation:ShowSample("large")
assert(presentation:IsSampleShown() and ActionHudPresentationSample:IsShown())
assert(profile.playerBuffsIconSize == 30, "preview must not apply the preset")
presentation:HideSample()
assert(not presentation:IsSampleShown())

-- Sounds: one rule per intended event, cleanup on every lifecycle exit.
sounds:Sync()
assert(#adds == 1 and adds[1].spellID == 184364 and activeCount() == 1)
assert(adds[1].file == sounds:ResolvePath("bundle:raid"))
sounds:Sync(); host:Fire("UNIT_AURA", "player"); flush()
assert(#adds == 1, "aura activity and repeated syncs must not duplicate rules")
assert(sounds:GetStatus(184364) == "active" and sounds:GetStatus(871) == "none")
sounds:Preview("bundle:ping")
assert(#host.playedSounds == 1 and host.playedSounds[1].channel == "Master")
sounds:SetRule(184364, { mute = true })
assert(activeCount() == 0 and sounds:GetStatus(184364) == "muted")
sounds:SetRule(184364, { mute = false })
assert(activeCount() == 1)
sounds:SetRule(871, { sound = "bundle:alarm" })
assert(activeCount() == 2)
sounds:SetRule(871, { sound = false })
assert(activeCount() == 1 and profile.playerBuffSounds["871"] == nil)
sounds:SetRule(184364, { sound = "bundle:ready" })
assert(activeCount() == 1 and adds[#adds].file == sounds:ResolvePath("bundle:ready"), "changing a sound replaces its rule")
profile.playerBuffsSoundEnabled = false; sounds:Sync()
assert(activeCount() == 0 and sounds:GetStatus(184364) == "off")
profile.playerBuffsSoundEnabled = true; sounds:Sync()
assert(activeCount() == 1)
setIDs("871"); assert(activeCount() == 0, "removing the buff retires its rule")
setIDs("184364,871"); assert(activeCount() == 1)
enable(false); assert(activeCount() == 0, "disabling the module retires rules")
enable(true); assert(activeCount() == 1)
local original = addon.db:GetCurrentProfile()
addon.db:SetProfile("sound-profile"); flush()
assert(activeCount() == 0, "profile switches retire rules")
addon.db:SetProfile(original); flush()
assert(activeCount() == 1)
-- Combat defers registration and retirement.
host:SetCombat(true)
sounds:SetRule(184364, { mute = true })
assert(activeCount() == 1, "no restricted calls in combat")
host:SetCombat(false); flush()
assert(activeCount() == 0)
sounds:SetRule(184364, { mute = false })

-- Ambiguous catalog candidates stay unresolved instead of double alerting.
local getCandidates = ns.BlizzardBuffCatalog.GetCandidateSpellIDs
function ns.BlizzardBuffCatalog:GetCandidateSpellIDs(id)
	if id == 871 then return { [871] = true, [872] = true } end
	return getCandidates(self, id)
end
sounds:SetRule(871, { sound = "bundle:alarm" })
assert(sounds:GetStatus(871) == "ambiguous" and activeCount() == 1)
sounds:SetRule(871, { sound = false })
ns.BlizzardBuffCatalog.GetCandidateSpellIDs = getCandidates

-- A removed shared-media sound falls back to a bundled default.
sounds:SetRule(184364, { sound = "lsm:Removed Sound" })
assert(sounds:ResolvePath("lsm:Removed Sound") == sounds:ResolvePath("bundle:raid"))
assert(profile.playerBuffSounds["184364"].sound == "bundle:raid" and activeCount() == 1)
local values, order = sounds:GetChoices()
assert(values["bundle:raid"] and #order >= 4)
-- Unsupported clients explain instead of failing.
local api = C_UnitAuras.AddAuraSound
C_UnitAuras.AddAuraSound = nil
assert(sounds:GetStatus(184364) == "unavailable" and not sounds:IsAvailable())
C_UnitAuras.AddAuraSound = api
-- A refused rule is reported, not assumed working.
sounds:SetRule(184364, { mute = true })
C_UnitAuras.AddAuraSound = function() error("refused") end
sounds:SetRule(184364, { mute = false })
assert(sounds:GetStatus(184364) == "failed")
C_UnitAuras.AddAuraSound = api
sounds:Sync(); assert(sounds:GetStatus(184364) == "active" or sounds:GetStatus(184364) == "pending")

-- Evidence: documented mapping, unverified IDs stay usable, restricted discovery is not "invalid".
local mapped = evidence:Classify(97463)
assert(mapped[1] == "documented" or mapped[2] == "documented")
local explanation = evidence:Explain(97462)
assert(explanation:find("97462", 1, true) and explanation:find("97463", 1, true))
assert(evidence:Explain(97463):find("simc") == nil)
local unknown = evidence:Classify(999999)
assert(#unknown == 1 and unknown[1] == "manual")
assert(buffs:ParseSpellIDs("999999")[1] == 999999, "unverified IDs remain usable")
assert(evidence:Explain(999999):find("still works", 1, true))
host:SetCombat(true)
assert(evidence:DiscoveryNote():find("not invalid", 1, true))
host:SetCombat(false)
-- Player-confirmed results are separate, bounded, and labelled with context.
addon.db.char.playerBuffRecentIDs = { 5 }
assert(evidence:GetResult(871) == nil)
assert(evidence:Record(871, "appearance", false) and evidence:Record(871, "sound", true))
local result = evidence:GetResult(871)
assert(result.appearance == "missing" and result.sound == "sounded" and result.class == "WARRIOR")
assert(evidence:DescribeResult(871):find("WARRIOR", 1, true) and evidence:DescribeResult(871):find("12.1.0", 1, true))
assert(#addon.db.char.playerBuffRecentIDs == 1 and addon.db.char.playerBuffRecentIDs[1] == 5)
for id = 1000, 1040 do evidence:Record(id, "appearance", true) end
local stored = 0
for _ in pairs(addon.db.char.playerBuffSetup.tests) do stored = stored + 1 end
assert(stored <= 24 and evidence:GetResult(871) == nil and evidence:GetResult(1040))
evidence:Forget(1040); assert(evidence:GetResult(1040) == nil)
assert(not evidence:Record("bad", "appearance", true) and not evidence:Record(5, "other", true))
local diagnosis = table.concat(evidence:Diagnose(184364), "\n")
assert(diagnosis:find("184364", 1, true) and diagnosis:find("Player Buffs state", 1, true))

-- Settings surfaces build and the picker exposes per-buff evidence and sound controls.
local slot = options.selected.args.slot1.args
assert(slot.evidence and slot.sound and slot.soundPreview and slot.soundMute)
assert(slot.evidence.name():find("Evidence", 1, true))
slot.sound.set(nil, "bundle:ping"); slot.soundMute.set(nil, true)
assert(profile.playerBuffSounds["184364"].mute == true)
assert(options.setupCheck.args.diagnostics and options.appearance.args.border and options.audio.args.enable)
options.appearance.args.border.set(nil, 3); flush()
assert(profile.playerBuffsBorderSize == 3)
local accessibility = ns.Settings.BuildAccessibilityOptions(addon).args
accessibility.apply.func(); flush()
assert(accessibility.undo.disabled() == false)
accessibility.undo.func()
print("accessibility, aura sound, and evidence tests passed")

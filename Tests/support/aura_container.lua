-- Inbound-only native aura-container contract. This does not emulate WoW aura
-- processing or certify native taint rules; forbidden observations fail loudly.
return function(host)
	local native = { containers = {}, slots = {}, writes = 0 }
	local createFrame = CreateFrame
	C_AuraContainerUtil = { ProcessCustomAuraButtonApplicationCountOptions = function(options) return options end }
	local function unavailable() error("addon observed or reconfigured a restricted aura widget") end
	CreateFrame = function(kind, name, parent, template)
		if kind ~= "AuraContainer" then return createFrame(kind, name, parent, template) end
		assert(not host.combat, "native container creation must defer in combat")
		assert(template == "CustomAuraContainerTemplate")
		local frame = createFrame(kind, name, parent, template)
		local state = { frame = frame, slots = {}, enabled = false }
		native.containers[#native.containers + 1] = state
		function frame:SetEnabled(value)
			assert(type(value) == "boolean")
			state.enabled = value
			native.writes = native.writes + 1
		end
		function frame:SetUnit(unit)
			assert(unit == "player", "only player helpful auras are supported")
			state.unit = unit
		end
		local function validateFilters(filters)
			assert(type(filters) == "table" and type(filters.includeSpellIDs) == "table")
			for id, included in pairs(filters.includeSpellIDs) do
				assert(type(id) == "number" and id > 0 and id == math.floor(id) and included == true)
			end
		end
		function frame:AddAuraSlot(key, filter, options)
			assert(not host.combat, "slot creation must defer in combat")
			assert(type(key) == "string" and not state.slots[key])
			assert(filter == "HELPFUL")
			validateFilters(options.candidateFilters)
			local button = createFrame("AuraButton", nil, frame, "CustomAuraButtonTemplate")
			local slot = { key = key, button = button, filters = options.candidateFilters }
			function button:SetAllPoints(anchor) slot.anchor = anchor end
			function button:SetIcon(texture) slot.icon = texture end
			function button:SetDurationCooldown(cooldown) slot.cooldown = cooldown end
			function button:SetApplicationCount(fontString) slot.count = fontString end
			if not native.failInitialization then
				options.initializeFrame(button)
			end
			assert(slot.anchor or native.failInitialization, "slots must anchor to ordinary public frames")
			state.slots[key] = slot
			native.slots[#native.slots + 1] = slot
			-- Restrict the widget and all children after the native initializer.
			for _, object in ipairs({ button, slot.icon, slot.cooldown, slot.count }) do
				for _, method in ipairs({ "GetWidth", "GetHeight", "GetSize", "IsShown", "IsVisible", "GetText",
					"GetValue", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight",
					"Show", "Hide", "SetText", "SetCooldown", "SetCountdownMillisecondsThreshold" }) do
					object[method] = unavailable
				end
			end
			return setmetatable({}, { __index = unavailable })
		end
		function frame:SetAuraSlotCandidateFilters(key, filters)
			assert(not host.combat, "saved slot filters must defer in combat")
			validateFilters(filters)
			assert(state.slots[key])
			state.slots[key].filters = filters
			native.writes = native.writes + 1
		end
		for _, method in ipairs({ "GetWidth", "GetHeight", "GetSize", "IsShown", "IsVisible",
			"GetAuraGroupFrameCount", "GetAuraGroupFrame", "GetChildren" }) do
			frame[method] = unavailable
		end
		return frame
	end
	return native
end

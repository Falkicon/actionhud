-- Inbound-only native aura-container contract. This does not emulate WoW aura
-- processing or certify native taint rules; forbidden observations fail loudly.
return function(host)
	local native = { containers = {}, slots = {}, writes = 0, refreshes = 0 }
	local createFrame = CreateFrame
	C_AuraContainerUtil = { ProcessCustomAuraButtonApplicationCountOptions = function(options) return options end }
	AuraContainerSortMethod = { UnitFrameDebuff = 2 }
	AuraContainerSortDirection = { Normal = 0 }
	AnchorUtil = { FlowDirection = { Right = 1, Down = 3, Up = 2 } }
	local function unavailable() error("addon observed or reconfigured a restricted aura widget") end
	local function restrict(object)
		for _, method in ipairs({ "GetWidth", "GetHeight", "GetSize", "IsShown", "IsVisible", "GetText",
			"GetValue", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight",
			"Show", "Hide", "SetText", "SetCooldown", "SetCountdownMillisecondsThreshold", "SetScale",
			"GetChildren", "HookScript", "SetScript", "SetIcon", "SetDurationCooldown", "SetApplicationCount",
			"EnableMouse", "SetMouseMotionEnabled", "SetMouseClickEnabled" }) do
			object[method] = unavailable
		end
	end
	local function initializeButton(frame, options, slot)
		local button = createFrame("AuraButton", nil, frame, "CustomAuraButtonTemplate")
		slot.button = button
		function button:SetAllPoints(anchor) slot.anchor = anchor end
		function button:SetIcon(texture)
			assert(not native.failButtonInitialization, "native widget initialization failed")
			slot.icon = texture
		end
		function button:SetDurationCooldown(cooldown) slot.cooldown = cooldown end
		function button:SetApplicationCount(fontString) slot.count = fontString end
		if not native.failInitialization then options.initializeFrame(button) end
		for _, object in ipairs({ button, slot.icon, slot.cooldown, slot.count }) do restrict(object) end
	end
	function native:CreateGroupBatch(state, key)
		local group = assert(state.groups[key])
		for _ = 1, 10 do
			local slot = {}
			initializeButton(state.frame, group.options, slot)
			group.buttons[#group.buttons + 1] = slot
		end
	end
	CreateFrame = function(kind, name, parent, template)
		if kind ~= "AuraContainer" then return createFrame(kind, name, parent, template) end
		assert(not host.combat, "native container creation must defer in combat")
		assert(template == "CustomAuraContainerTemplate")
		local frame = createFrame(kind, name, parent, template)
		local state = { frame = frame, slots = {}, groups = {}, enabled = false, refreshes = 0 }
		native.containers[#native.containers + 1] = state
		function frame:SetEnabled(value)
			assert(not host.combat, "container enablement must defer in combat")
			assert(type(value) == "boolean")
			state.enabled = value
			native.writes = native.writes + 1
		end
		function frame:SetUnit(unit)
			assert(not host.combat, "unit configuration must defer in combat")
			assert(unit == "player" or unit == "target")
			state.unit = unit
		end
		function frame:UpdateAllAuras()
			state.refreshes = state.refreshes + 1
			native.refreshes = native.refreshes + 1
		end
		local function configure(key, value)
			assert(not host.combat, "native layout configuration must defer in combat")
			state[key] = value
			native.writes = native.writes + 1
		end
		function frame:SetFlowLayoutAnchorPoint(value) configure("flowAnchor", value) end
		function frame:SetFlowLayoutGrowthDirection(horizontal, vertical) configure("growth", { horizontal, vertical }) end
		function frame:SetFlowLayoutMaximumLineSize(value) configure("lineSize", value) end
		function frame:AddAuraGroup(key, filter, options)
			assert(not host.combat, "group creation must defer in combat")
			assert(not native.failGroupCreation, "native group creation failed")
			assert(type(key) == "string" and not state.groups[key])
			assert(filter == "HARMFUL" and type(options.candidateFilters) == "table")
			assert(next(options.candidateFilters) == nil, "friendly debuffs must not filter by identity")
			assert(options.sortMethod == AuraContainerSortMethod.UnitFrameDebuff)
			assert(options.sortDirection == AuraContainerSortDirection.Normal)
			state.groups[key] = { filter = filter, options = options, buttons = {},
				maxCount = options.maxFrameCount, layout = options.layout }
			native:CreateGroupBatch(state, key)
		end
		function frame:SetAuraGroupMaxFrameCount(key, value)
			configure("maxCount", value)
			state.groups[key].maxCount = value
		end
		function frame:SetAuraGroupLayout(key, value)
			configure("layout", value)
			state.groups[key].layout = value
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
			local slot = { key = key, filters = options.candidateFilters }
			initializeButton(frame, options, slot)
			assert(slot.anchor or native.failInitialization, "slots must anchor to ordinary public frames")
			state.slots[key] = slot
			native.slots[#native.slots + 1] = slot
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

-- Load every script in the real TOC/XML order using an already initialized host.
return function(host, savedVariables)
	ActionHudDB = savedVariables
	local ns, loaded = {}, {}
	local function loadPath(path)
		path = path:gsub("\\", "/")
		local file = assert(io.open(path, "r"), path)
		local source = file:read("*a")
		file:close()
		if path:match("%.xml$") then
			source = source:gsub("<!%-%-.-%-%->", "")
			local directory = path:match("^(.*[/])") or ""
			for kind, reference in source:gmatch('<(%a+)%s+file="([^"]+)"') do
				if kind == "Include" or kind == "Script" then loadPath(directory .. reference) end
			end
		else
			assert(not loaded[path], "duplicate load: " .. path)
			loaded[path] = true
			assert(loadfile(path))("ActionHud", ns)
		end
	end
	for line in io.lines("ActionHud.toc") do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" and line:sub(1, 1) ~= "#" then loadPath(line) end
	end
	local addon = LibStub("AceAddon-3.0"):GetAddon("ActionHud")
	host:Fire("ADDON_LOADED", "ActionHud")
	host.loggedIn = true
	host:Fire("PLAYER_LOGIN")
	host:Flush()
	host:Fire("PLAYER_ENTERING_WORLD")
	host:Flush()
	return addon, ns
end

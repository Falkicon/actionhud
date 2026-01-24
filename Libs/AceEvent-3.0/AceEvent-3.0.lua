--- AceEvent-3.0 provides event registration and secure dispatching.
-- All dispatching is done using **CallbackHandler-1.0**. AceEvent is a simple wrapper around
-- CallbackHandler, and dispatches all game events or addon message to the registrees.
--
-- **AceEvent-3.0** can be embeded into your addon, either explicitly by calling AceEvent:Embed(MyAddon) or by
-- specifying it as an embeded library in your AceAddon. All functions will be available on your addon object
-- and can be accessed directly, without having to explicitly call AceEvent itself.\\
-- It is recommended to embed AceEvent, otherwise you'll have to specify a custom `self` on all calls you
-- make into AceEvent.
-- @class file
-- @name AceEvent-3.0
-- @release $Id$
local CallbackHandler = LibStub("CallbackHandler-1.0")

local MAJOR, MINOR = "AceEvent-3.0", 6
local AceEvent = LibStub:NewLibrary(MAJOR, MINOR)

if not AceEvent then
	return
end

-- Lua APIs
local pairs = pairs

-- WoW 12.0+: Frames can become protected/tainted. Always create a fresh
-- anonymous frame to avoid inheriting taint from earlier addon loads.
if AceEvent.frame then
	pcall(function()
		AceEvent.frame:UnregisterAllEvents()
		AceEvent.frame:SetScript("OnEvent", nil)
	end)
end
AceEvent.frame = CreateFrame("Frame") -- always fresh anonymous frame
AceEvent.embeds = AceEvent.embeds or {} -- what objects embed this lib

-- APIs and registry for blizzard events, using CallbackHandler lib
if not AceEvent.events then
	AceEvent.events = CallbackHandler:New(AceEvent, "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents")
end

-- WoW 12.0+: RegisterEvent can be protected during addon init.
-- Use pcall and defer if needed.
local pendingEvents = {}

function AceEvent.events:OnUsed(target, eventname)
	local success = pcall(AceEvent.frame.RegisterEvent, AceEvent.frame, eventname)
	if not success then
		pendingEvents[eventname] = true
		if not AceEvent.deferTimer then
			AceEvent.deferTimer = C_Timer.After(0, function()
				AceEvent.deferTimer = nil
				for ev in pairs(pendingEvents) do
					pcall(AceEvent.frame.RegisterEvent, AceEvent.frame, ev)
				end
				wipe(pendingEvents)
			end)
		end
	end
end

function AceEvent.events:OnUnused(target, eventname)
	pendingEvents[eventname] = nil
	pcall(AceEvent.frame.UnregisterEvent, AceEvent.frame, eventname)
end

-- APIs and registry for IPC messages, using CallbackHandler lib
if not AceEvent.messages then
	AceEvent.messages = CallbackHandler:New(AceEvent, "RegisterMessage", "UnregisterMessage", "UnregisterAllMessages")
	AceEvent.SendMessage = AceEvent.messages.Fire
end

--- embedding and embed handling
local mixins = {
	"RegisterEvent",
	"UnregisterEvent",
	"RegisterMessage",
	"UnregisterMessage",
	"SendMessage",
	"UnregisterAllEvents",
	"UnregisterAllMessages",
}

--- Register for a Blizzard Event.
-- The callback will be called with the optional `arg` as the first argument (if supplied), and the event name as the second (or first, if no arg was supplied)
-- Any arguments to the event will be passed on after that.
-- @name AceEvent:RegisterEvent
-- @class function
-- @paramsig event[, callback [, arg]]
-- @param event The event to register for
-- @param callback The callback function to call when the event is triggered (funcref or method, defaults to a method with the event name)
-- @param arg An optional argument to pass to the callback function

--- Unregister an event.
-- @name AceEvent:UnregisterEvent
-- @class function
-- @paramsig event
-- @param event The event to unregister

--- Register for a custom AceEvent-internal message.
-- The callback will be called with the optional `arg` as the first argument (if supplied), and the event name as the second (or first, if no arg was supplied)
-- Any arguments to the event will be passed on after that.
-- @name AceEvent:RegisterMessage
-- @class function
-- @paramsig message[, callback [, arg]]
-- @param message The message to register for
-- @param callback The callback function to call when the message is triggered (funcref or method, defaults to a method with the event name)
-- @param arg An optional argument to pass to the callback function

--- Unregister a message
-- @name AceEvent:UnregisterMessage
-- @class function
-- @paramsig message
-- @param message The message to unregister

--- Send a message over the AceEvent-3.0 internal message system to other addons registered for this message.
-- @name AceEvent:SendMessage
-- @class function
-- @paramsig message, ...
-- @param message The message to send
-- @param ... Any arguments to the message

-- Embeds AceEvent into the target object making the functions from the mixins list available on target:..
-- @param target target object to embed AceEvent in
function AceEvent:Embed(target)
	for k, v in pairs(mixins) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

-- AceEvent:OnEmbedDisable( target )
-- target (object) - target object that is being disabled
--
-- Unregister all events messages etc when the target disables.
-- this method should be called by the target manually or by an addon framework
function AceEvent:OnEmbedDisable(target)
	target:UnregisterAllEvents()
	target:UnregisterAllMessages()
end

-- Script to fire blizzard events into the event listeners
local events = AceEvent.events
AceEvent.frame:SetScript("OnEvent", function(this, event, ...)
	events:Fire(event, ...)
end)

--- Finally: upgrade our old embeds
for target, v in pairs(AceEvent.embeds) do
	AceEvent:Embed(target)
end

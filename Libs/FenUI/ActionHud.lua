-- Minimal embedded namespace for ActionHud. The addon consumes FenUI's utility
-- helpers, not its widget, theme, validation, settings, or slash-command layers.
-- The namespace is private to ActionHud: a shared global would let other addons
-- that bundle FenUI (e.g. Mechanic) overwrite these helpers at load time.
local _, ns = ...
ns.FenUI = ns.FenUI or {}

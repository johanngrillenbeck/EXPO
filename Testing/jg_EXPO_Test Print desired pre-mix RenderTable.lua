-- @description EXPO TEST Print desired pre-mix RenderTable
-- @author Johann Grillenbeck
-- @about
--   Prints the intended pre-mix RenderTable to REAPER's ReaScript console.
-- @noindex

local r = reaper
local TITLE = "EXPO TEST - Print desired pre-mix RenderTable"

local function loadTestHelpers()
	local source = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
	local scriptDir = source:match("^(.*)[/\\]") or ""
	local path = scriptDir .. "/jg_EXPO_TestRenderTableHelpers.lua"
	local ok, module = pcall(dofile, path)
	if ok and type(module) == "table" then
		return module
	end
	r.ShowMessageBox("Failed to load " .. path .. "\n\n" .. tostring(module), TITLE, 0)
	return nil
end

local T = loadTestHelpers()
if not T then
	return
end
local H, Render, moduleError = T.loadModules()
if not H or not Render then
	r.ShowMessageBox(tostring(moduleError), TITLE, 0)
	return
end

local api, apiError = Render.loadUltraschall()
if not api then
	r.ShowMessageBox("Could not load Ultraschall API.\n\n" .. tostring(apiError), TITLE, 0)
	return
end

local desired, info, buildError = T.buildDesiredRenderTable(api, H, Render)
if not desired then
	r.ShowMessageBox(tostring(buildError), TITLE, 0)
	return
end

T.printConsole(
	"EXPO pre-mix desired render table for "
		.. info.projectPath
		.. "\nCue: "
		.. info.cue.cueId
		.. "_"
		.. info.cue.version
		.. "\n"
		.. T.formatTable("Desired RenderTable", desired)
)

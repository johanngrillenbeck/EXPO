-- @description EXPO TEST Print current project RenderTable
-- @author Johann Grillenbeck
-- @about
--   Gets the current project's render settings as an Ultraschall RenderTable and prints it to the ReaScript console.
-- @noindex

local r = reaper
local TITLE = "EXPO TEST - Print current RenderTable"

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
local _, Render, moduleError = T.loadModules()
if not Render then
	r.ShowMessageBox(tostring(moduleError), TITLE, 0)
	return
end

local api, apiError = Render.loadUltraschall()
if not api then
	r.ShowMessageBox("Could not load Ultraschall API.\n\n" .. tostring(apiError), TITLE, 0)
	return
end
if type(api.GetRenderTable_Project) ~= "function" then
	r.ShowMessageBox(
	"This Ultraschall API does not provide GetRenderTable_Project (requires Ultraschall 5.3).",
		TITLE,
		0
	)
	return
end

local callOk, current = pcall(api.GetRenderTable_Project)
if not callOk or type(current) ~= "table" then
	r.ShowMessageBox("Could not retrieve the current project's RenderTable.\n\n" .. tostring(current), TITLE, 0)
	return
end

local _, projectPath = r.EnumProjects(-1)
T.printConsole(
	"Current project RenderTable"
		.. (projectPath and projectPath ~= "" and (" for " .. projectPath) or " (unsaved project)")
		.. "\n"
		.. T.formatTable("Current RenderTable", current)
)

-- @description EXPO TEST Compare desired and current pre-mix RenderTables
-- @author Johann Grillenbeck
-- @about
--   Compares the intended pre-mix RenderTable with the current project settings using Ultraschall.AreRenderTablesEqual.
-- @noindex

local r = reaper
local TITLE = "EXPO TEST - Compare pre-mix RenderTables"

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
if type(api.GetRenderTable_Project) ~= "function" then
	r.ShowMessageBox("This Ultraschall API does not provide GetRenderTable_Project.", TITLE, 0)
	return
end
if type(api.AreRenderTablesEqual) ~= "function" then
	r.ShowMessageBox("This Ultraschall API does not provide AreRenderTablesEqual.", TITLE, 0)
	return
end

local desired, info, buildError = T.buildDesiredRenderTable(api, H, Render)
if not desired then
	r.ShowMessageBox(tostring(buildError), TITLE, 0)
	return
end

local getOk, current = pcall(api.GetRenderTable_Project)
if not getOk or type(current) ~= "table" then
	r.ShowMessageBox("Could not retrieve the current project's RenderTable.\n\n" .. tostring(current), TITLE, 0)
	return
end

local compareOk, equal, countDesired, diffDesired, countCurrent, diffCurrent =
	pcall(api.AreRenderTablesEqual, desired, current)
if not compareOk then
	r.ShowMessageBox("AreRenderTablesEqual raised an error.\n\n" .. tostring(equal), TITLE, 0)
	return
end

local projectPath = info.projectPath
local report = {
	"RenderTable comparison for " .. projectPath,
	"Cue: " .. info.cue.cueId .. "_" .. info.cue.version,
	"AreRenderTablesEqual: " .. tostring(equal),
	"Desired-only/different entry count: " .. tostring(countDesired),
	"Current-only/different entry count: " .. tostring(countCurrent),
}
if type(diffDesired) == "table" then
	table.insert(report, "Entries differing in desired table: " .. T.formatTable("Desired differences", diffDesired))
end
if type(diffCurrent) == "table" then
	table.insert(
		report,
		"Entries differing in current project table: " .. T.formatTable("Current differences", diffCurrent)
	)
end

table.insert(report, T.formatTable("Desired RenderTable", desired))
table.insert(report, T.formatTable("Current project RenderTable", current))
T.printConsole(table.concat(report, "\n\n"))

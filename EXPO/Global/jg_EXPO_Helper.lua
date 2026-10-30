-- @description EXPO Helper
-- @author Johann Grillenbeck
-- @about
--   # EXPO Helper
--   Common functions to avoid duplication across EXPO scripts.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @changelog
--   Added script.
-- @noindex

local r = reaper

local H = {}

-------------------------------------------------------------------------------
-- EXPO v1 project spec
-------------------------------------------------------------------------------

local expoTree = {
	{ name = "01_Footage" },
	{ name = "02_Assembly" },
	{
		name = "03_Cues",
		children = {
			{ name = "03-01_Exports" },
			{ name = "03-02_SWS-Snapshots" },
		},
	},
	{ name = "04_Previews" },
	{ name = "05_Delivery" },
}

local expoProjectFolders = {
	["02_Assembly"] = true,
	["03_Cues"] = true,
}

local expoMinimumTracksAssembly = {
	{ name = "VIDEO" },
	{
		name = "CUES",
		children = {
			{ name = "Preview" },
			{ name = "Full Mix" },
		},
	},
}

local expoMinimumRulerLanesAssembly = {
	{ name = "EXPO (Video Preview)", timebase = "time" },
	{ name = "EXPO (Final Audio)", timebase = "time" },
}

---@class ExpoReport
---@field valid boolean Overall validation status
---@field projectType "Assembly"|"Cue" The detected or expected project type
---@field prefix string|nil Project prefix (e.g. "TF")
---@field validExpoTree boolean|nil
---@field validProjectFolder boolean|nil
---@field validFileName boolean|nil
---@field missingFolders string[]
---@field missingTracks string[]
---@field missingRulerLanes string[]
---@field frameRate number
---at some point: add version parsing here (v2, v04, v3.5, etc.)

---@param projectType "Assembly"|"Cue"
---@return ExpoReport
local function createExpoReport(projectType)
	---@type ExpoReport
	return {
		valid = true,
		projectType = projectType,
		prefix = nil,
		validExpoTree = nil,
		validProjectFolder = nil,
		validFileName = nil,
		missingFolders = {},
		missingTracks = {},
		missingRulerLanes = {},
		frameRate = 0,
	}
end

-------------------------------------------------------------------------------
-- Folder structure parsing functions
-------------------------------------------------------------------------------
-- Naming convention:
-- "Path" for a whole string of directories like C:/Projects/Film_01/03_Cues/XY_1m01_v01.rpp
-- "Folder" for just the folder name like "03_Cues".

---@return string | nil
local function getProjectPath()
	local _, projectPath = reaper.EnumProjects(-1)
	if not projectPath or projectPath == "" then
		reaper.ShowConsoleMsg("EXPO: Could not get project path. Is the project saved?\n")
		return nil
	else
		projectPath = projectPath:gsub("\\", "/")
		return projectPath
	end
end

local function parseProjectPath(projectPath)
	local parentPath, filename = projectPath:match("^(.+)/([^/]+)$")
	if not parentPath then
		return nil, nil, nil
	end
	local expoRoot, folder = parentPath:match("^(.+)/([^/]+)$")
	return expoRoot, folder, filename
end

local function getSubfolders(path)
	local folders = {}
	local i = 0
	while true do
		local folder = reaper.EnumerateSubdirectories(path, i)
		if not folder then
			break
		end
		folders[folder] = true
		i = i + 1
	end
	return folders
end

---check if path folder tree is valid against table, return first missing folder
---@param path string
---@param tree table
---@return boolean valid, string|nil missingFolder
local function isValidTree(path, tree)
	local folders = getSubfolders(path)
	for _, folder in ipairs(tree) do
		if not folders[folder.name] then
			reaper.ShowConsoleMsg("EXPO - Missing folder: " .. folder.name .. "in " .. path .. "\n")
			return false, folder.name -- a way to not break here but keep iterating so we don't stop at the first missing folder?
		end
		--- reaper.ShowConsoleMsg("EXPO - Found folder: " .. folder.name .. "\n")
		if folder.children then
			local childPath = path .. "/" .. folder.name
			local valid = isValidTree(childPath, folder.children)
			if not valid then
				return false, folder.children
			end
		end
	end
	return true
end

-------------------------------------------------------------------------------
-- Project structure validation functions
-------------------------------------------------------------------------------

---@param projectType any
---@param tree table
---@return boolean, table missingTracks
local function containsMinimumTracks(projectType, tree)
	local missingTracks = {}
	return true, missingTracks
end

---@param project any
---@param tree any
---@return boolean, table missingRulerLanes
local function containsMinimumRulerLanes(project, tree)
	local missingRulerLanes = {}
	return true, missingRulerLanes
end

-------------------------------------------------------------------------------
-- Check if current project is a valid Assembly Project according to the EXPO 1.0 spec
-------------------------------------------------------------------------------

---@return boolean isValid, ExpoReport report
function H.validateAssembly()
	local isValid = true
	local report = createExpoReport("Assembly")

	-- get paths and catch nil exceptions (project not saved, folder levels not deep enough, etc.)
	local projectPath = getProjectPath()
	if not projectPath then
		report.valid = false
		report.validExpoTree = false
		report.missingFolders = { "projectPath" }
		return false, report
	end
	local expoRoot, projectFolder, fileName = parseProjectPath(projectPath)
	if not (expoRoot and projectFolder and fileName) then
		report.valid = false
		report.validExpoTree = false
		table.insert(report.missingFolders, "expoRoot")
		return false, report
	end

	-- is parent folder "02_Assembly"?
	if projectFolder ~= "02_Assembly" then
		report.valid = false
		report.validProjectFolder = false
		table.insert(report.missingFolders, "projectFolder") -- in outputReport, if type = assembly and missingFolder = projectFolder, output "Assembly Project must reside in Folder 02_Assembly." Same for Cue and 03_Cues.
	else
		report.validProjectFolder = true
	end

	-- validate fileName and output prefix
	local prefix = fileName:match("^([^_]+)_Assembly%.rpp$")
	if not prefix then
		report.valid = false
		report.validFileName = false
	else
		report.validFileName = true
		report.prefix = prefix
	end

	-- is expoRoot folder tree valid?
	if not isValidTree(expoRoot, expoTree) then
		report.valid = false
		report.validExpoTree = false
		-- at some point: insert missing folders list, but that needs a new tree validation function.
	else
		report.validExpoTree = true
	end

	-- contains all tracks from expoMinimumTracksAssembly?

	-- contains all Ruler Lanes from expoMinimumRulerLanesAssembly?

	-- is project timebase time?

	-- check framerate

	isValid = report.valid
	return isValid, report
end

function H.makeValidAssembly()
	local valid, report = H.validateAssembly()
end

-------------------------------------------------------------------------------
-- Check if current project is a valid Cue Project according to the EXPO 1.0 spec
-------------------------------------------------------------------------------

function H.validateCue() end

function H.makeValidCue() end

-------------------------------------------------------------------------------
-- Check if current Cue project is a Multicue Project according to the EXPO 1.0 spec
-------------------------------------------------------------------------------

function H.cueOrMulticue() end

return H

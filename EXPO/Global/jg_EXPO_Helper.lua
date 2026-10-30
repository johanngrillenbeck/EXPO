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

-- For Assembly Projects:

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

-- For Cue Projects: TBD

local expoMinimumTracksCue = {}
local expoMinimumRulerLanesCue = {}

-------------------------------------------------------------------------------
-- EXPO v1 project validation report
-------------------------------------------------------------------------------

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
---@field wrongTimebaseRulerLanes string[] Prescribed lanes that exist but are not on timebase "time"
---@field validTimebase boolean|nil Project timebase is "time"
---@field projectTimebase number|nil Raw PROJECT_TIMEBASE (0=time, 1=beats pos/len/rate, 2=beats pos only)
---@field frameRate number
---@field dropFrame boolean
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
		wrongTimebaseRulerLanes = {},
		validTimebase = nil,
		projectTimebase = nil,
		frameRate = 0,
		dropFrame = false,
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

local minimumTracksByType = { Assembly = expoMinimumTracksAssembly, Cue = expoMinimumTracksCue }
local minimumRulerLanesByType = { Assembly = expoMinimumRulerLanesAssembly, Cue = expoMinimumRulerLanesCue }
local rulerLaneTimebaseValues = { time = 0 } -- RULER_LANE_TIMEBASE values

---Maps the full path of every track (e.g. "CUES/Preview") to whether it is a folder.
---@return table<string, boolean>
local function getTrackPaths()
	local paths = {}
	local stack = {}
	for i = 0, reaper.CountTracks(0) - 1 do
		local track = reaper.GetTrack(0, i)
		local _, name = reaper.GetTrackName(track)
		local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
		local path = #stack > 0 and (table.concat(stack, "/") .. "/" .. name) or name
		if paths[path] == nil then
			paths[path] = depth == 1
		end
		if depth == 1 then
			table.insert(stack, name)
		elseif depth < 0 then
			for _ = 1, -depth do
				table.remove(stack)
			end
		end
	end
	return paths
end

---Appends the path of every spec track that is missing (or not a folder although it has children).
local function collectMissingTracks(spec, parentPath, trackPaths, missing)
	for _, entry in ipairs(spec) do
		local path = parentPath ~= "" and (parentPath .. "/" .. entry.name) or entry.name
		local isFolder = trackPaths[path]
		if isFolder == nil or (entry.children and not isFolder) then
			table.insert(missing, path)
		end
		if entry.children then
			collectMissingTracks(entry.children, path, trackPaths, missing)
		end
	end
end

---Extra tracks are allowed; only the prescribed ones are checked.
---@param projectType "Assembly"|"Cue"
---@return boolean, string[] missingTracks Full paths like "CUES/Preview"
local function containsMinimumTracks(projectType)
	local missingTracks = {}
	collectMissingTracks(minimumTracksByType[projectType] or {}, "", getTrackPaths(), missingTracks)
	return #missingTracks == 0, missingTracks
end

---Extra lanes are allowed; only the prescribed ones are checked.
---@param projectType "Assembly"|"Cue"
---@return boolean, string[] missingRulerLanes, string[] wrongTimebaseRulerLanes
local function containsMinimumRulerLanes(projectType)
	local missingRulerLanes = {}
	local wrongTimebaseRulerLanes = {}

	-- lane name -> timebase; the first lane with a given name wins
	local lanes = {}
	local count = reaper.GetSetProjectInfo(0, "RULER_LANE_COUNT", 0, false)
	for i = 0, count - 1 do -- lane index base is not documented; verify in REAPER
		local _, name = reaper.GetSetProjectInfo_String(0, "RULER_LANE_NAME:" .. i, "", false)
		if lanes[name] == nil then
			lanes[name] = reaper.GetSetProjectInfo(0, "RULER_LANE_TIMEBASE:" .. i, 0, false)
		end
	end

	for _, lane in ipairs(minimumRulerLanesByType[projectType] or {}) do
		local timebase = lanes[lane.name]
		if timebase == nil then
			table.insert(missingRulerLanes, lane.name)
		elseif timebase ~= rulerLaneTimebaseValues[lane.timebase] then
			table.insert(wrongTimebaseRulerLanes, lane.name)
		end
	end
	return #missingRulerLanes == 0 and #wrongTimebaseRulerLanes == 0, missingRulerLanes, wrongTimebaseRulerLanes
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

	-- expoRoot is only meaningful if the project sits in the right folder, so otherwise validExpoTree stays nil
	if report.validProjectFolder then
		if not isValidTree(expoRoot, expoTree) then
			report.valid = false
			report.validExpoTree = false
			-- at some point: insert missing folders list, but that needs a new tree validation function.
		else
			report.validExpoTree = true
		end
	end

	local hasTracks, missingTracks = containsMinimumTracks("Assembly")
	report.missingTracks = missingTracks
	if not hasTracks then
		report.valid = false
	end

	local hasLanes, missingLanes, wrongTimebaseLanes = containsMinimumRulerLanes("Assembly")
	report.missingRulerLanes = missingLanes
	report.wrongTimebaseRulerLanes = wrongTimebaseLanes
	if not hasLanes then
		report.valid = false
	end

	report.projectTimebase = reaper.GetSetProjectInfo(0, "PROJECT_TIMEBASE", 0, false)
	report.validTimebase = report.projectTimebase == 0
	if not report.validTimebase then
		report.valid = false
	end

	-- framerate is only reported; it has no "right" value for an Assembly alone
	report.frameRate, report.dropFrame = reaper.TimeMap_curFrameRate(0)

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

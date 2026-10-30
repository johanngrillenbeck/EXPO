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

-- For Cue Projects:

local expoMinimumTracksCue = {} -- currently none!
local expoMinimumRulerLanesCue = {
	{ name = "EXPO", timebase = "time" },
}

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
---@field validTimebase boolean|nil Assembly-only: project timebase is "time"
---@field projectTimebase number|nil Assembly-only raw PROJECT_TIMEBASE (0=time, 1=beats pos/len/rate, 2=beats pos only)
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
			return false, folder.name -- a way to not break here but keep iterating so we don't stop at the first missing folder?
		end
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
local SET_PROJECT_TIMEBASE_TIME_COMMAND_ID = 43461
local UNSELECT_ALL_TRACKS_COMMAND_ID = 40297

---@class ExpoTrackInfo
---@field index number 0-based track index
---@field name string
---@field path string Full path like "CUES/Preview"
---@field isFolder boolean

---@return ExpoTrackInfo[]
local function getTracks()
	local tracks = {}
	local stack = {}
	for i = 0, reaper.CountTracks(0) - 1 do
		local track = reaper.GetTrack(0, i)
		local _, name = reaper.GetTrackName(track)
		local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
		local path = #stack > 0 and (table.concat(stack, "/") .. "/" .. name) or name
		table.insert(tracks, { index = i, name = name, path = path, isFolder = depth == 1 })
		if depth == 1 then
			table.insert(stack, name)
		elseif depth < 0 then
			for _ = 1, -depth do
				table.remove(stack)
			end
		end
	end
	return tracks
end

---Maps each full track path to its track info; the first track with a given path wins.
---@return table<string, ExpoTrackInfo>
local function getTrackPaths()
	local paths = {}
	for _, track in ipairs(getTracks()) do
		if paths[track.path] == nil then
			paths[track.path] = track
		end
	end
	return paths
end

---Appends the path of every spec track that is missing (or not a folder although it has children).
local function collectMissingTracks(spec, parentPath, trackPaths, missing)
	for _, entry in ipairs(spec) do
		local path = parentPath ~= "" and (parentPath .. "/" .. entry.name) or entry.name
		local track = trackPaths[path]
		if track == nil or (entry.children and not track.isFolder) then
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

---@class ExpoRulerLane
---@field index number
---@field guid string
---@field name string
---@field timebase number

---@return ExpoRulerLane[]
local function scanRulerLanes()
	local lanes = {}
	local seen = {}
	local count = reaper.GetSetProjectInfo(0, "RULER_LANE_COUNT", 0, false)
	-- the index base is undocumented, so probe 0..count and skip slots that hold no lane
	for i = 0, count do
		local _, guid = reaper.GetSetProjectInfo_String(0, "RULER_LANE_GUID:" .. i, "", false)
		if guid ~= "" and not seen[guid] then
			seen[guid] = true
			local _, name = reaper.GetSetProjectInfo_String(0, "RULER_LANE_NAME:" .. i, "", false)
			table.insert(lanes, {
				index = i,
				guid = guid,
				name = name,
				timebase = reaper.GetSetProjectInfo(0, "RULER_LANE_TIMEBASE:" .. i, 0, false),
			})
		end
	end
	return lanes
end

---Maps lane name to lane; the first lane with a given name wins.
---@return table<string, ExpoRulerLane>
local function getRulerLanes()
	local lanes = {}
	for _, lane in ipairs(scanRulerLanes()) do
		if lanes[lane.name] == nil then
			lanes[lane.name] = lane
		end
	end
	return lanes
end

---Extra lanes are allowed; only the prescribed ones are checked.
---@param projectType "Assembly"|"Cue"
---@return boolean, string[] missingRulerLanes, string[] wrongTimebaseRulerLanes
local function containsMinimumRulerLanes(projectType)
	local missingRulerLanes = {}
	local wrongTimebaseRulerLanes = {}
	local lanes = getRulerLanes()

	for _, lane in ipairs(minimumRulerLanesByType[projectType] or {}) do
		local existing = lanes[lane.name]
		if existing == nil then
			table.insert(missingRulerLanes, lane.name)
		elseif existing.timebase ~= rulerLaneTimebaseValues[lane.timebase] then
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

	-- framerate is only reported (no "right" value for an Assembly alone), so read it before any early return
	report.frameRate, report.dropFrame = reaper.TimeMap_curFrameRate(0)

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

	isValid = report.valid
	return isValid, report
end

-------------------------------------------------------------------------------
-- Fix functions
-------------------------------------------------------------------------------

---@param index number
---@param name string
---@return MediaTrack
local function insertTrack(index, name)
	reaper.InsertTrackAtIndex(index, false)
	local track = reaper.GetTrack(0, index)
	reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
	return track
end

---Makes every spec track exist at its prescribed path. Plain tracks are created at the top, folders at the
---end. Spec names are reserved, so a track with a child's name found anywhere else is moved into the folder
---(first positions, in spec order) instead of being duplicated. Spec nesting is at most two levels.
---@param spec table
local function fixTracks(spec)
	-- moving tracks goes through the track selection, so keep the user's
	local savedSelection = {}
	for i = 0, reaper.CountSelectedTracks(0) - 1 do
		table.insert(savedSelection, reaper.GetSelectedTrack(0, i))
	end

	for _, entry in ipairs(spec) do
		if not entry.children then
			if not getTrackPaths()[entry.name] then
				insertTrack(0, entry.name)
			end
		else
			if not getTrackPaths()[entry.name] then
				insertTrack(reaper.CountTracks(0), entry.name)
			end

			-- reverse order so the children end up in spec order right below the folder
			for i = #entry.children, 1, -1 do
				local childPath = entry.name .. "/" .. entry.children[i].name
				-- indices shift after every move, so look everything up again
				local tracks = getTracks()
				local trackPaths = getTrackPaths()

				if not trackPaths[childPath] then
					local candidate
					for _, track in ipairs(tracks) do
						if track.name == entry.children[i].name then
							candidate = reaper.GetTrack(0, track.index)
							break
						end
					end
					candidate = candidate or insertTrack(reaper.CountTracks(0), entry.children[i].name)

					-- makePrevFolder=1 also turns the preceding track into a folder if it isn't one
					reaper.SetOnlyTrackSelected(candidate)
					reaper.ReorderSelectedTracks(trackPaths[entry.name].index + 1, 1)
				end
			end
		end
	end

	reaper.Main_OnCommand(UNSELECT_ALL_TRACKS_COMMAND_ID, 0)
	for _, track in ipairs(savedSelection) do
		reaper.SetTrackSelected(track, true)
	end
end

---Inserts a lane, names it, and moves it to the top of the ruler.
---@param name string
---@param timebase number
local function createRulerLane(name, timebase)
	local known = {}
	for _, lane in ipairs(scanRulerLanes()) do
		known[lane.guid] = true
	end

	-- The descriptor suffix is the desired insertion position; value -1 inserts a new lane.
	reaper.GetSetProjectInfo(0, "RULER_LANE_ORDER:0", -1, true)

	-- Find the inserted lane by GUID because lane indices may shift during insertion.
	local created, top
	for _, lane in ipairs(scanRulerLanes()) do
		if not known[lane.guid] then
			created = lane
		end
		if top == nil or lane.index < top then
			top = lane.index
		end
	end
	if not created then
		return
	end

	reaper.GetSetProjectInfo_String(0, "RULER_LANE_NAME:" .. created.index, name, true)
	reaper.GetSetProjectInfo(0, "RULER_LANE_TIMEBASE:" .. created.index, timebase, true)
	if created.index ~= top then
		reaper.GetSetProjectInfo(0, "RULER_LANE_ORDER:" .. created.index, top, true)
	end
end

---@param report ExpoReport
local function fixRulerLanes(report)
	local specByName = {}
	for _, lane in ipairs(minimumRulerLanesByType[report.projectType]) do
		specByName[lane.name] = rulerLaneTimebaseValues[lane.timebase]
	end

	-- reverse order so the lanes end up in spec order at the top
	for i = #report.missingRulerLanes, 1, -1 do
		local name = report.missingRulerLanes[i]
		createRulerLane(name, specByName[name])
	end

	local lanes = getRulerLanes()
	for _, name in ipairs(report.wrongTimebaseRulerLanes) do
		reaper.GetSetProjectInfo(0, "RULER_LANE_TIMEBASE:" .. lanes[name].index, specByName[name], true)
	end
end

---Fixes what the report flags as project-level issues, then validates again.
---@param report ExpoReport|nil Result of H.validateAssembly(); validated here if omitted
---@return boolean isValid, ExpoReport report Fresh report after the fixes
function H.makeValidAssembly(report)
	if not report then
		_, report = H.validateAssembly()
	end

	reaper.Undo_BeginBlock2(0)
	reaper.PreventUIRefresh(1)

	if report.validTimebase == false then
		reaper.Main_OnCommand(SET_PROJECT_TIMEBASE_TIME_COMMAND_ID, 0)
	end
	fixRulerLanes(report)
	if #report.missingTracks > 0 then
		fixTracks(minimumTracksByType[report.projectType])
	end

	reaper.PreventUIRefresh(-1)
	reaper.TrackList_AdjustWindows(false)
	reaper.UpdateArrange()
	reaper.Undo_EndBlock2(0, "EXPO: Make project Assembly", -1)

	return H.validateAssembly()
end

-------------------------------------------------------------------------------
-- Check if current project is a valid Cue Project according to the EXPO 1.0 spec
-------------------------------------------------------------------------------

---@return boolean isValid, ExpoReport report
function H.validateCue()
	local report = createExpoReport("Cue")

	-- Framerate is informational for Cue projects, but is included in every report.
	report.frameRate, report.dropFrame = reaper.TimeMap_curFrameRate(0)

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

	if projectFolder ~= "03_Cues" then
		report.valid = false
		report.validProjectFolder = false
		table.insert(report.missingFolders, "projectFolder")
	else
		report.validProjectFolder = true
	end

	-- Require only the project prefix and .rpp extension; Cue ID/version parsing is out of scope.
	local prefix = fileName:match("^([^_]+)_[^/]*%.rpp$")
	if not prefix then
		report.valid = false
		report.validFileName = false
	else
		report.validFileName = true
		report.prefix = prefix
	end

	-- The root tree is meaningful only when the project is in its prescribed folder.
	if report.validProjectFolder then
		if not isValidTree(expoRoot, expoTree) then
			report.valid = false
			report.validExpoTree = false
		else
			report.validExpoTree = true
		end
	end

	local hasLanes, missingLanes, wrongTimebaseLanes = containsMinimumRulerLanes("Cue")
	report.missingRulerLanes = missingLanes
	report.wrongTimebaseRulerLanes = wrongTimebaseLanes
	if not hasLanes then
		report.valid = false
	end

	-- Cue projects may use any project timebase; only the EXPO lane is constrained.
	return report.valid, report
end

---Fixes missing or incorrectly timed Cue ruler lanes, then validates again.
---@param report ExpoReport|nil Result of H.validateCue(); validated here if omitted
---@return boolean isValid, ExpoReport report Fresh report after the fixes
function H.makeValidCue(report)
	if not report then
		_, report = H.validateCue()
	end

	reaper.Undo_BeginBlock2(0)
	reaper.PreventUIRefresh(1)
	fixRulerLanes(report)
	reaper.PreventUIRefresh(-1)
	reaper.TrackList_AdjustWindows(false)
	reaper.UpdateArrange()
	reaper.Undo_EndBlock2(0, "EXPO: Make project Cue", -1)

	return H.validateCue()
end

-------------------------------------------------------------------------------
-- Check if current Cue project is a Multicue Project according to the EXPO 1.0 spec
-------------------------------------------------------------------------------

function H.cueOrMulticue() end

return H

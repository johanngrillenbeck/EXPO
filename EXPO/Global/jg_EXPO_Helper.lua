-- @description EXPO Helper
-- @version 0.1
-- @author Johann Grillenbeck
-- @about
--   # EXPO Helper
--   Common functions to avoid duplication across EXPO scripts.
--   ## Currently included:
--   - isValidFolderTree()
--   - isValidAssembly()
--   - isValidCue()
--   - cueOrMulticue()
--   - isValidRegion()
--   - moveRegionToWholeFrame()
--   - getBusTracksInCue()
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @changelog
--   Added script.

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
---@field valid boolean|nil Overall validation status
---@field type "Assembly"|"Cue" The detected or expected project type
---@field prefix string|nil Project prefix (e.g. "TF")
---@field messages string[] List of human-readable issues for popups
---@field validFolder boolean|nil
---@field validExpoTree boolean|nil
---@field validFileName boolean|nil
---@field missingTracks string[]
---@field missingRulerLanes string[]

---@param type "Assembly"|"Cue"
---@return ExpoReport
local function createExpoReport(type)
	---@type ExpoReport
	return {
		valid = true,
		type = type,
		prefix = nil,
		messages = {},
		validFolder = nil,
		validFileName = nil,
		missingTracks = {},
		missingRulerLanes = {},
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
		reaper.ShowConsoleMsg("EXPO - Found folder: " .. folder.name .. "\n")
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
-- Track structure parsing functions
-------------------------------------------------------------------------------

---@param project any
---@param tree any
---@return boolean | table Issues
local function containsMinimumTracks(project, tree)
	-- return boolean
end

-------------------------------------------------------------------------------
-- Check if current project file resides in valid folder tree structure
-------------------------------------------------------------------------------

--- this became obsolete?? crazy programming paradigms being discovered here in real time...
local function isValidExpoTree(expoRoot)
	local projectPath = getProjectPath()
	if not projectPath then
		return false
	end
	reaper.ShowConsoleMsg("EXPO - Current .rpp project path: " .. projectPath .. "\n")

	local expoRoot = getExpoRoot(projectPath)
	if not expoRoot then
		return false
	end
	reaper.ShowConsoleMsg("EXPO - root folder: " .. expoRoot .. "\n")

	local valid = isValidTree(expoRoot, expoTree)
	if valid then
		reaper.ShowConsoleMsg("EXPO - Folder structure is valid!\n")
	end
	return valid
end

-------------------------------------------------------------------------------
-- Check if current project is a valid Assembly Project according to the EXPO 1.0 spec
-------------------------------------------------------------------------------

---@return boolean isValid, ExpoReport report
function H.validateAssembly()
	local report = createExpoReport("Assembly")
	local projectPath = getProjectPath()
	if not projectPath then
		---set valid false
		return false, report
	end

	local expoRoot, projectFolder, fileName = parseProjectPath(projectPath)
	-- is file named correctly?
	if fileName ~= "^([^_]+)_Assembly%.rpp$" then
		---set valid false
		---set validFileName false
		---set message "invalid filename"
		return false, report
	end
	---set validFileName true
	---parse prefix and add to report

	-- is parent folder "02_Assembly"?
	if projectFolder ~= "02_Assembly" then
		---set valid false
		---set validFolder false
		---set message "invalid folder: must be named 02_Assembly"
	end

	-- is expoRoot folder tree valid?
	if not isValidTree(expoRoot, expoTree) then -- we must catch "nil" possibility from parseProjectPath
		---set valid false
		---set validExpoTree false
		---set message "invalid filename"

	-- contains all tracks from expoMinimumTracksAssembly?

	-- contains all Ruler Lanes from expoMinimumRulerLanesAssembly?

	-- is project timebase time?

	return isValid, report
	
	--- showReportMessage(report) -> different local function that prints every message and asks for confirmation to launch the MAKE script.
	--- Should give an indication that folderTree is not fixable automatically.
	--- Even better idea: Get rid of the message field in the report and have this report function generate a message based on the reported issues?
end

function H.makeValidAssembly()
	local valid, _, report = H.validateAssembly()
end

-------------------------------------------------------------------------------
-- Check if current project is a valid Cue Project according to the EXPO 1.0 spec
-------------------------------------------------------------------------------

function H.isValidCue() end

-------------------------------------------------------------------------------
-- Check if current Cue project is a Multicue Project according to the EXPO 1.0 spec
-------------------------------------------------------------------------------

function H.cueOrMulticue() end

-- return H
-- for testing:
H.isValidAssembly()

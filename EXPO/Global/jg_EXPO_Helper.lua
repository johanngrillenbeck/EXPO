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

-------------------------------------------------------------------------------
-- Folder structure parsing functions
-------------------------------------------------------------------------------
-- Naming convention:
-- "Path" for a whole string of directories like C:/Projects/Film_01/03_Cues/XY_1m01_v01.rpp
-- "Folder" for just the folder name like "03_Cues".

local function getProjectPath()
	local project, projectPath = reaper.EnumProjects(-1)
	if not projectPath or projectPath == "" then
		reaper.ShowConsoleMsg("EXPO: Could not get project path. Is the project saved?\n")
		return nil
	else
		projectPath = projectPath:gsub("\\", "/")
		return projectPath
	end
end

local function getExpoRoot(projectPath)
	local parentPath = projectPath:match("^(.+)/")
	local expoRoot, projectFolder = parentPath:match("^(.+)/([^/]+)$")
	if not expoProjectFolders[projectFolder] then
		reaper.ShowConsoleMsg(
			"EXPO - Invalid project folder ("
				.. projectFolder
				.. ").\n"
				.. "Your Assembly Project needs to live inside 02_Assembly, your Cue Projects inside 03_Cues."
				.. "\n"
				.. "Check the EXPO documentation at https://expo.johanngrillenbeck.de for more information."
		)
		return nil
	else
		return expoRoot
	end
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

local function isValidTree(path, tree)
	local folders = getSubfolders(path)

	for _, folder in ipairs(tree) do
		if not folders[folder.name] then
			reaper.ShowConsoleMsg("EXPO - Missing folder: " .. folder.name .. "in " .. path .. "\n")
			return false
		end
		reaper.ShowConsoleMsg("EXPO - Found folder: " .. folder.name .. "\n")
		if folder.children then
			local childPath = path .. "/" .. folder.name
			local valid = isValidTree(childPath, folder.children)
			if not valid then
				return false
			end
		end
	end
	return true
end

-------------------------------------------------------------------------------
-- Check if current project file resides in valid folder tree structure
-------------------------------------------------------------------------------

function H.isValidExpoTree()
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

function H.isValidAssembly() end

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
H.isValidExpoTree()

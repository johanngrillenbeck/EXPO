-- @description EXPO Check Assembly Project
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Check assembly project
--   Use this script to validate the current project against the EXPO Assembly spec and offers to fix project-level issues.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @changelog
--   Added script.
-- @noindex

local r = reaper

local TITLE = "EXPO - Check assembly project"
local MB_OK, MB_OKCANCEL = 0, 1
local MB_RESULT_OK = 1

-------------------------------------------------------------------------------
-- Helper loading
-------------------------------------------------------------------------------

local function loadHelper()
	local info = debug.getinfo(1, "S")
	local scriptPath = info.source:match("^@(.+)$") or ""
	local dir = scriptPath:match("^(.*)[/\\]") or ""
	local root = dir:match("^(.*)[/\\][^/\\]+$") or dir
	local helperPath = root .. "/Global/jg_EXPO_Helper.lua"
	local ok, H = pcall(dofile, helperPath)
	if ok and type(H) == "table" then
		return H
	end
	r.ShowMessageBox("Failed to load helper at: " .. helperPath, TITLE, MB_OK)
	return nil
end

local H = loadHelper()
if not H then
	return
end

-------------------------------------------------------------------------------
-- Messages (fill in your own texts)
-------------------------------------------------------------------------------

local messages = {
	-- Manual issues (cannot be fixed by the script)
	projectNotSaved = "Couldn't find valid project path. Is the project saved?",
	expoRootNotFound = "Couldn't find root folder of project. Weird...",
	wrongProjectFolder = ".RPP project file is in the wrong folder. Please move the project file manually.",
	wrongFileName = "Project filename does not follow the spec. Please fix the file name manually.",
	invalidFolderTree = "Folder tree does not follow the spec. Please fix folder issues manually.",
	wrongProjectTimebase = 'Project timebase should be "Time" for an Assembly Project. Please solve manually via project settings.',

	-- Fixable issues (the missing items are appended, see formatList)
	missingTracks = "Tracks are missing:",
	missingRulerLanes = "Ruler lanes are missing:",
	wrongTimebaseRulerLanes = "Ruler lanes have the wrong timebase:",

	-- Section headers and dialogs
	manualHeader = "The following issues need to be solved manually:",
	fixableHeader = "The following issues can be fixed automatically by EXPO.",
	fixPrompt = "Press OK to fix the issues.",
	valid = "Congrats, this is valid Assembly Project! Time saved make better art.",
	fixed = "Issues have been fixed! Continue making music now.",
	stillInvalid = "Project still invalid :( Take your time to fix the issues and run me again. No hard feelings.",
	frameRate = "Double check framerate with your source material. If they differ, fix in project settings. Current framerate:",
}

-------------------------------------------------------------------------------
-- Report parsing
-------------------------------------------------------------------------------

---@param text string
---@param items string[]
---@return string
local function formatList(text, items)
	return text .. " " .. table.concat(items, ", ")
end

---Sorts the report into issues the user must fix by hand and issues H.makeValidAssembly() can fix.
---A nil field means "not checked" (e.g. project not saved) and is not an issue.
---@param report ExpoReport
---@return string[] manual, string[] fixable
local function collectIssues(report)
	local manual, fixable = {}, {}

	-- sentinel values written by H.validateAssembly()
	for _, folder in ipairs(report.missingFolders) do
		if folder == "projectPath" then
			table.insert(manual, messages.projectNotSaved)
		elseif folder == "expoRoot" then
			table.insert(manual, messages.expoRootNotFound)
		end
	end

	if report.validProjectFolder == false then
		table.insert(manual, messages.wrongProjectFolder)
	end
	if report.validFileName == false then
		table.insert(manual, messages.wrongFileName)
	end
	-- the unsaved/bad-path early returns also set validExpoTree = false; those are already covered above
	if report.validExpoTree == false and #report.missingFolders == 0 then
		table.insert(manual, messages.invalidFolderTree)
	end
	if report.validTimebase == false then
		-- report.projectTimebase holds the raw value if you want to name the wrong timebase
		table.insert(manual, messages.wrongProjectTimebase)
	end

	if #report.missingTracks > 0 then
		table.insert(fixable, formatList(messages.missingTracks, report.missingTracks))
	end
	if #report.missingRulerLanes > 0 then
		table.insert(fixable, formatList(messages.missingRulerLanes, report.missingRulerLanes))
	end
	if #report.wrongTimebaseRulerLanes > 0 then
		table.insert(fixable, formatList(messages.wrongTimebaseRulerLanes, report.wrongTimebaseRulerLanes))
	end

	return manual, fixable
end

---@param header string
---@param issues string[]
---@return string
local function formatSection(header, issues)
	return header .. "\n- " .. table.concat(issues, "\n- ")
end

---@param manual string[]
---@param fixable string[]
---@return string
local function buildIssueText(manual, fixable)
	local sections = {}
	if #manual > 0 then
		table.insert(sections, formatSection(messages.manualHeader, manual))
	end
	if #fixable > 0 then
		table.insert(sections, formatSection(messages.fixableHeader, fixable))
	end
	return table.concat(sections, "\n\n")
end

---@param report ExpoReport
---@return string
local function buildFrameRateText(report)
	return string.format("%s %s%s", messages.frameRate, report.frameRate, report.dropFrame and " (drop frame)" or "")
end

-------------------------------------------------------------------------------
-- Core Script
-------------------------------------------------------------------------------

local function main()
	local isValid, report = H.validateAssembly()
	local manual, fixable = collectIssues(report)

	if isValid then
		r.ShowMessageBox(messages.valid .. "\n\n" .. buildFrameRateText(report), TITLE, MB_OK)
		return
	end

	local issueText = buildIssueText(manual, fixable)

	-- nothing the script can fix: just show the issues
	if #fixable == 0 then
		r.ShowMessageBox(issueText, TITLE, MB_OK)
		return
	end

	local answer = r.ShowMessageBox(issueText .. "\n\n" .. messages.fixPrompt, TITLE, MB_OKCANCEL)
	if answer ~= MB_RESULT_OK then
		return
	end

	r.Undo_BeginBlock2(0)
	H.makeValidAssembly()
	r.Undo_EndBlock2(0, TITLE, -1)

	-- validate again and show the outcome
	local isValidNow, newReport = H.validateAssembly()
	if isValidNow then
		r.ShowMessageBox(messages.fixed .. "\n\n" .. buildFrameRateText(newReport), TITLE, MB_OK)
	else
		local newManual, newFixable = collectIssues(newReport)
		r.ShowMessageBox(messages.stillInvalid .. "\n\n" .. buildIssueText(newManual, newFixable), TITLE, MB_OK)
	end
end

main()

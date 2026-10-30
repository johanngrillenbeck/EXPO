-- @description EXPO Messages
-- @author Johann Grillenbeck
-- @about
--   # EXPO Messages
--   User-facing texts and report parsing shared by the EXPO action scripts.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @changelog
--   Added script.
-- @noindex

local M = {}

-------------------------------------------------------------------------------
-- User facing messages
-------------------------------------------------------------------------------

local messages = {
	-- Manual issues (cannot be fixed by the script)
	projectNotSaved = "Couldn't find valid project path. Is the project saved?",
	expoRootNotFound = "Couldn't find root folder of project. Weird...",
	wrongProjectFolder = ".RPP project file is in the wrong folder. Please move the project file manually.",
	wrongFileName = "Project filename does not follow the spec. Please fix the file name manually.",
	invalidFolderTree = "Folder tree does not follow the spec. Please fix folder issues manually.",

	-- Fixable issues (the missing items are appended, see formatList)
	wrongProjectTimebase = 'Project timebase should be "Time" for an Assembly Project.',
	missingTracks = "Tracks are missing:",
	missingRulerLanes = "Ruler lanes are missing:",
	wrongTimebaseRulerLanes = "Ruler lanes have the wrong timebase:",

	-- Section headers and dialogs
	manualHeader = "The following issues need to be solved manually:",
	fixableHeader = "The following issues can be fixed automatically by EXPO.",
	fixPrompt = "Press OK to fix the issues.",
	valid = "Congrats, this is valid Assembly Project! Time saved to make better art.",
	validCue = "Congrats, this is a valid Cue Project! Time saved to make better art.",
	fixed = "Issues have been fixed! Continue mixing now. Or already delivering?? Well, congrats!",
	fixedCue = "Cue project issues have been fixed! Continue making music now.",
	stillInvalid = "Project still invalid :( Take your time to fix the issues and run me again. No hard feelings.",
	frameRate = "Double check framerate with your source material. If they differ, fix in project settings. Current framerate:",
}

M.messages = messages

-------------------------------------------------------------------------------
-- Report parsing
-------------------------------------------------------------------------------

---@param text string
---@param items string[]
---@return string
local function formatList(text, items)
	return text .. " " .. table.concat(items, ", ")
end

---Sorts the report into issues the user must fix by hand and project issues the matching Make action can fix.
---A nil field means "not checked" (e.g. project not saved) and is not an issue.
---@param report ExpoReport
---@return string[] manual, string[] fixable
function M.collectIssues(report)
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
		table.insert(fixable, messages.wrongProjectTimebase)
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
function M.buildIssueText(manual, fixable)
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
function M.buildFrameRateText(report)
	return string.format("%s %s%s", messages.frameRate, report.frameRate, report.dropFrame and " (drop frame)" or "")
end

---Dialog text with the framerate message appended; every dialog shows it.
---@param text string
---@param report ExpoReport
---@return string
function M.withFrameRate(text, report)
	return text .. "\n\n" .. M.buildFrameRateText(report)
end

return M

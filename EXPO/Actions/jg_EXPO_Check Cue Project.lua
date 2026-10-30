-- @description EXPO Check Cue Project
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Check Cue project
--   Validates the current project against the EXPO Cue spec and offers to fix project-level issues.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @changelog
--   Added script.
-- @noindex

local r = reaper

local TITLE = "EXPO - Check Cue project"
local MB_OK, MB_OKCANCEL = 0, 1
local MB_RESULT_OK = 1

-------------------------------------------------------------------------------
-- Module loading
-------------------------------------------------------------------------------

---@param fileName string File inside the Global folder
local function loadGlobal(fileName)
	local info = debug.getinfo(1, "S")
	local scriptPath = info.source:match("^@(.+)$") or ""
	local dir = scriptPath:match("^(.*)[/\\]") or ""
	local root = dir:match("^(.*)[/\\][^/\\]+$") or dir
	local path = root .. "/Global/" .. fileName
	local ok, module = pcall(dofile, path)
	if ok and type(module) == "table" then
		return module
	end
	r.ShowMessageBox("Failed to load " .. path, TITLE, MB_OK)
	return nil
end

local H = loadGlobal("jg_EXPO_Helper.lua")
local Messages = loadGlobal("jg_EXPO_Messages.lua")
if not (H and Messages) then
	return
end
local messages = Messages.messages

-------------------------------------------------------------------------------
-- Core Script
-------------------------------------------------------------------------------

local function main()
	local isValid, report = H.validateCue()
	local manual, fixable = Messages.collectIssues(report)

	if isValid then
		r.ShowMessageBox(Messages.withFrameRate(messages.validCue, report), TITLE, MB_OK)
		return
	end

	local issueText = Messages.withFrameRate(Messages.buildIssueText(manual, fixable), report)
	if #fixable == 0 then
		r.ShowMessageBox(issueText, TITLE, MB_OK)
		return
	end

	local answer = r.ShowMessageBox(issueText .. "\n\n" .. messages.fixPrompt, TITLE, MB_OKCANCEL)
	if answer ~= MB_RESULT_OK then
		return
	end

	local isValidNow, newReport = H.makeValidCue(report)
	if isValidNow then
		r.ShowMessageBox(Messages.withFrameRate(messages.fixedCue, newReport), TITLE, MB_OK)
	else
		local newManual, newFixable = Messages.collectIssues(newReport)
		local text = messages.stillInvalid .. "\n\n" .. Messages.buildIssueText(newManual, newFixable)
		r.ShowMessageBox(Messages.withFrameRate(text, newReport), TITLE, MB_OK)
	end
end

main()

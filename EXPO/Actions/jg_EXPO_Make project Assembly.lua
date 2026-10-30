-- @description EXPO Make project Assembly
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Make project Assembly
--   Validates the current project against the EXPO Assembly spec and fixes all project-level issues.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @changelog
--   Added script.
-- @noindex

local r = reaper

local TITLE = "EXPO - Make project Assembly"
local MB_OK = 0

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
	local isValid, report = H.validateAssembly()
	if isValid then
		r.ShowMessageBox(Messages.withFrameRate(messages.valid, report), TITLE, MB_OK)
		return
	end

	local isValidNow, newReport = H.makeValidAssembly(report)
	if isValidNow then
		r.ShowMessageBox(Messages.withFrameRate(messages.fixed, newReport), TITLE, MB_OK)
	else
		local manual, fixable = Messages.collectIssues(newReport)
		local text = messages.stillInvalid .. "\n\n" .. Messages.buildIssueText(manual, fixable)
		r.ShowMessageBox(Messages.withFrameRate(text, newReport), TITLE, MB_OK)
	end
end

main()

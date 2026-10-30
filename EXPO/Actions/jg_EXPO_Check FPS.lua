-- @description EXPO Check FPS
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Check FPS
--   Compares the current Cue project's framerate with its paired Assembly project.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @changelog
--   Added script.
-- @noindex

local r = reaper

local TITLE = "EXPO - Check FPS"
local MB_OK = 0

-------------------------------------------------------------------------------
-- Module loading
-------------------------------------------------------------------------------

local function loadHelper()
	local info = debug.getinfo(1, "S")
	local scriptPath = info.source:match("^@(.+)$") or ""
	local dir = scriptPath:match("^(.*)[/\\]") or ""
	local root = dir:match("^(.*)[/\\][^/\\]+$") or dir
	local path = root .. "/Global/jg_EXPO_Helper.lua"
	local ok, helper = pcall(dofile, path)
	if ok and type(helper) == "table" then
		return helper
	end
	r.ShowMessageBox("Failed to load " .. path, TITLE, MB_OK)
	return nil
end

local H = loadHelper()
if not H then
	return
end

-------------------------------------------------------------------------------
-- Core Script
-------------------------------------------------------------------------------

local function formatRate(frameRate, dropFrame)
	if frameRate == nil then
		return "unknown"
	end
	return string.format("%.3f fps (%s)", frameRate, dropFrame and "DF" or "NDF")
end

local function getMessage(result)
	if result.status == "match" then
		return string.format(
			"Cue and Assembly framerates match: %s.",
			formatRate(result.cueFrameRate, result.cueDropFrame)
		)
	elseif result.status == "mismatch" then
		return string.format(
			"Cue and Assembly framerates do not match! That's no good. \n\nCue: %s\nAssembly: %s\n\nCorrect FPS inside this Cue or Assembly project settings and run the check again. \n Phew, glad this script exists!",
			formatRate(result.cueFrameRate, result.cueDropFrame),
			formatRate(result.assemblyFrameRate, result.assemblyDropFrame)
		)
	elseif result.status == "cue_not_saved" then
		return "Save the current Cue project before checking its paired Assembly framerate."
	elseif result.status == "invalid_cue_project" then
		return "The current project does not appear to be a saved Cue project in the expected 03_Cues folder with a project prefix."
	elseif result.status == "assembly_missing" then
		return "Could not find the paired Assembly project at:\n" .. tostring(result.assemblyPath)
	elseif result.status == "assembly_needs_save" then
		return "The Assembly project has unsaved changes. Save it, then run this check again."
	elseif result.status == "temporary_tab_failed" then
		return "Could not safely create a temporary project tab to inspect the Assembly project."
	elseif result.status == "assembly_load_failed" then
		return "Could not load or inspect the paired Assembly project.\n\n"
			.. tostring(result.detail or result.assemblyPath)
	elseif result.status == "cleanup_failed" then
		return "The Assembly framerate was checked, but EXPO could not safely close the temporary tab or restore the Cue tab.\n\n"
			.. tostring(result.detail)
	end
	return "FPS check failed with an unexpected status: " .. tostring(result.status)
end

local result = H.compareCueAssemblyFrameRate()
r.ShowMessageBox(getMessage(result), TITLE, MB_OK)

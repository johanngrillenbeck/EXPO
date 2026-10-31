-- @description EXPO Test resample mode config variable
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Test resample mode config variable
--   Sets REAPER's project render resample mode config variable to mode 10 (r8brain free).
--   Run this test action, then inspect the Render to File dialog's resample mode.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @noindex

local r = reaper
local TITLE = "EXPO - Test resample mode"
local RESAMPLE_MODE = 10
local CONFIG_VAR = "projrenderresample"

-- Check that the SWS API exists before attempting the test command.
if type(r.SNM_SetIntConfigVar) ~= "function" then
	r.ShowMessageBox(
		"SNM_SetIntConfigVar is unavailable. Install or enable the SWS extension, then run this test again.",
		TITLE,
		0
	)
	return
end

-- Set the global render resample preference to the requested mode.
local ok, result = pcall(r.SNM_SetIntConfigVar, CONFIG_VAR, RESAMPLE_MODE)
if not ok then
	r.ShowMessageBox("Could not set " .. CONFIG_VAR .. ":\n\n" .. tostring(result), TITLE, 0)
	return
end

-- SNM_SetIntConfigVar commonly returns no value, so report that the call ran;
-- the user should verify the selected mode in REAPER's Render to File dialog.
r.ShowMessageBox(
	'Called SNM_SetIntConfigVar("'
	.. CONFIG_VAR
		.. '", '
		.. RESAMPLE_MODE
		.. ").\n\n"
		.. "Open Render to File and check whether Resample mode is set to r8brain free.\n"
		.. "This test does not restore the previous preference.",
	TITLE,
	0
)

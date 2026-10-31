-- @description EXPO Test native render settings
-- @author Johann Grillenbeck
-- @about
--   Temporarily applies the pre-mix render settings, opens REAPER's Render to File dialog
--   for inspection, then restores render settings, bus names, track selection, and dirty state.
--   This script does not invoke a render command.
-- @noindex

local r = reaper
local TITLE = "EXPO - Test native render settings"
local MB_OK = 0
local MB_OKCANCEL = 1
local MB_RESULT_OK = 1
local UNSELECT_ALL_TRACKS_COMMAND_ID = 40297
local RENDER_DIALOG_COMMAND_ID = 40015 -- File: Render project...

local NUMBER_KEYS = {
	"RENDER_SETTINGS",
	"RENDER_BOUNDSFLAG",
	"RENDER_CHANNELS",
	"RENDER_SRATE",
	"RENDER_STARTPOS",
	"RENDER_ENDPOS",
	"RENDER_TAILFLAG",
	"RENDER_TAILMS",
	"RENDER_ADDTOPROJ",
	"RENDER_DITHER",
	"RENDER_NORMALIZE",
}

local STRING_KEYS = {
	"RENDER_FILE",
	"RENDER_PATTERN",
	"RENDER_FORMAT",
	"RENDER_FORMAT2",
}

local function show(message, flags)
	return r.ShowMessageBox(message, TITLE, flags or MB_OK)
end

local function loadWavFormatString()
	local api = rawget(_G, "ultraschall")
	if type(api) ~= "table" or type(api.CreateRenderCFG_WAV) ~= "function" then
		local apiPath = r.GetResourcePath() .. "/UserPlugins/ultraschall_api.lua"
		if not r.file_exists(apiPath) then
			return nil, "Ultraschall API was not found at:\n" .. apiPath
		end
		local ok, result = pcall(dofile, apiPath)
		if not ok then
			return nil, "Could not load Ultraschall API:\n" .. tostring(result)
		end
		api = rawget(_G, "ultraschall") or result
	end
	if type(api) ~= "table" or type(api.CreateRenderCFG_WAV) ~= "function" then
		return nil, "Ultraschall API does not provide CreateRenderCFG_WAV."
	end
	local ok, renderString = pcall(api.CreateRenderCFG_WAV, 2, 0, 0, 0, false)
	if not ok or type(renderString) ~= "string" or renderString == "" then
		return nil, "Could not create the requested 24-bit PCM WAV format string: " .. tostring(renderString)
	end
	return renderString
end

local function getProjectInfoNumber(project, key)
	local ok, value = pcall(r.GetSetProjectInfo, project, key, 0, false)
	if ok and type(value) == "number" then
		return value
	end
	return nil, tostring(value)
end

local function setProjectInfoNumber(project, key, value)
	local callOk, returnedValue = pcall(r.GetSetProjectInfo, project, key, value, true)
	local readOk, actualValue = pcall(r.GetSetProjectInfo, project, key, 0, false)
	local retained = callOk and readOk and type(actualValue) == "number" and math.abs(actualValue - value) < 1e-7
	local detail = string.format("%s: wanted %s; read back %s", key, tostring(value), tostring(actualValue))
	if not callOk then
		detail = detail .. "; setter error: " .. tostring(returnedValue)
	end
	return retained, detail
end

local function setProjectInfoString(project, key, value)
	local callOk, retval = pcall(r.GetSetProjectInfo_String, project, key, value, true)
	local readOk, getOk, actualValue = pcall(r.GetSetProjectInfo_String, project, key, "", false)
	local retained = callOk and retval and readOk and getOk and actualValue == value
	local detail = string.format("%s: wanted %q; read back %q", key, value, tostring(actualValue))
	if not callOk then
		detail = detail .. "; setter error: " .. tostring(retval)
	end
	return retained, detail
end

local function snapshotRenderSettings(project)
	local state = { project = project, numbers = {}, strings = {}, active = true }
	state.dirty = r.GetSetProjectInfo(project, "DIRTY", 0, false)
	for _, key in ipairs(NUMBER_KEYS) do
		local value = getProjectInfoNumber(project, key)
		if value ~= nil then
			state.numbers[key] = value
		end
	end
	for _, key in ipairs(STRING_KEYS) do
		local ok, retval, value = pcall(r.GetSetProjectInfo_String, project, key, "", false)
		if ok and retval and type(value) == "string" then
			state.strings[key] = value
		end
	end
	return state
end

local function snapshotTracks()
	local state = { active = true, selected = {}, buses = {} }
	for index = 0, r.CountTracks(0) - 1 do
		local track = r.GetTrack(0, index)
		state.selected[track] = r.IsTrackSelected(track)
		local _, name = r.GetTrackName(track)
		if name:sub(1, 2) == "B " then
			table.insert(state.buses, { track = track, originalName = name, stem = name:sub(3) })
		end
	end
	return state
end

local function restoreTracks(state)
	if not state or not state.active then
		return true, nil
	end
	local errors = {}
	r.PreventUIRefresh(1)
	for _, bus in ipairs(state.buses) do
		local ok, retval = pcall(r.GetSetMediaTrackInfo_String, bus.track, "P_NAME", bus.originalName, true)
		if not ok or not retval then
			table.insert(errors, "Could not restore track name " .. bus.originalName)
		end
	end
	local ok, err = pcall(r.Main_OnCommand, UNSELECT_ALL_TRACKS_COMMAND_ID, 0)
	if not ok then
		table.insert(errors, "Could not clear temporary selection: " .. tostring(err))
	end
	for track, selected in pairs(state.selected) do
		if selected then
			local selectOk, selectError = pcall(r.SetTrackSelected, track, true)
			if not selectOk then
				table.insert(errors, "Could not restore track selection: " .. tostring(selectError))
			end
		end
	end
	r.PreventUIRefresh(-1)
	r.TrackList_AdjustWindows(false)
	r.UpdateArrange()
	if #errors == 0 then
		state.active = false
		return true, nil
	end
	return false, table.concat(errors, "\n")
end

local function restoreRenderSettings(state, restoreDirty)
	if not state or not state.active then
		return true, nil
	end
	local errors = {}
	for key, value in pairs(state.strings) do
		local ok, retval = pcall(r.GetSetProjectInfo_String, state.project, key, value, true)
		if not ok or not retval then
			table.insert(errors, "Could not restore " .. key)
		end
	end
	for key, value in pairs(state.numbers) do
		local ok, returnedValue = pcall(r.GetSetProjectInfo, state.project, key, value, true)
		if not ok or type(returnedValue) ~= "number" then
			table.insert(errors, "Could not restore " .. key)
		end
	end
	if restoreDirty and type(state.dirty) == "number" then
		local ok, value = pcall(r.GetSetProjectInfo, state.project, "DIRTY", state.dirty, true)
		if not ok or type(value) ~= "number" then
			table.insert(errors, "Could not restore project dirty state")
		end
	end
	if #errors == 0 then
		state.active = false
		return true, nil
	end
	return false, table.concat(errors, "\n")
end

local function prepareTracks(state)
	r.PreventUIRefresh(1)
	local ok, err = xpcall(function()
		r.Main_OnCommand(UNSELECT_ALL_TRACKS_COMMAND_ID, 0)
		for _, bus in ipairs(state.buses) do
			if not r.GetSetMediaTrackInfo_String(bus.track, "P_NAME", bus.stem, true) then
				error("Could not temporarily remove the B prefix from " .. bus.originalName)
			end
			r.SetTrackSelected(bus.track, true)
		end
	end, debug.traceback)
	r.PreventUIRefresh(-1)
	r.TrackList_AdjustWindows(false)
	r.UpdateArrange()
	return ok, err
end

local function findCuePattern(projectPath)
	local baseName = projectPath:gsub("^.*[/\\]", ""):gsub("%.[Rr][Pp][Pp]$", "")
	local prefix, cueId, version = baseName:match("^([^_]+)_([^_]+)_(v%d+)")
	if prefix and cueId and cueId:match("^%d+m%d+$") and version then
		return prefix .. "_" .. cueId .. "_" .. version .. "_$track_pre-mix_TC-$starttc"
	end
	return "EXPO_TEST_$track_pre-mix_TC-$starttc"
end

local function getTestBounds(project)
	if type(r.GetSet_LoopTimeRange2) == "function" then
		local ok, startPos, endPos = pcall(r.GetSet_LoopTimeRange2, project, false, false, 0, 0, false)
		if ok and type(startPos) == "number" and type(endPos) == "number" and endPos > startPos then
			return startPos, endPos, "current time selection"
		end
	end
	local length = type(r.GetProjectLength) == "function" and r.GetProjectLength(project) or 0
	if type(length) ~= "number" or length <= 0 then
		length = 10
	end
	return 0, length, "project range fallback"
end

local function main()
	local project, projectPath = r.EnumProjects(-1)
	if not project or not projectPath or projectPath == "" then
		show("Save the project before running this test so EXPO can set a meaningful render folder and pattern.")
		return
	end
	local renderString, formatError = loadWavFormatString()
	if not renderString then
		show(formatError)
		return
	end

	local projectFolder = projectPath:match("^(.*)[/\\][^/\\]+$")
	if not projectFolder then
		show("Could not determine the current project's folder.")
		return
	end
	local master = r.GetMasterTrack(project)
	local channels = math.floor(r.GetMediaTrackInfo_Value(master, "I_NCHAN") or 0)
	if channels < 1 then
		show("Could not determine a valid Master channel count.")
		return
	end
	local trackState = snapshotTracks()
	if #trackState.buses == 0 then
		show("No bus tracks were found. Name bus tracks with the `B ` prefix before running this test.")
		return
	end
	local renderState = snapshotRenderSettings(project)
	r.atexit(function()
		local tracksRestored = restoreTracks(trackState)
		restoreRenderSettings(renderState, tracksRestored)
	end)
	local startPos, endPos, boundsSource = getTestBounds(project)
	local pattern = findCuePattern(projectPath)
	local outputFolder = projectFolder .. "/03-01_Exports"
	local results = {}
	local function record(ok, detail)
		table.insert(results, (ok and "OK: " or "NOT RETAINED: ") .. detail)
	end

	local prepared, prepareError = prepareTracks(trackState)
	if not prepared then
		restoreTracks(trackState)
		restoreRenderSettings(renderState, true)
		show("Could not prepare bus tracks for the render-dialog test.\n\n" .. tostring(prepareError))
		return
	end

	-- These are the REAPER-native render fields used by the production pre-mix action.
	record(setProjectInfoNumber(project, "RENDER_SETTINGS", 3))
	record(setProjectInfoNumber(project, "RENDER_BOUNDSFLAG", 0))
	record(setProjectInfoNumber(project, "RENDER_CHANNELS", channels))
	record(setProjectInfoNumber(project, "RENDER_SRATE", 48000))
	record(setProjectInfoNumber(project, "RENDER_STARTPOS", startPos))
	record(setProjectInfoNumber(project, "RENDER_ENDPOS", endPos))
	record(setProjectInfoNumber(project, "RENDER_TAILFLAG", 0))
	record(setProjectInfoNumber(project, "RENDER_TAILMS", 0))
	record(setProjectInfoNumber(project, "RENDER_ADDTOPROJ", 2))
	record(setProjectInfoNumber(project, "RENDER_DITHER", 0))
	record(setProjectInfoNumber(project, "RENDER_NORMALIZE", 0))

	record(setProjectInfoString(project, "RENDER_FILE", outputFolder))
	record(setProjectInfoString(project, "RENDER_PATTERN", pattern))
	record(setProjectInfoString(project, "RENDER_FORMAT", renderString))
	record(setProjectInfoString(project, "RENDER_FORMAT2", ""))

	local dialogPrompt = table.concat({
		"Temporary render settings are applied. The REAPER Render to File dialog will open for inspection.",
		"\nDo not click Render. Close/Cancel the dialog to restore the previous settings and track state.",
		"\n\nSource: RENDER_SETTINGS=3 (Selected track (stems), confirmed in the REAPER render dialog).",
		"\nSelected B tracks: " .. tostring(#trackState.buses),
		"\nBounds: " .. string.format("%.6f–%.6f seconds (%s)", startPos, endPos, boundsSource),
		"\nSample rate / channels: 48000 Hz / " .. tostring(channels),
		"\nOutput folder: " .. outputFolder,
		"\nPattern: " .. pattern,
	}, "")
	if show(dialogPrompt, MB_OKCANCEL) ~= MB_RESULT_OK then
		restoreTracks(trackState)
		restoreRenderSettings(renderState, true)
		return
	end

	local dialogOk, dialogError = pcall(r.Main_OnCommand, RENDER_DIALOG_COMMAND_ID, 0)
	local tracksRestored, trackRestoreError = restoreTracks(trackState)
	local settingsRestored, settingsRestoreError = restoreRenderSettings(renderState, tracksRestored)

	if not dialogOk then
		table.insert(results, "Render dialog command failed: " .. tostring(dialogError))
	end
	if not tracksRestored then
		table.insert(results, "Track restoration failed:\n" .. tostring(trackRestoreError))
	end
	if not settingsRestored then
		table.insert(results, "Render-setting restoration failed:\n" .. tostring(settingsRestoreError))
	end
	show(
		"Render-dialog test finished. No render was invoked by this script. Previous project settings and track state were restored where possible.\n\n"
			.. table.concat(results, "\n")
	)
end

main()

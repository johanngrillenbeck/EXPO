-- @description EXPO Render pre-mix STEMs
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Render pre-mix STEMs
--   Validates Cue regions, aligns them to frames and renders non-silent bus-track stems via REAPER.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @noindex

local r = reaper
local TITLE = "EXPO - Render pre-mix STEMs"
local MB_OK = 0
local MB_OKCANCEL = 1
local MB_RESULT_OK = 1
local UNSELECT_ALL_TRACKS_COMMAND_ID = 40297

-- Ultraschall 5.3 WAV render-string configuration.
-- CreateRenderCFG_WAV: BitDepth 2 = 24-bit PCM; LargeFiles 0 = Auto WAV/Wave64;
-- BWFChunk 0 = no BWF chunk/project filename; IncludeMarkers 0 = none; tempo metadata off.
local PREMIX_RENDER_STRING = {
	bitDepth = 2,
	largeFiles = 0,
	bwfChunk = 0,
	includeMarkers = 0,
	embedProjectTempo = false,
}

local function loadGlobal(fileName)
	local source = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
	local actionDir = source:match("^(.*)[/\\]") or ""
	local root = actionDir:match("^(.*)[/\\][^/\\]+$") or actionDir
	local path = root .. "/Global/" .. fileName
	local ok, module = pcall(dofile, path)
	if ok and type(module) == "table" then
		return module
	end
	r.ShowMessageBox("Failed to load " .. path .. "\n\n" .. tostring(module), TITLE, MB_OK)
	return nil
end

local H = loadGlobal("jg_EXPO_Helper.lua")
local Messages = loadGlobal("jg_EXPO_Messages.lua")
if not (H and Messages) then
	return
end

local function stop(message)
	r.ShowMessageBox(message, TITLE, MB_OK)
end

local function regionList(regions)
	local lines = {}
	for _, region in ipairs(regions) do
		table.insert(
			lines,
			string.format(
				"- %s (%.3f to %.3f seconds)",
				region.name ~= "" and region.name or "<unnamed>",
				region.startPos,
				region.endPos
			)
		)
	end
	return table.concat(lines, "\n")
end

local function showCueChecklist(candidates, missing, done)
	local imgui = r
	for _, functionName in ipairs({
		"ImGui_CreateContext",
		"ImGui_Begin",
		"ImGui_End",
		"ImGui_Text",
		"ImGui_Checkbox",
		"ImGui_Button",
		"ImGui_SameLine",
		"ImGui_Separator",
	}) do
		if type(imgui[functionName]) ~= "function" then
			stop(
				"ReaImGui is required to select cues for a multicue pre-mix STEM render. Install or update ReaImGui, then run this action again."
			)
			return
		end
	end

	local ctx = imgui.ImGui_CreateContext("EXPO pre-mix STEM cue selection")
	local selected = {}
	for _, region in ipairs(candidates) do
		selected[region.cue.cueId] = true
	end
	local finished, picked = false, nil
	local function close(result)
		if finished then
			return
		end
		finished, picked = true, result
	end

	local function frame()
		if finished then
			done(picked)
			return
		end
		local visible, open = imgui.ImGui_Begin(ctx, TITLE .. " - Select cues", true)
		if visible then
			imgui.ImGui_Text(ctx, "Select the cue regions whose bus-track STEMs should be rendered:")
			if #missing > 0 then
				imgui.ImGui_Text(
					ctx,
					"No matching EXPO region for: " .. H.cueList(missing) .. ". These cues will be skipped."
				)
			end
			for _, region in ipairs(candidates) do
				local cue = region.cue
				local label = cue.cueId .. "_" .. cue.version .. "  |  " .. H.formatTimecode(region.alignedStart, false)
				local _, value = imgui.ImGui_Checkbox(ctx, label, selected[cue.cueId])
				selected[cue.cueId] = value
			end
			if imgui.ImGui_Button(ctx, "Select all") then
				for _, region in ipairs(candidates) do
					selected[region.cue.cueId] = true
				end
			end
			imgui.ImGui_SameLine(ctx)
			if imgui.ImGui_Button(ctx, "Select none") then
				for _, region in ipairs(candidates) do
					selected[region.cue.cueId] = false
				end
			end
			imgui.ImGui_Separator(ctx)
			if imgui.ImGui_Button(ctx, "Render selected") then
				local result = {}
				for _, region in ipairs(candidates) do
					if selected[region.cue.cueId] then
						table.insert(result, region)
					end
				end
				close(result)
			end
			imgui.ImGui_SameLine(ctx)
			if imgui.ImGui_Button(ctx, "Cancel") then
				close(nil)
			end
		end
		imgui.ImGui_End(ctx)
		if not open and not finished then
			close(nil)
		end
		if finished then
			done(picked)
		else
			r.defer(frame)
		end
	end
	r.defer(frame)
end

local function createPremixRenderString(ultraschallApi)
	if type(ultraschallApi.CreateRenderCFG_WAV) ~= "function" then
		return nil, "Ultraschall API does not provide CreateRenderCFG_WAV."
	end
	local cfg = PREMIX_RENDER_STRING
	local ok, renderString = pcall(
		ultraschallApi.CreateRenderCFG_WAV,
		cfg.bitDepth,
		cfg.largeFiles,
		cfg.bwfChunk,
		cfg.includeMarkers,
		cfg.embedProjectTempo
	)
	if not ok or type(renderString) ~= "string" or renderString == "" then
		return nil, "Could not create the configured WAV render string: " .. tostring(renderString)
	end
	return renderString
end

local function loadUltraschallWavBuilder()
	local api = rawget(_G, "ultraschall")
	if type(api) == "table" and type(api.CreateRenderCFG_WAV) == "function" then
		return api
	end

	local apiPath = r.GetResourcePath() .. "/UserPlugins/ultraschall_api.lua"
	if not r.file_exists(apiPath) then
		return nil, "Ultraschall API file was not found at:\n" .. apiPath
	end
	local ok, returnedApi = pcall(dofile, apiPath)
	if not ok then
		return nil, "Could not load Ultraschall API from:\n" .. apiPath .. "\n\n" .. tostring(returnedApi)
	end
	api = rawget(_G, "ultraschall")
	if
		(type(api) ~= "table" or type(api.CreateRenderCFG_WAV) ~= "function")
		and type(returnedApi) == "table"
		and type(returnedApi.CreateRenderCFG_WAV) == "function"
	then
		api = returnedApi
		rawset(_G, "ultraschall", api)
	end
	if type(api) ~= "table" or type(api.CreateRenderCFG_WAV) ~= "function" then
		return nil,
			"Ultraschall API loaded, but CreateRenderCFG_WAV is unavailable. Check the installation at:\n" .. apiPath
	end
	return api
end

local function collectBusTracks()
	local tracks, names = {}, {}
	local windows = r.GetOS():match("Win") ~= nil
	for index = 0, r.CountTracks(0) - 1 do
		local track = r.GetTrack(0, index)
		local _, name = r.GetTrackName(track)
		if name:sub(1, 2) == "B " then
			local stem = name:sub(3)
			if stem:gsub("%s", "") == "" then
				return nil, "Bus track has an empty stem name: " .. name
			end
			if stem:find("_", 1, true) or stem:find('[\\/:*?"<>|]') or stem:match("[%. ]$") or stem:find("[%c]") then
				return nil, "Bus track name cannot be represented safely in the EXPO filename convention:\n\n" .. name
			end
			local key = windows and stem:lower() or stem
			if names[key] then
				return nil, "Bus tracks would produce the same stem filename:\n\n" .. names[key] .. "\n" .. name
			end
			names[key] = name
			table.insert(tracks, { track = track, originalName = name, stem = stem })
		end
	end
	return tracks
end

local function parsePremixFilename(fileName)
	local sourceName = tostring(fileName or "")
	local parseName = r.GetOS():match("Win") and sourceName:lower() or sourceName
	local prefix, cueId, version, stem, hh, mm, ss, ff =
		parseName:match("^([^_]+)_([^_]+)_v(%d+)_([^_]+)_pre%-mix_TC%-(%d+)%.(%d+)%.(%d+)%.(%d+)%.wav$")
	if not prefix or not cueId:match("^%d+m%d+$") then
		return nil
	end
	return {
		prefix = prefix,
		cueId = cueId,
		normalizedVersion = H.normalizeVersion(version),
		stem = stem,
	}
end

local function normalizedPath(path)
	local key = path:gsub("\\", "/")
	if r.GetOS():match("Win") then
		key = key:lower()
	end
	return key
end

local function findStemConflicts(directory, prefix, cue)
	local matches = {}
	local index = 0
	while true do
		local fileName = r.EnumerateFiles(directory, index)
		if not fileName then
			break
		end
		local parsed = parsePremixFilename(fileName)
		if
			parsed
			and normalizedPath(parsed.prefix) == normalizedPath(prefix)
			and parsed.cueId == cue.cueId
			and parsed.normalizedVersion == cue.normalizedVersion
		then
			table.insert(matches, directory .. "/" .. fileName)
		end
		index = index + 1
	end
	return matches
end

local NATIVE_RENDER_ACTION_ID = 41824 -- File: Render project, using most recent render settings

local NATIVE_RENDER_NUMBER_KEYS = {
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

local NATIVE_RENDER_STRING_KEYS = {
	"RENDER_FILE",
	"RENDER_PATTERN",
	"RENDER_FORMAT",
	"RENDER_FORMAT2",
}

local function snapshotNativeRenderSettings(project)
	local state = { active = true, project = project, numbers = {}, strings = {} }
	state.dirty = r.GetSetProjectInfo(project, "DIRTY", 0, false)
	if type(state.dirty) ~= "number" then
		return nil, "Could not read the Cue project's current dirty state."
	end
	for _, key in ipairs(NATIVE_RENDER_NUMBER_KEYS) do
		local ok, value = pcall(r.GetSetProjectInfo, project, key, 0, false)
		if not ok or type(value) ~= "number" then
			return nil, "Could not read the current REAPER render setting " .. key .. "."
		end
		state.numbers[key] = value
	end
	for _, key in ipairs(NATIVE_RENDER_STRING_KEYS) do
		local ok, retval, value = pcall(r.GetSetProjectInfo_String, project, key, "", false)
		if not ok or not retval or type(value) ~= "string" then
			return nil, "Could not read the current REAPER render setting " .. key .. "."
		end
		state.strings[key] = value
	end
	return state
end

local function restoreNativeRenderSettings(state, restoreDirty)
	if not state or not state.active then
		return true, nil
	end
	local errors = {}
	for _, key in ipairs(NATIVE_RENDER_STRING_KEYS) do
		local ok, retval = pcall(r.GetSetProjectInfo_String, state.project, key, state.strings[key], true)
		if not ok or not retval then
			table.insert(errors, "Could not restore REAPER render setting " .. key .. ".")
		end
	end
	for _, key in ipairs(NATIVE_RENDER_NUMBER_KEYS) do
		local ok, value = pcall(r.GetSetProjectInfo, state.project, key, state.numbers[key], true)
		if not ok or type(value) ~= "number" or math.abs(value - state.numbers[key]) > 1e-7 then
			table.insert(errors, "Could not restore REAPER render setting " .. key .. ".")
		end
	end
	if restoreDirty ~= false then
		local dirtyOk, dirtyValue = pcall(r.GetSetProjectInfo, state.project, "DIRTY", state.dirty, true)
		if not dirtyOk or type(dirtyValue) ~= "number" or dirtyValue ~= state.dirty then
			table.insert(errors, "Could not restore the Cue project's previous dirty state.")
		end
	end
	if #errors == 0 then
		state.active = false
		return true, nil
	end
	return false, table.concat(errors, "\n")
end

local function setNativeRenderNumber(project, key, value)
	local ok, returnedValue = pcall(r.GetSetProjectInfo, project, key, value, true)
	if not ok or type(returnedValue) ~= "number" then
		return false, "Could not set REAPER render setting " .. key .. "."
	end
	local readOk, actualValue = pcall(r.GetSetProjectInfo, project, key, 0, false)
	if not readOk or type(actualValue) ~= "number" or math.abs(actualValue - value) > 1e-7 then
		return false,
			"REAPER did not retain render setting " .. key .. ": expected " .. tostring(value) .. ", got " .. tostring(
				actualValue
			)
	end
	return true
end

local function setNativeRenderString(project, key, value)
	local ok, retval = pcall(r.GetSetProjectInfo_String, project, key, value, true)
	if not ok or not retval then
		return false, "Could not set REAPER render setting " .. key .. "."
	end
	local readOk, getOk, actualValue = pcall(r.GetSetProjectInfo_String, project, key, "", false)
	if not readOk or not getOk or actualValue ~= value then
		return false, "REAPER did not retain render setting " .. key .. "."
	end
	return true
end

local function applyNativeRenderSettings(project, renderString, cueSettings)
	local numberSettings = {
		{ "RENDER_SETTINGS", 3 }, -- REAPER test dialog confirms selected-track stems
		{ "RENDER_BOUNDSFLAG", 0 }, -- custom start/end bounds
		{ "RENDER_CHANNELS", cueSettings.channels },
		{ "RENDER_SRATE", 48000 },
		{ "RENDER_STARTPOS", cueSettings.region.alignedStart },
		{ "RENDER_ENDPOS", cueSettings.region.alignedEnd },
		{ "RENDER_TAILFLAG", 0 },
		{ "RENDER_TAILMS", 0 },
		{ "RENDER_ADDTOPROJ", 2 }, -- do not add to project; skip files likely to be silent
		{ "RENDER_DITHER", 0 },
		{ "RENDER_NORMALIZE", 0 },
	}
	local stringSettings = {
		RENDER_FILE = cueSettings.outputFolder:gsub("[/\\]+$", ""),
		RENDER_PATTERN = cueSettings.pattern,
		RENDER_FORMAT = renderString,
		RENDER_FORMAT2 = "",
	}
	for _, setting in ipairs(numberSettings) do
		local ok, err = setNativeRenderNumber(project, setting[1], setting[2])
		if not ok then
			return false, err
		end
	end
	for key, value in pairs(stringSettings) do
		local ok, err = setNativeRenderString(project, key, value)
		if not ok then
			return false, err
		end
	end
	return true
end

local function verifyRenderState(projectHandle, busTracks, cueSettings)
	local issues = {}
	local activeProject, activePath = r.EnumProjects(-1)
	if projectHandle and activeProject ~= projectHandle then
		table.insert(
			issues,
			"The active project changed before rendering. Expected Cue project:\n"
				.. tostring(cueSettings.projectPath)
				.. "\nActive project:\n"
				.. tostring(activePath)
		)
	end
	local expectedNumbers = {
		RENDER_SETTINGS = 3,
		RENDER_BOUNDSFLAG = 0,
		RENDER_CHANNELS = cueSettings.channels,
		RENDER_SRATE = 48000,
		RENDER_STARTPOS = cueSettings.region.alignedStart,
		RENDER_ENDPOS = cueSettings.region.alignedEnd,
		RENDER_ADDTOPROJ = 2,
	}
	for key, expected in pairs(expectedNumbers) do
		local actual = r.GetSetProjectInfo(projectHandle, key, 0, false)
		if math.abs(actual - expected) > 1e-7 then
			table.insert(issues, key .. " is " .. tostring(actual) .. "; expected " .. tostring(expected) .. ".")
		end
	end
	local expectedStrings = {
		RENDER_FILE = cueSettings.outputFolder:gsub("[/\\]+$", ""),
		RENDER_PATTERN = cueSettings.pattern,
		RENDER_FORMAT = cueSettings.renderString,
		RENDER_FORMAT2 = "",
	}
	for key, expected in pairs(expectedStrings) do
		local _, actual = r.GetSetProjectInfo_String(projectHandle, key, "", false)
		if actual ~= expected then
			table.insert(
				issues,
				key .. " was not retained: expected '" .. expected .. "', found '" .. tostring(actual) .. "'."
			)
		end
	end

	local expected = {}
	local expectedNames, actualNames = {}, {}
	for _, bus in ipairs(busTracks) do
		expected[bus.track] = true
		table.insert(expectedNames, bus.stem)
	end
	local actual = {}
	for index = 0, r.CountSelectedTracks(0) - 1 do
		local track = r.GetSelectedTrack(0, index)
		local _, name = r.GetTrackName(track)
		actual[track] = true
		table.insert(actualNames, name)
		if not expected[track] then
			table.insert(issues, "Unexpected selected track at render time: " .. tostring(name))
		end
	end
	for _, bus in ipairs(busTracks) do
		if not actual[bus.track] then
			table.insert(issues, "Bus track is not selected at render time: " .. bus.stem)
		end
		local _, name = r.GetTrackName(bus.track)
		if name ~= bus.stem then
			table.insert(
				issues,
				"Bus track name is not normalized for $track: expected '"
					.. bus.stem
					.. "', found '"
					.. tostring(name)
					.. "'."
			)
		end
	end
	local masterSelected = false
	if type(r.CountSelectedTracks2) == "function" and type(r.GetSelectedTrack2) == "function" then
		for index = 0, r.CountSelectedTracks2(0, true) - 1 do
			if r.GetSelectedTrack2(0, index, true) == r.GetMasterTrack(0) then
				masterSelected = true
				table.insert(issues, "The Master track is selected at render time.")
			end
		end
	end
	local state = string.format(
		"Render preflight: RENDER_SETTINGS=%s; selected tracks=%d/%d [%s]; expected buses=[%s]; Master selected=%s; active project=%s",
		tostring(r.GetSetProjectInfo(projectHandle, "RENDER_SETTINGS", 0, false)),
		r.CountSelectedTracks(0),
		#busTracks,
		table.concat(actualNames, ", "),
		table.concat(expectedNames, ", "),
		masterSelected and "yes" or "no",
		tostring(activePath)
	)
	if #issues > 0 then
		return nil, state .. "\n\nSelection/configuration problems:\n- " .. table.concat(issues, "\n- ")
	end
	return state
end

local function snapshotDirectoryFiles(directory)
	local files, index = {}, 0
	while true do
		local fileName = r.EnumerateFiles(directory, index)
		if not fileName then
			break
		end
		files[normalizedPath(fileName)] = true
		index = index + 1
	end
	return files
end

local function collectNewWaveFiles(directory, before)
	local files, index = {}, 0
	while true do
		local fileName = r.EnumerateFiles(directory, index)
		if not fileName then
			break
		end
		if fileName:lower():match("%.wav$") and not before[normalizedPath(fileName)] then
			table.insert(files, directory:gsub("[/\\]+$", "") .. "/" .. fileName)
		end
		index = index + 1
	end
	return files
end

local function snapshotTrackState(busTracks)
	local state = { active = true, selected = {}, busTracks = busTracks }
	for index = 0, r.CountTracks(0) - 1 do
		local track = r.GetTrack(0, index)
		state.selected[track] = r.IsTrackSelected(track)
	end
	return state
end

local function restoreTrackState(state)
	if not state or not state.active then
		return true, nil
	end
	local errors = {}
	r.PreventUIRefresh(1)
	for _, bus in ipairs(state.busTracks) do
		local callOk, setOk = pcall(r.GetSetMediaTrackInfo_String, bus.track, "P_NAME", bus.originalName, true)
		if not callOk or not setOk then
			table.insert(errors, "Could not restore track name: " .. bus.originalName)
		end
	end
	local unselectOk, unselectError = pcall(r.Main_OnCommand, UNSELECT_ALL_TRACKS_COMMAND_ID, 0)
	if not unselectOk then
		table.insert(errors, "Could not clear temporary track selection: " .. tostring(unselectError))
	end
	for track, selected in pairs(state.selected) do
		if selected then
			local selectOk, selectError = pcall(r.SetTrackSelected, track, true)
			if not selectOk then
				table.insert(errors, "Could not restore a selected track: " .. tostring(selectError))
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

local function prepareTracksForRender(state)
	r.PreventUIRefresh(1)
	local ok, err = xpcall(function()
		for _, bus in ipairs(state.busTracks) do
			if not r.GetSetMediaTrackInfo_String(bus.track, "P_NAME", bus.stem, true) then
				error("Could not temporarily remove the B prefix from track: " .. bus.originalName)
			end
		end
		r.Main_OnCommand(UNSELECT_ALL_TRACKS_COMMAND_ID, 0)
		for _, bus in ipairs(state.busTracks) do
			r.SetTrackSelected(bus.track, true)
		end
	end, debug.traceback)
	r.PreventUIRefresh(-1)
	r.TrackList_AdjustWindows(false)
	r.UpdateArrange()
	return ok, err
end

local function applyConfirmedRegionEdits(regions, selectedByCueId, nameOverrides)
	local edits, changedRegions = {}, {}
	for _, region in ipairs(regions) do
		local newName = region.confirmedName or nameOverrides[region.guid]
		if selectedByCueId[region.cue and region.cue.cueId or ""] == region then
			newName = region.cue.cueId
				.. "_"
				.. region.cue.version
				.. " "
				.. H.formatTimecode(region.alignedStart, false)
				.. " - "
				.. H.formatTimecode(region.alignedEnd, false)
		end
		if region.alignmentChanged or (newName and newName ~= region.name) then
			table.insert(edits, {
				region = region,
				startPos = region.alignmentChanged and region.alignedStart or nil,
				endPos = region.alignmentChanged and region.alignedEnd or nil,
				name = newName,
			})
			table.insert(changedRegions, region)
		end
	end
	if #edits == 0 then
		return true
	end

	local summary = {
		"Apply the following confirmed region changes before rendering? This is one undoable operation and will remain even if a render is cancelled or fails.",
	}
	for _, region in ipairs(changedRegions) do
		local line = region.name ~= "" and region.name or "<unnamed>"
		if region.alignmentChanged then
			line = line
				.. string.format(
					"\n  Frame alignment: %.6f–%.6f → %.6f–%.6f seconds",
					region.startPos,
					region.endPos,
					region.alignedStart,
					region.alignedEnd
				)
		end
		local replacement = region.confirmedName or nameOverrides[region.guid]
		if selectedByCueId[region.cue and region.cue.cueId or ""] == region then
			replacement = region.cue.cueId
				.. "_"
				.. region.cue.version
				.. " "
				.. H.formatTimecode(region.alignedStart, false)
				.. " - "
				.. H.formatTimecode(region.alignedEnd, false)
		end
		if replacement and replacement ~= region.name then
			line = line .. "\n  Name: " .. replacement
		end
		table.insert(summary, "\n- " .. line)
	end
	if r.ShowMessageBox(table.concat(summary), TITLE, MB_OKCANCEL) ~= MB_RESULT_OK then
		return false
	end
	local ok, err = H.applyRegionEdits(edits, "EXPO: Align and name pre-mix stem regions")
	if not ok then
		stop("Could not apply the confirmed region edits.\n\n" .. tostring(err))
		return false
	end
	return true
end

local function runRender(details, regions, selectedRegions, nameOverrides, renderString, busTracks)
	local outputFolder = H.getExpoRoot(details.projectPath) .. "/03_Cues/03-01_Exports"

	local plans, conflicts, conflictSet = {}, {}, {}
	local function addConflict(path)
		local key = normalizedPath(path)
		if not conflictSet[key] then
			conflictSet[key] = true
			table.insert(conflicts, path)
		end
	end
	local selectedByCueId = {}
	for _, region in ipairs(selectedRegions) do
		selectedByCueId[region.cue.cueId] = region
	end
	table.sort(selectedRegions, function(a, b)
		return a.startPos < b.startPos
	end)
	for _, region in ipairs(selectedRegions) do
		local cue = region.cue
		for _, existing in ipairs(findStemConflicts(outputFolder, details.prefix, cue)) do
			addConflict(existing)
		end
		local expected = {}
		local startTC = H.formatTimecode(region.alignedStart, true)
		for _, bus in ipairs(busTracks) do
			local fileName = details.prefix
				.. "_"
				.. cue.cueId
				.. "_"
				.. cue.version
				.. "_"
				.. bus.stem
				.. "_pre-mix_TC-"
				.. startTC
				.. ".wav"
			local outputPath = outputFolder .. "/" .. fileName
			if r.file_exists(outputPath) then
				addConflict(outputPath)
			end
			expected[normalizedPath(fileName)] = true
		end
		local pattern = details.prefix .. "_" .. cue.cueId .. "_" .. cue.version .. "_$track_pre-mix_TC-$starttc"
		table.insert(plans, { region = region, cue = cue, pattern = pattern, expected = expected })
	end
	if #conflicts > 0 then
		stop(
			"Pre-mix files already exist for this cue/version. EXPO will not overwrite or increment versioned files.\n\n"
				.. table.concat(conflicts, "\n")
				.. "\n\nSave the Cue Project with a new version index or remove the existing pre-mix STEM files manually."
		)
		return
	end

	local master = r.GetMasterTrack(0)
	local channels = math.floor(r.GetMediaTrackInfo_Value(master, "I_NCHAN") or 0)
	if channels < 1 then
		stop("Could not determine a valid Master Channel count for the pre-mix STEM renders.")
		return
	end
	if not applyConfirmedRegionEdits(regions, selectedByCueId, nameOverrides) then
		return
	end

	local renderSettingsState, settingsError = snapshotNativeRenderSettings(details.projectHandle)
	if not renderSettingsState then
		stop(
			"Could not snapshot the current REAPER render settings. No render was started.\n\n"
				.. tostring(settingsError)
		)
		return
	end
	local state = snapshotTrackState(busTracks)
	local restoreOk, restoreError
	r.atexit(function()
		local tracksRestored = restoreTrackState(state)
		restoreNativeRenderSettings(renderSettingsState, tracksRestored)
	end)
	local rendered, failed, unexpected, silentCues = {}, {}, {}, {}
	local ok, err = xpcall(function()
		local prepared, prepareError = prepareTracksForRender(state)
		if not prepared then
			error(prepareError)
		end
		for _, plan in ipairs(plans) do
			local configured, configureError = applyNativeRenderSettings(details.projectHandle, renderString, {
				outputFolder = outputFolder,
				region = plan.region,
				channels = channels,
				pattern = plan.pattern,
				renderString = renderString,
			})
			if not configured then
				error(plan.pattern .. "\n  " .. tostring(configureError))
			end
			local renderState, stateError = verifyRenderState(details.projectHandle, busTracks, {
				projectPath = details.projectPath,
				region = plan.region,
				channels = channels,
				pattern = plan.pattern,
				renderString = renderString,
				outputFolder = outputFolder,
			})
			if not renderState then
				error("Not rendering because the pre-render state is unexpected.\n\n" .. tostring(stateError))
			end
			local filesBefore = snapshotDirectoryFiles(outputFolder)
			local renderOk, renderError = pcall(r.Main_OnCommand, NATIVE_RENDER_ACTION_ID, 0)
			if not renderOk then
				error(
					"REAPER's native render action failed for pattern " .. plan.pattern .. ": " .. tostring(renderError)
				)
			end
			local matchedStemFiles = 0
			for _, path in ipairs(collectNewWaveFiles(outputFolder, filesBefore)) do
				local fileName = path:gsub("\\", "/"):match("([^/]+)$") or path
				table.insert(rendered, path)
				if plan.expected[normalizedPath(fileName)] then
					matchedStemFiles = matchedStemFiles + 1
				else
					table.insert(unexpected, path)
				end
			end
			if matchedStemFiles == 0 then
				table.insert(
					silentCues,
					plan.cue.cueId
						.. "_"
						.. plan.cue.version
						.. " (no new WAVs; render may have been cancelled or all stems may be silent)"
				)
			end
		end
	end, debug.traceback)
	restoreOk, restoreError = restoreTrackState(state)
	local settingsRestoreOk, settingsRestoreError = restoreNativeRenderSettings(renderSettingsState, restoreOk)
	if not ok then
		table.insert(failed, tostring(err))
	end
	if not restoreOk then
		table.insert(failed, "Could not restore temporary bus track names/selection:\n" .. tostring(restoreError))
	end
	if not settingsRestoreOk then
		table.insert(
			failed,
			"Could not restore the original REAPER render settings:\n" .. tostring(settingsRestoreError)
		)
	end

	local summary = {}
	if #failed > 0 then
		table.insert(
			summary,
			"Rendering stopped after an error. Confirmed region edits and completed renders have been kept."
		)
	end
	if #rendered > 0 then
		table.insert(summary, "Rendered files:\n" .. table.concat(rendered, "\n"))
	else
		table.insert(summary, "No audible bus-track outputs were rendered (all selected stems may be silent).")
	end
	if #unexpected > 0 then
		table.insert(
			summary,
			"REAPER returned paths that did not match the expected cue/stem/timecode pattern:\n"
				.. table.concat(unexpected, "\n")
		)
	end
	if #silentCues > 0 then
		table.insert(summary, "Cues with no new WAV output:\n" .. table.concat(silentCues, "\n"))
	end
	if #failed > 0 then
		table.insert(summary, "Errors:\n" .. table.concat(failed, "\n\n"))
	end
	stop(table.concat(summary, "\n\n"))
end

local function main()
	local ultraschallApi, apiError = loadUltraschallWavBuilder()
	if not ultraschallApi then
		stop(
			"Ultraschall API could not be loaded. Install it via ReaPack or check the installation, then run this action again.\n\n"
				.. tostring(apiError)
		)
		return
	end
	local renderString, renderStringError = createPremixRenderString(ultraschallApi)
	if not renderString then
		stop(renderStringError)
		return
	end

	local report = H.cueRenderPreflight(Messages, TITLE)
	if not report then
		return
	end
	local parsed, parseError = H.cueOrMulticue()
	if not parsed then
		stop("Could not parse the Cue project filename.\n\n" .. tostring(parseError))
		return
	end
	local projectHandle, projectPath = r.EnumProjects(-1)
	local details = {
		prefix = parsed.prefix,
		cues = parsed.cues,
		projectPath = projectPath,
		projectHandle = projectHandle,
	}
	local busTracks, busError = collectBusTracks()
	if not busTracks then
		stop(busError)
		return
	end
	if #busTracks == 0 then
		stop("No bus tracks were found. Name bus tracks with the `B ` prefix before rendering pre-mix STEMs.")
		return
	end

	local regions = H.getRegionsOnRulerLane("EXPO", 0)
	if #regions == 0 then
		stop(
			"There are no regions on the EXPO Ruler Lane. Create a region with the required cue time bounds; EXPO will not guess region bounds."
		)
		return
	end
	local matching = H.matchCueRegions(details.cues, regions)
	if next(matching.duplicates) then
		local lines = {}
		for cueId, duplicates in pairs(matching.duplicates) do
			table.insert(lines, cueId .. ":\n" .. regionList(duplicates))
		end
		stop(
			"Multiple EXPO regions map to the same cue and output filename. Resolve duplicate regions before rendering.\n\n"
				.. table.concat(lines, "\n\n")
		)
		return
	end

	local renameOverrides = {}
	if #matching.unmatched > 0 then
		local canConfirmUniqueAssociation = #matching.unmatched == 1 and #matching.missing == 1
		if not canConfirmUniqueAssociation then
			stop(
				"Every region on the EXPO Ruler Lane must correspond to a cue ID in this project's filename. Resolve these unmatched regions before rendering:\n\n"
					.. regionList(matching.unmatched)
			)
			return
		end
		local region, expected = matching.unmatched[1], matching.missing[1]
		local answer = r.ShowMessageBox(
			"This is the only unmatched region and "
				.. expected.cueId
				.. "_"
				.. expected.version
				.. " is the only cue missing a region. Associate this region with that cue and rename it to "
				.. expected.cueId
				.. "_"
				.. expected.version
				.. " and continue?",
			TITLE,
			MB_OKCANCEL
		)
		if answer ~= MB_RESULT_OK then
			return
		end
		region.cue = expected
		region.versionMismatch = false
		renameOverrides[region.guid] = expected.cueId .. "_" .. expected.version
		table.insert(matching.matched, region)
		matching.unmatched, matching.missing = {}, {}
	end

	for _, region in ipairs(matching.versionMismatches) do
		local expected = region.cue
		local answer = r.ShowMessageBox(
			"Region "
				.. region.name
				.. " has a different version index than the project filename.\n\nUpdate it to "
				.. expected.cueId
				.. "_"
				.. expected.version
				.. "?",
			TITLE,
			MB_OKCANCEL
		)
		if answer ~= MB_RESULT_OK then
			return
		end
		region.versionMismatch = false
		region.versionAccepted = true
		renameOverrides[region.guid] = expected.cueId .. "_" .. expected.version
		table.insert(matching.matched, region)
	end
	if #matching.matched == 0 then
		stop("No matched cue regions are available to render.")
		return
	end

	local frameRate = r.TimeMap_curFrameRate(0)
	for _, region in ipairs(regions) do
		region.alignedStart, region.alignedEnd, region.alignmentChanged =
			H.alignRegionToFrames(region.startPos, region.endPos, frameRate)
		if region.alignedEnd <= region.alignedStart then
			stop(
				"Frame alignment would make this region empty or invalid:\n\n"
					.. (region.name ~= "" and region.name or "<unnamed>")
			)
			return
		end
	end

	local function afterSelection(selectedRegions)
		if not selectedRegions or #selectedRegions == 0 then
			return
		end
		runRender(details, regions, selectedRegions, renameOverrides, renderString, busTracks)
	end
	if #details.cues > 1 then
		showCueChecklist(matching.matched, matching.missing, afterSelection)
	else
		afterSelection(matching.matched)
	end
end

main()

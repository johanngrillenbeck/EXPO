-- @description EXPO Render pre-mix STEMs
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Render pre-mix STEMs
--   Validates Cue regions, aligns them to frames and renders non-silent bus-track stems via Ultraschall.
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

-- Ultraschall 5.3 RenderTable reference and pre-mix-specific overrides.
-- Commented entries document API defaults; CreateNewRenderTable supplies them unless overridden.
-- Bounds/source/paths are action-specific; position, directory, pattern, channels and WAV string are set dynamically.
local PREMIX_RENDER_TABLE = {
	AddToProj = false, -- boolean; do not add rendered items to new tracks (factory default false)
	-- Brickwall_Limiter_Enabled = false, -- boolean; limiter enabled (factory default false)
	-- Brickwall_Limiter_Method = 1, -- integer; 1 peak, 2 true peak (factory default 1)
	-- Brickwall_Limiter_Target = 1, -- number; limiter target in dB (factory default 1)
	Source = 3, -- integer; 3 selected-track stems (not via Master)
	Bounds = 0, -- integer; 0 custom range
	-- Startposition = 0, -- number; custom range start in seconds (set dynamically per cue)
	-- Endposition = 0, -- number; custom range end in seconds (set dynamically per cue)
	-- TailFlag = 18, -- integer bitmask: 1 custom, 2 project, 4 time selection, 8 all regions, 16 selected items, 32 selected regions, 64 razor areas (factory default 18)
	-- TailMS = 0, -- integer; tail length in milliseconds (factory default 0)
	-- RenderFile = "", -- string; output directory (factory default empty; set dynamically)
	-- RenderPattern = "", -- string; filename pattern (factory default empty; set dynamically; includes REAPER $track and $starttc wildcards)
	CloseAfterRender = true, -- boolean; close render dialog when done (factory default true)
	SampleRate = 48000, -- integer; sample rate in Hz (pre-mix convention; factory default 44100)
	-- Channels = 2, -- integer; output channel count (factory default 2; set dynamically to Master channel count)
	OfflineOnlineRendering = 0, -- integer; 0 full-speed offline (factory default 0)
	-- ProjectSampleRateFXProcessing = true, -- boolean; process FX at project/hardware rate (factory default true)
	RenderResample = 10, -- integer; 10 r8brain free (pre-mix convention; factory default 3)
	-- OnlyMonoMedia = false, -- boolean; mono-only media to mono files (factory default false)
	-- MultiChannelFiles = false, -- boolean; multichannel tracks to multichannel files (factory default false)
	-- Dither = 0, -- integer bitmask: 1 master dither, 2 master noise shaping, 4 stem dither, 8 stem noise shaping (factory default 0)
	-- RenderString = "", -- string; Base64 render-format config (factory default empty; set from WAV builder)
	SilentlyIncrementFilename = false, -- boolean; do not silently increment conflicting names (factory default true)
	-- SaveCopyOfProject = false, -- boolean; save RPP copy alongside render (factory default false)
	-- RenderQueueDelay = false, -- boolean; delay queued renders (factory default false)
	-- RenderQueueDelaySeconds = 0, -- integer; queued render delay seconds (factory default 0)
	-- EmbedStretchMarkers = false, -- boolean; embed stretch markers/transient guides (factory default false)
	-- RenderString2 = "", -- string; secondary-format Base64 render config (factory default empty)
	-- EmbedTakeMarkers = false, -- boolean; embed take markers (factory default false)
	NoSilentRender = true, -- boolean; skip likely-silent outputs (pre-mix requirement; factory default false)
	-- EmbedMetaData = false, -- boolean; embed metadata (factory default false)
	-- Enable2ndPassRender = false, -- boolean; enable second pass (factory default false)
	-- Normalize_Enabled = false, -- boolean; enable normalization (factory default false)
	-- Normalize_Method = 0, -- integer; 0 LUFS-I, 1 RMS-I, 2 peak, 3 true peak, 4 LUFS-M max, 5 LUFS-S max (factory default 0)
	-- Normalize_Stems_to_Master_Target = false, -- boolean; common master target for stems vs per-file (factory default false)
	-- Normalize_Target = -24, -- number; normalization target dB (factory default -24)
	-- FadeIn_Enabled = false, -- boolean; apply render fade-in (factory default false)
	-- FadeIn = 0, -- number; fade-in seconds (factory default 0)
	-- FadeIn_Shape = 0, -- integer; 0 linear, 1 inverted quadratic, 2 quadratic, 3 inverted quartic, 4 quartic, 5 cosine S, 6 quartic S (factory default 0)
	-- FadeOut_Enabled = false, -- boolean; apply render fade-out (factory default false)
	-- FadeOut = 0, -- number; fade-out seconds (factory default 0)
	-- FadeOut_Shape = false, -- integer; factory default false
	-- OnlyChannelsSentToParent = false, -- boolean; render only channels sent to parent (factory default false)
	-- RenderStems_Prefader = false, -- boolean; render stems pre-fader (factory default false)
	-- Preserve_Start_Offset = false, -- boolean; preserve selected-media-item start offset (factory default false)
	-- Preserve_Metadata = false, -- boolean; preserve selected-media-item metadata (factory default false)
	-- RenderTable = true, -- boolean; valid-table marker (CreateNewRenderTable sets true)
	-- ReturnToDialog = false, -- boolean; return to render dialog after rendering (factory default false)
	SaveRenderStatsFile = 2, -- integer; 0 none, 1 combined, 2 per rendered file (pre-mix convention)
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
local Render = loadGlobal("jg_EXPO_Render.lua")
if not (H and Messages and Render) then
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

local function findStemConflicts(directory, prefix, cue, stemTokens)
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
			and stemTokens[normalizedPath(parsed.stem)]
		then
			table.insert(matches, directory .. "/" .. fileName)
		end
		index = index + 1
	end
	return matches
end

local function buildRenderTable(ultraschallApi, renderString, outputFolder, region, channels, pattern)
	local overrides = {}
	for key, value in pairs(PREMIX_RENDER_TABLE) do
		overrides[key] = value
	end
	overrides.Startposition = region.alignedStart
	overrides.Endposition = region.alignedEnd
	overrides.RenderFile = outputFolder:gsub("[/\\]+$", "") .. "/"
	overrides.RenderPattern = pattern
	overrides.Channels = channels
	overrides.RenderString = renderString
	return Render.createRenderTable(ultraschallApi, overrides)
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

local function runRender(details, regions, selectedRegions, nameOverrides, ultraschallApi, renderString, busTracks)
	local outputFolder = H.getExpoRoot(details.projectPath) .. "/03_Cues/03-01_Exports"
	local stemTokens = {}
	for _, bus in ipairs(busTracks) do
		local key = normalizedPath(bus.stem)
		stemTokens[key] = true
	end

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
		for _, existing in ipairs(findStemConflicts(outputFolder, details.prefix, cue, stemTokens)) do
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
			"Pre-mix STEM files already exist for this cue/version. EXPO will not overwrite or increment versioned files.\n\n"
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

	local state = snapshotTrackState(busTracks)
	local restoreOk, restoreError
	r.atexit(function()
		restoreTrackState(state)
	end)
	local rendered, failed, unexpected = {}, {}, {}
	local ok, err = xpcall(function()
		local prepared, prepareError = prepareTracksForRender(state)
		if not prepared then
			error(prepareError)
		end
		for _, plan in ipairs(plans) do
			local renderTable, buildError =
				buildRenderTable(ultraschallApi, renderString, outputFolder, plan.region, channels, plan.pattern)
			if not renderTable then
				error(plan.pattern .. "\n  " .. tostring(buildError))
			end
			if renderTable.Source ~= 3 then
				error(
					"Expected selected-track stem source (Source=3), received Source=" .. tostring(renderTable.Source)
				)
			end
			local result = Render.renderProjectWithTable(ultraschallApi, renderTable)
			if result.count < 0 then
				error(plan.pattern .. "\n  " .. tostring(result.detail))
			end
			local matchedStemFiles = 0
			for _, file in ipairs(result.files or {}) do
				local path = tostring(file)
				local fileName = path:gsub("\\", "/"):match("([^/]+)$") or path
				if fileName:lower():match("%.wav$") then
					table.insert(rendered, path)
					if plan.expected[normalizedPath(fileName)] then
						matchedStemFiles = matchedStemFiles + 1
					else
						table.insert(unexpected, path)
					end
				end
			end
			if result.count > 0 and matchedStemFiles == 0 then
				error(
					"Ultraschall reported a render, but returned no file matching the expected selected-track stem pattern:\n"
					.. plan.pattern
						.. (
							result.files
								and #result.files > 0
								and ("\n\nReturned paths:\n" .. table.concat(result.files, "\n"))
							or ""
						)
				)
			end
		end
	end, debug.traceback)
	restoreOk, restoreError = restoreTrackState(state)
	if not ok then
		table.insert(failed, tostring(err))
	end
	if not restoreOk then
		table.insert(failed, "Could not restore temporary bus track names/selection:\n" .. tostring(restoreError))
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
	if #failed > 0 then
		table.insert(summary, "Errors:\n" .. table.concat(failed, "\n\n"))
	end
	stop(table.concat(summary, "\n\n"))
end

local function main()
	local ultraschallApi, apiError = Render.loadUltraschall()
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
	local _, projectPath = r.EnumProjects(-1)
	local details = { prefix = parsed.prefix, cues = parsed.cues, projectPath = projectPath }
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
		runRender(details, regions, selectedRegions, renameOverrides, ultraschallApi, renderString, busTracks)
	end
	if #details.cues > 1 then
		showCueChecklist(matching.matched, matching.missing, afterSelection)
	else
		afterSelection(matching.matched)
	end
end

main()

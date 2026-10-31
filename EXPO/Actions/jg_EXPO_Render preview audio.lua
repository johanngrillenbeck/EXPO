-- @description EXPO Render preview audio
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Render preview audio
--   Validates Cue regions, aligns them to frames and renders selected previews via Ultraschall.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @noindex

local r = reaper
local TITLE = "EXPO - Render preview audio"
local MB_OK = 0
local MB_OKCANCEL = 1
local MB_RESULT_OK = 1

-- Ultraschall 5.3 render-string arguments. The bitrate index is 16 = 320 kbps;
-- encoder quality 2 = Normal. Optional flags default to false.
local PREVIEW_RENDER_STRING = {
	bitrate = 16,
	quality = 2,
	noJointStereo = false,
	writeReplayGain = false,
}

-- Ultraschall 5.3 RenderTable reference and preview-specific active overrides.
-- Commented entries document API defaults only; CreateNewRenderTable supplies them.
-- ReaScript action-specific values (format/source/bounds/paths) are not Global defaults.
local PREVIEW_RENDER_TABLE = {
	AddToProj = false, -- boolean; do not add rendered items to new tracks (factory default false)
	-- Brickwall_Limiter_Enabled = false, -- boolean; limiter enabled (default false)
	-- Brickwall_Limiter_Method = 1, -- integer; 1 peak, 2 true peak (default 1)
	-- Brickwall_Limiter_Target = 1, -- number; limiter target in dB (default 1)
	Source = 0, -- integer; 0 master mix; 1 mix+stems; 3 selected-track stems; 8 region matrix; 32 selected items; 64 items via master; 128 selected tracks via master; 136 region matrix via master; 4096 razor areas; 4224 razor areas via master
	Bounds = 0, -- integer; 0 custom range; 1 project; 2 time selection; 3 project regions; 4 selected items (Source=32); 5 selected regions; 6 razor areas; 7 all markers; 8 selected markers
	-- Startposition = 0, -- number; custom range start in seconds (default 0; set dynamically per cue)
	-- Endposition = 0, -- number; custom range end in seconds (default 0; set dynamically per cue)
	-- TailFlag = 18, -- integer bitmask: 1 custom, 2 project, 4 time selection, 8 all regions, 16 selected items, 32 selected regions, 64 razor areas (default 18)
	-- TailMS = 0, -- integer; tail length in milliseconds (CreateNewRenderTable factory value 0)
	-- RenderFile = "", -- string; output directory (factory default empty; set dynamically)
	-- RenderPattern = "", -- string; output filename/pattern (factory default empty; set dynamically)
	SampleRate = 48000, -- integer; output sample rate (preview convention; factory default 44100)
	-- Channels = 2, -- integer; 1 mono, 2 stereo, 3+ channel count (default 2)
	-- OfflineOnlineRendering = 0, -- integer; 0 full-speed offline, 1 1x offline, 2 online, 3 online idle, 4 offline idle (default 0)
	-- ProjectSampleRateFXProcessing = true, -- boolean; project sample rate for mixing/FX (default true)
	RenderResample = 10, -- integer; 0 64pt, 1 linear, 2 point, 3 192pt, 4 384pt, 5 linear+IIR, 6 linear+IIRx2, 7 16pt, 8 512pt, 9 768pt, 10 r8brain free (preview convention)
	-- OnlyMonoMedia = false, -- boolean; mono-only media to mono files (default false)
	-- MultiChannelFiles = false, -- boolean; multichannel tracks to multichannel files (default false)
	-- Dither = 0, -- integer bitmask: 1 master dither, 2 master noise shaping, 4 stem dither, 8 stem noise shaping (default 0)
	-- Normalize_Only_Files_Too_Loud = false, -- boolean; normalize only files exceeding target (default false)
	-- RenderString = "", -- string; Base64 render-format config (factory default empty; set from MP3 builder)
	SilentlyIncrementFilename = false, -- boolean; silently increment on conflict (factory default true; EXPO versioning forbids increments)
	CloseAfterRender = true, -- boolean; close render dialog when done (factory default true)
	-- SaveCopyOfProject = false, -- boolean; save RPP copy alongside render (default false)
	-- RenderQueueDelay = false, -- boolean; delay queued renders (default false)
	-- RenderQueueDelaySeconds = 0, -- integer; queued render delay seconds (default 0)
	-- EmbedStretchMarkers = false, -- boolean; embed stretch markers/transient guides (default false)
	-- RenderString2 = "", -- string; secondary-format Base64 render config (default empty)
	-- EmbedTakeMarkers = false, -- boolean; embed take markers (default false)
	-- NoSilentRender = false, -- boolean; skip likely-silent outputs (default false)
	-- EmbedMetaData = false, -- boolean; embed metadata (default false)
	-- Enable2ndPassRender = false, -- boolean; enable second pass (default false)
	-- Normalize_Enabled = false, -- boolean; enable normalization (default false)
	-- Normalize_Method = 0, -- integer; 0 LUFS-I, 1 RMS-I, 2 peak, 3 true peak, 4 LUFS-M max, 5 LUFS-S max (default 0)
	-- Normalize_Stems_to_Master_Target = false, -- boolean; common master target for stems vs per-file (default false)
	-- Normalize_Target = -24, -- number; normalization target dB (factory default -24)
	-- FadeIn_Enabled = false, -- boolean; apply render fade-in (default false)
	-- FadeIn = 0, -- number; fade-in seconds (default 0)
	-- FadeIn_Shape = 0, -- integer; 0 linear, 1 inverted quadratic, 2 quadratic, 3 inverted quartic, 4 quartic, 5 cosine S, 6 quartic S (default 0)
	-- FadeOut_Enabled = false, -- boolean; apply render fade-out (default false)
	-- FadeOut = 0, -- number; fade-out seconds (default 0)
	-- FadeOut_Shape = 0, -- integer; 0 linear, 1 inverted quadratic, 2 quadratic, 3 inverted quartic, 4 quartic, 5 cosine S, 6 quartic S (factory default is false)
	-- OnlyChannelsSentToParent = false, -- boolean; render only channels sent to parent (default false)
	-- RenderStems_Prefader = false, -- boolean; render stems pre-fader (default false)
	-- Preserve_Start_Offset = false, -- boolean; preserve selected-media-item start offset (default false)
	-- Preserve_Metadata = false, -- boolean; preserve selected-media-item metadata (default false)
	-- RenderTable = true, -- boolean; marker identifying a valid render table (CreateNewRenderTable sets true)
	-- ReturnToDialog = false, -- boolean; return to render dialog after rendering (default false)
	-- SaveRenderStatsFile = 0, -- integer; 0 none, 1 combined, 2 per rendered file (default 0)
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
				"ReaImGui is required to select cues for a multicue preview render. Install or update ReaImGui, then run this action again."
			)
			return
		end
	end

	local ctx = imgui.ImGui_CreateContext("EXPO preview cue selection")
	local selected = {}
	for _, region in ipairs(candidates) do
		selected[region.cue.cueId] = true
	end
	local finished = false
	local picked
	local function close(result)
		if finished then
			return
		end
		finished = true
		picked = result
	end

	local function frame()
		if finished then
			done(picked)
			return
		end
		local visible, open = imgui.ImGui_Begin(ctx, TITLE .. " - Select cues", true)
		if visible then
			imgui.ImGui_Text(ctx, "Select the cue previews to render:")
			if #missing > 0 then
				imgui.ImGui_Text(
					ctx,
					"No matching EXPO region for: " .. H.cueList(missing) .. ". These cues will be skipped."
				)
			end
			for _, region in ipairs(candidates) do
				local cue = region.cue
				local tc = H.formatTimecode(region.alignedStart, false)
				local label = cue.cueId .. "_" .. cue.version .. "  |  " .. tc
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

local function createPreviewRenderString(ultraschallApi)
	if type(ultraschallApi.CreateRenderCFG_MP3CBR) ~= "function" then
		return nil, "Ultraschall API does not provide CreateRenderCFG_MP3CBR."
	end
	local ok, renderString = pcall(
		ultraschallApi.CreateRenderCFG_MP3CBR,
		PREVIEW_RENDER_STRING.bitrate,
		PREVIEW_RENDER_STRING.quality,
		PREVIEW_RENDER_STRING.noJointStereo,
		PREVIEW_RENDER_STRING.writeReplayGain
	)
	if not ok or type(renderString) ~= "string" or renderString == "" then
		return nil, "Could not create the configured MP3 CBR render string: " .. tostring(renderString)
	end
	return renderString
end

local function buildPreviewRenderTable(ultraschallApi, renderString, outputFolder, plan)
	local overrides = {}
	for key, value in pairs(PREVIEW_RENDER_TABLE) do
		overrides[key] = value
	end
	overrides.Startposition = plan.region.alignedStart
	overrides.Endposition = plan.region.alignedEnd
	overrides.RenderFile = outputFolder:gsub("[/\\]+$", "") .. "/"
	overrides.RenderPattern = plan.stem
	overrides.RenderString = renderString
	return Render.createRenderTable(ultraschallApi, overrides)
end

local function runRender(details, regions, selectedByCueId, nameOverrides, ultraschallApi, renderString)
	local outputFolder = H.getExpoRoot(details.projectPath) .. "/04_Previews"
	local outputPlans, conflicts = {}, {}
	local conflictSet = {}
	local function addConflict(path)
		local key = path:gsub("\\", "/")
		if r.GetOS():match("Win") then
			key = key:lower()
		end
		if not conflictSet[key] then
			conflictSet[key] = true
			table.insert(conflicts, path)
		end
	end
	local selectedRegions = {}
	for _, region in pairs(selectedByCueId) do
		table.insert(selectedRegions, region)
	end
	table.sort(selectedRegions, function(a, b)
		return a.startPos < b.startPos
	end)
	for _, region in ipairs(selectedRegions) do
		local cue = region.cue
		local filenameTC = H.formatTimecode(region.alignedStart, true)
		local stem = details.prefix .. "_" .. cue.cueId .. "_" .. cue.version .. "_preview_TC-" .. filenameTC
		local outputPath = outputFolder .. "/" .. stem .. ".mp3"
		local existing = H.findPreviewVersionConflicts(outputFolder, details.prefix, cue)
		if #existing > 0 then
			for _, path in ipairs(existing) do
				addConflict(path)
			end
		end
		if r.file_exists(outputPath) then
			addConflict(outputPath)
		end
		table.insert(outputPlans, { region = region, cue = cue, stem = stem, outputPath = outputPath })
	end
	if #conflicts > 0 then
		stop(
			"Preview Audio already exists for this cue. EXPO will not overwrite or increment versioned files.\n\n"
				.. table.concat(conflicts, "\n")
				.. "\n\nEither re-save this Cue Project with a new version index or manually delete the existing Preview Audio file from the 04_Previews folder."
		)
		return
	end

	local master = r.GetMasterTrack(0)
	local masterChannels = r.GetMediaTrackInfo_Value(master, "I_NCHAN")
	if masterChannels > 2 then
		local answer = r.ShowMessageBox(
			"The master track is configured for "
				.. tostring(masterChannels)
				.. " channels. Has a stereo fold-down already been applied?\n\nContinue only if the mix is ready to render as stereo.",
			TITLE,
			MB_OKCANCEL
		)
		if answer ~= MB_RESULT_OK then
			return
		end
	end

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
	if #edits > 0 then
		local summary = {
			"Apply the following confirmed region changes before rendering? This is one undoable operation and will remain even if a render is cancelled or fails.",
		}
		for _, region in ipairs(changedRegions) do
			local oldStart = region.startPos
			local oldEnd = region.endPos
			local changed = region.alignmentChanged
			local line = region.name ~= "" and region.name or "<unnamed>"
			if changed then
				line = line
					.. string.format(
						"\n  Frame alignment: %.6f–%.6f → %.6f–%.6f seconds",
						oldStart,
						oldEnd,
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
			return
		end
		local ok, err = H.applyRegionEdits(edits, "EXPO: Align and name preview regions")
		if not ok then
			stop("Could not apply the confirmed region edits.\n\n" .. tostring(err))
			return
		end
	end

	local rendered, failed = {}, {}
	for _, plan in ipairs(outputPlans) do
		local renderTable, buildError = buildPreviewRenderTable(ultraschallApi, renderString, outputFolder, plan)
		if not renderTable then
			table.insert(failed, plan.outputPath .. "\n  " .. tostring(buildError))
			break
		end
		local result = Render.renderProjectWithTable(ultraschallApi, renderTable)
		if result.ok then
			for _, file in ipairs(result.files) do
				table.insert(rendered, file)
			end
		else
			table.insert(failed, plan.outputPath .. "\n  " .. tostring(result.detail))
			break
		end
	end

	if #failed > 0 then
		stop(
			"Rendering stopped after an error. Any confirmed region edits and completed renders have been kept.\n\n"
				.. table.concat(failed, "\n\n")
				.. (#rendered > 0 and ("\n\nCompleted renders:\n" .. table.concat(rendered, "\n")) or "")
		)
	elseif #rendered > 0 then
		stop("Preview render complete:\n\n" .. table.concat(rendered, "\n"))
	else
		stop("No output was rendered.")
	end
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
	local renderString, renderStringError = createPreviewRenderString(ultraschallApi)
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
	local details = {
		prefix = parsed.prefix,
		cues = parsed.cues,
		projectPath = projectPath,
	}

	local regions = H.getRegionsOnRulerLane("EXPO", 0)
	if #regions == 0 then
		stop(
			"There are no regions on the EXPO Ruler Lane. Create a region with the required cue time bounds, then run this action again. EXPO will not guess region bounds."
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
			"Multiple EXPO regions map to the same cue and output filename. Resolve the duplicate regions before rendering.\n\n"
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
		local region = matching.unmatched[1]
		local expected = matching.missing[1]
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
		matching.unmatched = {}
		matching.missing = {}
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
		local selectedByCueId = {}
		for _, region in ipairs(selectedRegions) do
			selectedByCueId[region.cue.cueId] = region
		end
		runRender(details, regions, selectedByCueId, renameOverrides, ultraschallApi, renderString)
	end

	if #details.cues > 1 then
		showCueChecklist(matching.matched, matching.missing, afterSelection)
	else
		afterSelection(matching.matched)
	end
end

main()

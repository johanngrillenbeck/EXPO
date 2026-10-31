-- @description EXPO Render preview audio
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Render preview audio
--   Validates Cue regions, aligns them to frames and renders selected previews via REAPER.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @noindex

local r = reaper
local TITLE = "EXPO - Render preview audio"
local MB_OK = 0
local MB_OKCANCEL = 1
local MB_RESULT_OK = 1
local RENDER_RESAMPLE_MODE = 10 -- r8brain free, set through SWS projrenderresample

-- Ultraschall 5.3 render-string arguments. The bitrate index is 16 = 320 kbps;
-- encoder quality 2 = Normal. Optional flags default to false.
local PREVIEW_RENDER_STRING = {
	bitrate = 16,
	quality = 2,
	noJointStereo = false,
	writeReplayGain = false,
}

-- Preview render bounds, source, output settings, and format are applied through
-- REAPER's native project render settings below. Ultraschall is used only to
-- create the MP3 format configuration string.
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

local function normalizedFileName(fileName)
	local key = tostring(fileName or ""):gsub("\\", "/")
	if r.GetOS():match("Win") then
		key = key:lower()
	end
	return key
end

local function displayFileName(path)
	return tostring(path or ""):gsub("\\", "/"):match("([^/]+)$") or tostring(path or "")
end

local function configurePreviewRender(project, outputFolder, renderString, plan)
	local numbers = {
		RENDER_SETTINGS = 0, -- master mix; do not render selected-track stems
		RENDER_BOUNDSFLAG = 0, -- custom start/end bounds
		RENDER_CHANNELS = 2,
		RENDER_SRATE = 48000,
		RENDER_STARTPOS = plan.region.alignedStart,
		RENDER_ENDPOS = plan.region.alignedEnd,
		RENDER_TAILFLAG = 0,
		RENDER_TAILMS = 0,
		RENDER_ADDTOPROJ = 2, -- do not add to project; skip likely-silent output
		RENDER_DITHER = 0,
		RENDER_NORMALIZE = 0,
	}
	local strings = {
		RENDER_FILE = outputFolder:gsub("[/\\]+$", ""),
		RENDER_PATTERN = plan.stem,
		RENDER_FORMAT = renderString,
		RENDER_FORMAT2 = "",
	}
	return numbers, strings, Render.applyNativeRenderSettings(project, numbers, strings)
end

local function verifyPreviewRenderState(project, projectPath, numbers, strings)
	local activeProject, activePath = r.EnumProjects(-1)
	if activeProject ~= project then
		return false,
			"The active project changed before rendering. Expected Cue project:\n"
				.. tostring(projectPath)
				.. "\nActive project:\n"
				.. tostring(activePath)
	end
	for key, expected in pairs(numbers) do
		local actual = r.GetSetProjectInfo(project, key, 0, false)
		if type(actual) ~= "number" or math.abs(actual - expected) > 1e-7 then
			return false, key .. " is " .. tostring(actual) .. "; expected " .. tostring(expected) .. "."
		end
	end
	for key, expected in pairs(strings) do
		local _, actual = r.GetSetProjectInfo_String(project, key, "", false)
		if actual ~= expected then
			return false, key .. " was not retained: expected '" .. expected .. "', found '" .. tostring(actual) .. "'."
		end
	end
	return true
end

local function runRender(details, regions, selectedByCueId, nameOverrides, renderString)
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
			table.insert(conflicts, displayFileName(path))
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
		table.insert(outputPlans, {
			region = region,
			cue = cue,
			stem = stem,
			fileName = stem .. ".mp3",
			outputPath = outputPath,
		})
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

	local renderSettingsState, settingsError = Render.snapshotNativeRenderSettings(details.projectHandle)
	if not renderSettingsState then
		stop(
			"Could not snapshot the current REAPER render settings. No render was started.\n\n"
				.. tostring(settingsError)
		)
		return
	end
	r.atexit(function()
		Render.restoreNativeRenderSettings(renderSettingsState)
	end)

	local rendered, failed, unexpected = {}, {}, {}
	local ok, err = xpcall(function()
		for _, plan in ipairs(outputPlans) do
			local numbers, strings, configured, configureError =
				configurePreviewRender(details.projectHandle, outputFolder, renderString, plan)
			if not configured then
				error(plan.fileName .. "\n  " .. tostring(configureError))
			end
			local verified, verifyError =
				verifyPreviewRenderState(details.projectHandle, details.projectPath, numbers, strings)
			if not verified then
				error("Not rendering because the pre-render state is unexpected.\n\n" .. tostring(verifyError))
			end

			local resampleOk, resampleError = Render.setRenderResampleMode(RENDER_RESAMPLE_MODE)
			if not resampleOk then
				error(plan.fileName .. "\n  " .. tostring(resampleError))
			end

			local filesBefore = Render.snapshotDirectoryFiles(outputFolder)
			local renderOk, renderError = pcall(r.Main_OnCommand, Render.NATIVE_RENDER_ACTION_ID, 0)
			if not renderOk then
				error("REAPER's native render action failed: " .. tostring(renderError))
			end

			local newMp3Files = Render.collectNewFiles(outputFolder, filesBefore, "mp3")
			local expectedKey = normalizedFileName(plan.fileName)
			local expectedCreated = false
			for _, path in ipairs(newMp3Files) do
				local fileName = path:gsub("\\", "/"):match("([^/]+)$") or path
				if normalizedFileName(fileName) == expectedKey then
					expectedCreated = true
					table.insert(rendered, fileName)
				else
					table.insert(unexpected, fileName)
				end
			end
			if not expectedCreated then
				error(
					"The exact expected preview was not created (the render may have been cancelled or produced no audible output):\n"
						.. plan.fileName
				)
			end
			if #unexpected > 0 then
				error("REAPER created unexpected or incremented MP3 files:\n" .. table.concat(unexpected, "\n"))
			end
		end
	end, debug.traceback)
	local settingsRestoreOk, settingsRestoreError = Render.restoreNativeRenderSettings(renderSettingsState)
	if not ok then
		table.insert(failed, tostring(err))
	end
	if not settingsRestoreOk then
		table.insert(
			failed,
			"Could not restore the original REAPER render settings:\n" .. tostring(settingsRestoreError)
		)
	end

	if #failed > 0 then
		stop(
			"Rendering stopped after an error. Any confirmed region edits and completed renders have been kept.\n\n"
				.. table.concat(failed, "\n\n")
				.. (#rendered > 0 and ("\n\nCompleted renders:\n" .. table.concat(rendered, "\n")) or "")
				.. (#unexpected > 0 and ("\n\nUnexpected files:\n" .. table.concat(unexpected, "\n")) or "")
		)
	elseif #rendered > 0 then
		stop("Preview render complete:\n\n" .. table.concat(rendered, "\n"))
	else
		stop("No output was rendered.")
	end
end

local function main()
	local ultraschallApi, apiError = Render.loadUltraschall({ "CreateRenderCFG_MP3CBR" })
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
	local projectHandle, projectPath = r.EnumProjects(-1)
	local details = {
		prefix = parsed.prefix,
		cues = parsed.cues,
		projectPath = projectPath,
		projectHandle = projectHandle,
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
		runRender(details, regions, selectedByCueId, renameOverrides, renderString)
	end

	if #details.cues > 1 then
		showCueChecklist(matching.matched, matching.missing, afterSelection)
	else
		afterSelection(matching.matched)
	end
end

main()

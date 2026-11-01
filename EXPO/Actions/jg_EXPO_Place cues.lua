-- @description EXPO Place cues
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Place cues
--   Imports rendered cue previews and pre-mix stems into version-numbered Assembly lanes.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @changelog
--   Initial implementation: inventory and place rendered audio.
-- @noindex

local r = reaper
local TITLE = "EXPO - Place cues"
local MB_OK, MB_OKCANCEL, MB_RESULT_OK = 0, 1, 1
local MAX_LANES_WITHOUT_CONFIRMATION = 30
local MAX_SUPPORTED_LANES = 1000
local VIDEO_LANE = "EXPO (Video Preview)"
local FINAL_LANE = "EXPO (Final Audio)"

-------------------------------------------------------------------------------
-- Module loading
-------------------------------------------------------------------------------

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
if not H then
	return
end

-------------------------------------------------------------------------------
-- Disk and project inventory
-------------------------------------------------------------------------------

local function displayName(path)
	return tostring(path or ""):gsub("\\", "/"):match("([^/]+)$") or tostring(path or "")
end

local function enumerateAudio(directory, parser, mediaKind, prefix, files, warnings)
	local index = 0
	while true do
		local fileName = r.EnumerateFiles(directory, index)
		if not fileName then
			break
		end
		index = index + 1
		local extensionMatches = mediaKind == "preview" and fileName:lower():match("%.mp3$")
			or mediaKind == "stem" and fileName:lower():match("%.wav$")
		if extensionMatches then
			local parsed = parser(fileName)
			if parsed and H.normalizePath(parsed.prefix) == H.normalizePath(prefix) then
				local lane = #parsed.normalizedVersion <= 4 and tonumber(parsed.normalizedVersion) or nil
				if not lane or lane < 1 then
					table.insert(warnings, "Invalid version index in " .. fileName)
				else
					parsed.versionIndex = lane
					parsed.mediaKind = mediaKind
					parsed.path = directory .. "/" .. fileName
					table.insert(files, parsed)
				end
			elseif not parsed and fileName:lower():find("_v%d+_") then
				table.insert(warnings, "Could not parse supported render filename: " .. fileName)
			end
		end
	end
end

local function inspectProjectSources(project)
	local sources, sourceItems = {}, {}
	for trackIndex = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, trackIndex)
		for itemIndex = 0, r.CountTrackMediaItems(track) - 1 do
			local item = r.GetTrackMediaItem(track, itemIndex)
			local take = r.GetActiveTake(item)
			local source = take and r.GetMediaItemTake_Source(take)
			if source then
				local sourcePath = r.GetMediaSourceFileName(source)
				if sourcePath and sourcePath ~= "" then
					local key = H.normalizePath(sourcePath)
					sources[key] = (sources[key] or 0) + 1
					local position = r.GetMediaItemInfo_Value(item, "D_POSITION")
					local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
					sourceItems[key] = sourceItems[key] or {}
					table.insert(sourceItems[key], { startPos = position, endPos = position + length })
				end
			end
		end
	end
	return sources, sourceItems
end

local function addSpan(spans, cueId, versionKey, startPosition, endPosition)
	local cueSpans = spans[cueId]
	if not cueSpans then
		cueSpans = {}
		spans[cueId] = cueSpans
	end
	local span = cueSpans[versionKey]
	if not span then
		cueSpans[versionKey] = { startPos = startPosition, endPos = endPosition }
	else
		span.startPos = math.min(span.startPos, startPosition)
		span.endPos = math.max(span.endPos, endPosition)
	end
end

local function getTrackPathMap(project)
	local paths, stack = {}, {}
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		local _, name = r.GetTrackName(track)
		local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
		local path = #stack > 0 and (table.concat(stack, "/") .. "/" .. name) or name
		if not paths[path] then
			paths[path] = track
		end
		if depth > 0 then
			table.insert(stack, name)
		elseif depth < 0 then
			for _ = 1, -depth do
				table.remove(stack)
			end
		end
	end
	return paths
end

local function insertStemTrack(project, stemName)
	local cuesTrack
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		local _, name = r.GetTrackName(track)
		if name == "CUES" then
			cuesTrack = track
			break
		end
	end
	if not cuesTrack or r.GetMediaTrackInfo_Value(cuesTrack, "I_FOLDERDEPTH") <= 0 then
		return nil, "Could not find a valid CUES folder track."
	end

	local startIndex = math.floor(r.GetMediaTrackInfo_Value(cuesTrack, "IP_TRACKNUMBER") - 1)
	local depth = 1
	local insertionIndex
	for index = startIndex + 1, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		local trackDepth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
		if depth + trackDepth <= 0 then
			insertionIndex = index
			break
		end
		depth = depth + trackDepth
	end
	if not insertionIndex then
		return nil, "Could not determine the end of the CUES folder."
	end

	r.InsertTrackAtIndex(insertionIndex, false)
	local track = r.GetTrack(project, insertionIndex)
	r.GetSetMediaTrackInfo_String(track, "P_NAME", stemName, true)
	r.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
	return track
end

local function ensureTrack(project, trackPaths, stemName)
	local path = "CUES/" .. stemName
	if trackPaths[path] then
		return trackPaths[path]
	end
	local track, err = insertStemTrack(project, stemName)
	if not track then
		return nil, err
	end
	return track
end

-------------------------------------------------------------------------------
-- Fixed-lane assignment and region updates
-------------------------------------------------------------------------------

local function ensureVersionLane(track, versionIndex)
	local currentMode = r.GetMediaTrackInfo_Value(track, "I_FREEMODE")
	if currentMode ~= 2 then
		r.SetMediaTrackInfo_Value(track, "I_FREEMODE", 2)
	end
	local laneCount = r.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES") or 0
	if laneCount < versionIndex then
		r.SetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES", versionIndex)
	end
	r.UpdateTimeline()
end

local function findCueRegion(regions, cueId)
	local found
	for _, region in ipairs(regions) do
		local parsed = H.parseCueRegionName(region.name)
		local regionCueId = parsed and parsed.cueId or region.name:match("^%s*(%d+m%d+)%s*$")
		if regionCueId == cueId then
			if found then
				return nil, "Multiple regions match cue " .. cueId .. "."
			end
			found = region
		end
	end
	return found
end

local function setRegionLane(project, region, laneName, position, endPosition, name)
	if region then
		local marker = region.guid ~= "" and r.GetRegionOrMarker(project, -1, region.guid) or region.marker
		if not marker then
			return false, "Could not resolve region " .. tostring(region.name) .. "."
		end
		if position ~= nil then
			r.SetRegionOrMarkerInfo_Value(project, marker, "D_STARTPOS", position)
		end
		if endPosition ~= nil then
			r.SetRegionOrMarkerInfo_Value(project, marker, "D_ENDPOS", endPosition)
		end
		if name then
			r.GetSetRegionOrMarkerInfo_String(project, marker, "P_NAME", name, true)
		end
		return true
	end

	local lane = H.getRulerLane(laneName)
	if not lane then
		return false, "Required ruler lane is missing: " .. laneName
	end
	local index = r.AddProjectMarker2(project, true, position, endPosition, name, -1, 0)
	if index < 0 then
		return false, "Could not create region " .. name .. "."
	end
	local marker = r.GetRegionOrMarker(project, index, "")
	if not marker or not r.SetRegionOrMarkerInfo_Value(project, marker, "I_LANENUMBER", lane.index) then
		return false, "Could not assign region " .. name .. " to " .. laneName .. "."
	end
	return true
end

local function regionName(cueId, version, startPosition, endPosition)
	return cueId .. "_" .. version .. " " .. H.formatTimecode(startPosition) .. " - " .. H.formatTimecode(endPosition)
end

-------------------------------------------------------------------------------
-- Main action
-------------------------------------------------------------------------------

local function main()
	local project, projectPath = r.EnumProjects(-1)
	local valid, report = H.validateAssembly()
	if not valid then
		r.ShowMessageBox(
			"The current project must be a valid, saved EXPO Assembly before placing cues.\n\n"
				.. (report.validFileName == false and "Check the Assembly filename and project prefix.\n" or "")
				.. (report.validExpoTree == false and "Check the EXPO folder structure.\n" or "")
				.. (
					#report.missingTracks > 0
						and "Missing required tracks: " .. table.concat(report.missingTracks, ", ")
					or ""
				),
			TITLE,
			MB_OK
		)
		return
	end
	if not projectPath or projectPath == "" or not report.prefix then
		r.ShowMessageBox("Save a correctly named Assembly project before placing cues.", TITLE, MB_OK)
		return
	end

	local root = H.getExpoRoot(projectPath)
	if not root then
		r.ShowMessageBox("Could not determine the EXPO project root from the Assembly path.", TITLE, MB_OK)
		return
	end
	local files, warnings = {}, {}
	enumerateAudio(root .. "/03_Cues/03-01_Exports", H.parsePremixFilename, "stem", report.prefix, files, warnings)
	enumerateAudio(root .. "/04_Previews", H.parsePreviewFilename, "preview", report.prefix, files, warnings)
	if #files == 0 then
		local suffix = #warnings > 0 and ("\n\n" .. table.concat(warnings, "\n")) or ""
		r.ShowMessageBox("No matching audio preview or pre-mix stem renders were found." .. suffix, TITLE, MB_OK)
		return
	end

	local seenCandidates, uniqueFiles, maxVersionByCue = {}, {}, {}
	for _, file in ipairs(files) do
		local duplicateKey = table.concat({ file.cueId, file.normalizedVersion, file.mediaKind, file.stem or "" }, "|")
		duplicateKey = H.normalizePath(duplicateKey)
		if seenCandidates[duplicateKey] then
			table.insert(warnings, "Ambiguous duplicate render; skipped: " .. displayName(file.path))
		else
			seenCandidates[duplicateKey] = true
			table.insert(uniqueFiles, file)
			local previous = maxVersionByCue[file.cueId]
			if not previous or H.compareVersions(file.version, previous.version) > 0 then
				maxVersionByCue[file.cueId] = file
			end
		end
	end

	local highVersions = {}
	for _, file in ipairs(uniqueFiles) do
		if file.versionIndex > MAX_LANES_WITHOUT_CONFIRMATION then
			highVersions[file.version] = true
		end
	end
	if next(highVersions) then
		local versions = {}
		for version in pairs(highVersions) do
			table.insert(versions, version)
		end
		table.sort(versions, function(a, b)
			return H.compareVersions(a, b) < 0
		end)
		local answer = r.ShowMessageBox(
			"Version Index indicates we would need more than 30 lanes. Are you sure to continue?\n\n"
				.. "Versions: "
				.. table.concat(versions, ", "),
			TITLE,
			MB_OKCANCEL
		)
		if answer ~= MB_RESULT_OK then
			return
		end
	end
	for _, file in ipairs(uniqueFiles) do
		if file.versionIndex > MAX_SUPPORTED_LANES then
			r.ShowMessageBox(
				"This version would require more than "
					.. MAX_SUPPORTED_LANES
					.. " fixed lanes, which is not supported safely by this action. No project changes were made.",
				TITLE,
				MB_OK
			)
			return
		end
	end

	local sources, sourceItems = inspectProjectSources(project)
	local toImport = {}
	local versionSpans = {}
	for _, file in ipairs(uniqueFiles) do
		local sourceKey = H.normalizePath(file.path)
		local existingItems = sourceItems[sourceKey]
		if existingItems then
			if sources[sourceKey] > 1 then
				table.insert(
					warnings,
					"Source already occurs multiple times in the Assembly project: " .. displayName(file.path)
				)
			end
			for _, itemSpan in ipairs(existingItems) do
				addSpan(versionSpans, file.cueId, file.normalizedVersion, itemSpan.startPos, itemSpan.endPos)
			end
		else
			table.insert(toImport, file)
		end
	end
	local trackPaths = getTrackPathMap(project)
	local neededStems = {}
	for _, file in ipairs(toImport) do
		if file.mediaKind == "stem" then
			neededStems[H.normalizePath(file.stem)] = file.stem
		end
	end
	local originalCursor = r.GetCursorPosition()
	local originalTimeStart, originalTimeEnd = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
	local originalTracks = {}
	for i = 0, r.CountSelectedTracks(project) - 1 do
		originalTracks[r.GetSelectedTrack(project, i)] = true
	end
	local originalItems = {}
	local originalSelectedItems = {}
	for i = 0, r.CountMediaItems(project) - 1 do
		local item = r.GetMediaItem(project, i)
		local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
		originalItems[guid] = true
		if r.IsMediaItemSelected(item) then
			originalSelectedItems[guid] = true
		end
	end

	local failures = {}
	local importCount = 0
	r.Undo_BeginBlock2(project)
	r.PreventUIRefresh(1)
	local ok, err = xpcall(function()
		for _, stemName in pairs(neededStems) do
			local track, trackError = ensureTrack(project, trackPaths, stemName)
			if not track then
				error(trackError)
			end
			trackPaths = getTrackPathMap(project)
		end

		for _, file in ipairs(toImport) do
			local target = file.mediaKind == "preview" and trackPaths["CUES/Preview"]
				or trackPaths["CUES/" .. file.stem]
			if not target then
				table.insert(failures, "No target track for " .. displayName(file.path))
			else
				ensureVersionLane(target, file.versionIndex)
				while r.CountSelectedTracks(project) > 0 do
					r.SetTrackSelected(r.GetSelectedTrack(project, 0), false)
				end
				r.SetTrackSelected(target, true)
				r.SetEditCurPos(file.startPosition, false, false)
				local insertResult = r.InsertMedia(file.path, 0)
				local inserted
				if insertResult ~= 0 then
					for itemIndex = 0, r.CountTrackMediaItems(target) - 1 do
						local item = r.GetTrackMediaItem(target, itemIndex)
						local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
						if not originalItems[guid] then
							inserted = item
							originalItems[guid] = true
							break
						end
					end
				end
				if not inserted then
					table.insert(failures, "REAPER could not import " .. displayName(file.path))
				else
					importCount = importCount + 1
					r.SetMediaItemInfo_Value(inserted, "D_POSITION", file.startPosition)
					r.SetMediaItemInfo_Value(inserted, "I_FIXEDLANE", file.versionIndex - 1)
					local sourceTake = r.GetActiveTake(inserted)
					local mediaSource = sourceTake and r.GetMediaItemTake_Source(sourceTake)
					local length = mediaSource and r.GetMediaSourceLength(mediaSource)
					if length and length > 0 then
						r.SetMediaItemInfo_Value(inserted, "D_LENGTH", length)
					end
					addSpan(
						versionSpans,
						file.cueId,
						file.normalizedVersion,
						file.startPosition,
						file.startPosition + (length or 0)
					)
				end
			end
		end

		for cueId, latest in pairs(maxVersionByCue) do
			local cueSpans = versionSpans[cueId]
			local span = cueSpans and cueSpans[latest.normalizedVersion]
			if span and span.endPos > span.startPos then
				local finalRegions = H.getRegionsOnRulerLane(FINAL_LANE, project)
				local videoRegions = H.getRegionsOnRulerLane(VIDEO_LANE, project)
				local finalRegion, finalError = findCueRegion(finalRegions, cueId)
				local videoRegion, videoError = findCueRegion(videoRegions, cueId)
				if finalError or videoError then
					table.insert(failures, finalError or videoError)
				else
					local finalName = regionName(cueId, latest.version, span.startPos, span.endPos)
					local finalOk, finalSetError =
						setRegionLane(project, finalRegion, FINAL_LANE, span.startPos, span.endPos, finalName)
					if not finalOk then
						table.insert(failures, finalSetError)
					end
					local videoName = cueId .. "_" .. latest.version
					if videoRegion then
						local videoOk, videoSetError =
							setRegionLane(project, videoRegion, VIDEO_LANE, nil, nil, videoName)
						if not videoOk then
							table.insert(failures, videoSetError)
						end
					else
						local videoOk, videoSetError = setRegionLane(
							project,
							nil,
							VIDEO_LANE,
							math.max(0, span.startPos - 10),
							span.endPos + 10,
							videoName
						)
						if not videoOk then
							table.insert(failures, videoSetError)
						end
					end
				end
			end
		end
	end, debug.traceback)
	r.PreventUIRefresh(-1)
	while r.CountSelectedTracks(project) > 0 do
		r.SetTrackSelected(r.GetSelectedTrack(project, 0), false)
	end
	for track in pairs(originalTracks) do
		r.SetTrackSelected(track, true)
	end
	for i = 0, r.CountMediaItems(project) - 1 do
		local item = r.GetMediaItem(project, i)
		local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
		r.SetMediaItemSelected(item, originalSelectedItems[guid] == true)
	end
	r.SetEditCurPos(originalCursor, false, false)
	r.GetSet_LoopTimeRange(true, false, originalTimeStart, originalTimeEnd, false)
	r.UpdateTimeline()
	r.UpdateArrange()
	r.Undo_EndBlock2(project, "EXPO: Place cues", -1)

	if not ok then
		table.insert(failures, tostring(err))
	end
	local result = "Placed "
		.. tostring(importCount)
		.. " render file(s).\n\n"
		.. "Source lanes were preserved. Native comp-lane automation is not yet applied by this initial implementation."
	if #failures > 0 then
		result = result .. "\n\nIssues:\n- " .. table.concat(failures, "\n- ")
	end
	if #warnings > 0 then
		result = result .. "\n\nSkipped or malformed files:\n- " .. table.concat(warnings, "\n- ")
	end
	r.ShowMessageBox(result, TITLE, MB_OK)
end

main()

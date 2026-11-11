-- @description EXPO Place cues
-- @author Johann Grillenbeck
-- @about
--   # EXPO: Place cues
--   Imports rendered cue previews, pre-mix stems, and full mixes into version-numbered Assembly lanes.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @changelog
--   Place media directly on resolved tracks and assign new regions to their EXPO ruler lanes.
--   Keep Preview and Full Mix as the first two CUES child tracks on every placement run.
--   Match all CUES child lane counts to the highest discovered render version.
--   Group all CUES child tracks in Group 1 and enable media/razor edit lead and follow.
--   Create comp areas from all available items of each cue's latest version.
--   Reconcile existing items by named version lanes and label takes with source filenames.
-- @noindex

local r = reaper
local TITLE = "EXPO - Place cues"
local MB_OK, MB_OKCANCEL, MB_RESULT_OK = 0, 1, 1
local MAX_LANES_WITHOUT_CONFIRMATION = 30
local MAX_SUPPORTED_LANES = 1000
local ADD_COMP_AREAS_COMMAND_ID = 42652
local TURN_OFF_COMPING_COMMAND_ID = 42692
local OPEN_FIXED_ITEM_LANES_COMMAND_ID = 42431
local TOGGLE_FIXED_ITEM_LANES_COMMAND_ID = 42430
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

local function parseFullMixFilename(fileName)
	local sourceName = tostring(fileName or "")
	local prefix, cueId, version, hh, mm, ss, ff = sourceName:match(
		"^([^_]+)_([^_]+)_[vV](%d+)_[fF][uU][lL][lL]%-[mM][iI][xX]_[tT][cC]%-(%d+)%.(%d+)%.(%d+)%.(%d+)%.[wW][aA][vV]$"
	)
	if not prefix or not cueId:match("^%d+[mM]%d+$") then
		return nil
	end
	local timecode = table.concat({ hh, mm, ss, ff }, ".")
	return {
		prefix = prefix,
		cueId = cueId,
		version = "v" .. version,
		normalizedVersion = H.normalizeVersion(version),
		timecode = timecode,
		startPosition = r.parse_timestr_pos(timecode:gsub("%.", ":"), 5),
		fileName = sourceName,
	}
end

local function enumerateFullMixes(directory, prefix, files, warnings)
	local index = 0
	while true do
		local fileName = r.EnumerateFiles(directory, index)
		if not fileName then
			break
		end
		index = index + 1
		if fileName:lower():match("%.wav$") and fileName:lower():find("_full%-mix_tc%-") then
			local parsed = parseFullMixFilename(fileName)
			if parsed and H.normalizePath(parsed.prefix) == H.normalizePath(prefix) then
				local lane = #parsed.normalizedVersion <= 4 and tonumber(parsed.normalizedVersion) or nil
				if not lane or lane < 1 then
					table.insert(warnings, "Invalid version index in " .. fileName)
				else
					parsed.versionIndex = lane
					parsed.mediaKind = "fullmix"
					parsed.path = directory .. "/" .. fileName
					table.insert(files, parsed)
				end
			elseif not parsed then
				table.insert(warnings, "Could not parse supported full mix filename: " .. fileName)
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
					table.insert(sourceItems[key], {
						item = item,
						track = track,
						startPos = position,
						endPos = position + length,
					})
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
	local paths = {}
	local function getPath(track)
		local _, name = r.GetTrackName(track)
		local parent = r.GetParentTrack(track)
		if parent then
			return getPath(parent) .. "/" .. name
		end
		return name
	end

	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		local path = H.normalizePath(getPath(track))
		if paths[path] == nil then
			paths[path] = track
		else
			-- A duplicate full path is ambiguous; never silently route to its first track.
			paths[path] = false
		end
	end
	return paths
end

local function insertStemTrack(project, stemName)
	local cuesTrack
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		local _, name = r.GetTrackName(track)
		if name == "CUES" and not r.GetParentTrack(track) then
			if cuesTrack then
				return nil, "Multiple top-level CUES tracks exist. Rename or remove the duplicate before placing cues."
			end
			cuesTrack = track
		end
	end
	local folderDepth = cuesTrack and r.GetMediaTrackInfo_Value(cuesTrack, "I_FOLDERDEPTH") or 0
	if not cuesTrack or folderDepth <= 0 then
		return nil, "Could not find a valid CUES folder track."
	end

	local startIndex = math.floor(r.GetMediaTrackInfo_Value(cuesTrack, "IP_TRACKNUMBER") - 1)
	local depth = folderDepth
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
	local path = H.normalizePath("CUES/" .. stemName)
	if trackPaths[path] == false then
		return nil, "Multiple tracks have the name path " .. path .. ". Rename the duplicates before placing cues."
	end
	if trackPaths[path] then
		return trackPaths[path]
	end
	local track, err = insertStemTrack(project, stemName)
	if not track then
		return nil, err
	end
	return track
end

---Keeps the required cue tracks at the start of the CUES folder in a stable order.
---@param project ReaProject
---@return boolean success, string|nil error
local function ensureCueTrackOrder(project)
	local cuesTrack
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		local _, name = r.GetTrackName(track)
		if name == "CUES" and not r.GetParentTrack(track) then
			if cuesTrack then
				return false, "Multiple top-level CUES tracks exist; could not enforce Preview and Full Mix order."
			end
			cuesTrack = track
		end
	end
	if not cuesTrack or r.GetMediaTrackInfo_Value(cuesTrack, "I_FOLDERDEPTH") <= 0 then
		return false, "Could not find a valid CUES folder while enforcing Preview and Full Mix order."
	end

	local paths = getTrackPathMap(project)
	local preview = paths[H.normalizePath("CUES/Preview")]
	local fullMix = paths[H.normalizePath("CUES/Full Mix")]
	if preview == false or fullMix == false then
		return false, "Duplicate Preview or Full Mix tracks make the required CUES track order ambiguous."
	end
	if not preview or not fullMix then
		return false, "Could not find both Preview and Full Mix tracks inside the CUES folder."
	end
	if r.GetParentTrack(preview) ~= cuesTrack or r.GetParentTrack(fullMix) ~= cuesTrack then
		return false, "Preview and Full Mix must be direct child tracks of the CUES folder."
	end

	local function findTrackIndex(target)
		for index = 0, r.CountTracks(project) - 1 do
			if r.GetTrack(project, index) == target then
				return index
			end
		end
		return nil
	end

	local function moveToIndex(track, targetIndex, trackName)
		if findTrackIndex(track) ~= targetIndex then
			r.SetOnlyTrackSelected(track)
			r.ReorderSelectedTracks(targetIndex, 0)
		end
		if findTrackIndex(track) ~= targetIndex then
			return false, "REAPER could not move " .. trackName .. " to its required CUES position."
		end
		return true
	end

	local cuesIndex = findTrackIndex(cuesTrack)
	local previewMoved, previewError = moveToIndex(preview, cuesIndex + 1, "Preview")
	if not previewMoved then
		return false, previewError
	end
	if r.GetParentTrack(preview) ~= cuesTrack then
		return false, "Moving Preview changed its folder; could not safely enforce CUES track order."
	end

	cuesIndex = findTrackIndex(cuesTrack)
	local fullMixMoved, fullMixError = moveToIndex(fullMix, cuesIndex + 2, "Full Mix")
	if not fullMixMoved then
		return false, fullMixError
	end
	if r.GetParentTrack(fullMix) ~= cuesTrack then
		return false, "Moving Full Mix changed its folder; could not safely enforce CUES track order."
	end
	return true
end

-------------------------------------------------------------------------------
-- Fixed-lane assignment and region updates
-------------------------------------------------------------------------------

local function getVersionLaneIndex(track, versionName)
	local laneCount = math.floor(r.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES") or 0)
	for laneIndex = 0, laneCount - 1 do
		local _, laneName = r.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. laneIndex, "", false)
		if laneName == versionName then
			return laneIndex
		end
	end
	return nil
end

local function ensureVersionLane(track, versionIndex)
	local versionName = tostring(versionIndex)
	local currentMode = r.GetMediaTrackInfo_Value(track, "I_FREEMODE")
	if currentMode ~= 2 then
		r.SetMediaTrackInfo_Value(track, "I_FREEMODE", 2)
		r.UpdateTimeline()
	end
	local laneIndex = getVersionLaneIndex(track, versionName)
	if laneIndex ~= nil then
		return laneIndex
	end

	local laneCount = math.floor(r.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES") or 0)
	r.SetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES", laneCount + 1)
	r.UpdateTimeline()
	laneCount = math.floor(r.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES") or 0)
	laneIndex = getVersionLaneIndex(track, versionName)
	if laneIndex ~= nil then
		return laneIndex
	end
	if laneCount <= 0 then
		return nil, "REAPER could not create fixed lane " .. versionName .. "."
	end

	-- New lanes are appended; name them with the version token rather than relying on position.
	laneIndex = laneCount - 1
	local named = r.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. laneIndex, versionName, true)
	r.UpdateTimeline()
	if not named or getVersionLaneIndex(track, versionName) == nil then
		return nil, "REAPER could not name the fixed lane " .. versionName .. "."
	end
	return getVersionLaneIndex(track, versionName)
end

---Sets all direct CUES child tracks to at least a common fixed-lane count.
---@param project ReaProject
---@param minimumLaneCount number
---@return boolean success, string|nil error
local function ensureSharedCueLaneCount(project, minimumLaneCount)
	local cuesTrack
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		local _, name = r.GetTrackName(track)
		if name == "CUES" and not r.GetParentTrack(track) then
			if cuesTrack then
				return false, "Multiple top-level CUES tracks exist; could not synchronize version lanes."
			end
			cuesTrack = track
		end
	end
	if not cuesTrack or r.GetMediaTrackInfo_Value(cuesTrack, "I_FOLDERDEPTH") <= 0 then
		return false, "Could not find a valid CUES folder while synchronizing version lanes."
	end

	local childTracks, sharedLaneCount = {}, minimumLaneCount
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		if r.GetParentTrack(track) == cuesTrack then
			table.insert(childTracks, track)
			local laneCount = math.floor(r.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES") or 0)
			for laneIndex = 0, laneCount - 1 do
				local _, laneName = r.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. laneIndex, "", false)
				local namedVersion = tonumber(laneName)
				if namedVersion and namedVersion >= 1 and namedVersion == math.floor(namedVersion) then
					sharedLaneCount = math.max(sharedLaneCount, namedVersion)
				end
			end
		end
	end
	for _, track in ipairs(childTracks) do
		for versionIndex = 1, sharedLaneCount do
			local _, err = ensureVersionLane(track, versionIndex)
			if err then
				return false, err
			end
		end
	end
	return true
end

---Assigns every direct CUES child to Group 1 with media/razor edit lead and follow enabled.
---@param project ReaProject
---@return boolean success, string|nil error
local function ensureCueTrackGroup(project)
	if type(r.GetSetTrackGroupMembership) ~= "function" or type(r.GetSetProjectInfo_String) ~= "function" then
		return false, "This REAPER version does not expose the track-group APIs required to configure CUES."
	end

	local cuesTrack
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		local _, name = r.GetTrackName(track)
		if name == "CUES" and not r.GetParentTrack(track) then
			if cuesTrack then
				return false, "Multiple top-level CUES tracks exist; could not configure track grouping."
			end
			cuesTrack = track
		end
	end
	if not cuesTrack or r.GetMediaTrackInfo_Value(cuesTrack, "I_FOLDERDEPTH") <= 0 then
		return false, "Could not find a valid CUES folder while configuring track grouping."
	end

	local groupNameOk = r.GetSetProjectInfo_String(project, "TRACK_GROUP_NAME:1", "CUES", true)
	if not groupNameOk then
		return false, "REAPER could not name track Group 1 as CUES."
	end

	local groupBit = 1 -- Group 1 is the low bit in each track-group membership mask.
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		if r.GetParentTrack(track) == cuesTrack then
			r.GetSetTrackGroupMembership(track, "MEDIA_EDIT_LEAD", groupBit, groupBit)
			r.GetSetTrackGroupMembership(track, "MEDIA_EDIT_FOLLOW", groupBit, groupBit)
		end
	end

	local _, storedGroupName = r.GetSetProjectInfo_String(project, "TRACK_GROUP_NAME:1", "", false)
	if storedGroupName ~= "CUES" then
		return false, "REAPER did not retain CUES as the name of track Group 1."
	end
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		if r.GetParentTrack(track) == cuesTrack then
			local lead = r.GetSetTrackGroupMembership(track, "MEDIA_EDIT_LEAD", 0, 0)
			local follow = r.GetSetTrackGroupMembership(track, "MEDIA_EDIT_FOLLOW", 0, 0)
			if lead % (groupBit * 2) < groupBit or follow % (groupBit * 2) < groupBit then
				return false, "REAPER could not enable Media/Razor Edit Lead and Follow for every CUES child track."
			end
		end
	end
	return true
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
	local marker = r.AddRegionOrMarker(project, true, position, endPosition, name, -1, 0)
	if not marker then
		return false, "Could not create region " .. name .. "."
	end
	if not r.SetRegionOrMarkerInfo_Value(project, marker, "I_LANENUMBER", lane.index) then
		return false, "Could not assign region " .. name .. " to " .. laneName .. "."
	end
	return true
end

---Sets an existing item's track, filename-derived position, version lane, and take name.
---@param item MediaItem
---@param track MediaTrack
---@param file table
---@param laneIndex number
---@return boolean success, number|nil length, string|nil error
local function configureRenderItem(item, track, file, laneIndex)
	if r.GetMediaItemTrack(item) ~= track then
		r.MoveMediaItemToTrack(item, track)
		if r.GetMediaItemTrack(item) ~= track then
			return false, nil, "REAPER could not move " .. displayName(file.path) .. " to its target track."
		end
	end

	local take = r.GetActiveTake(item)
	local source = take and r.GetMediaItemTake_Source(take)
	if not take or not source then
		return false, nil, "Could not resolve the active take for " .. displayName(file.path)
	end
	local length = r.GetMediaSourceLength(source)
	if not length or length <= 0 then
		return false, nil, "REAPER reported an invalid source length for " .. displayName(file.path)
	end

	local takeNameSet = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", displayName(file.path), true)
	if not takeNameSet then
		return false, nil, "REAPER could not name the take after " .. displayName(file.path)
	end
	r.SetMediaItemInfo_Value(item, "D_POSITION", file.startPosition)
	r.SetMediaItemInfo_Value(item, "D_LENGTH", length)
	r.SetMediaItemInfo_Value(item, "I_FIXEDLANE", laneIndex)
	if r.GetMediaItemInfo_Value(item, "I_FIXEDLANE") ~= laneIndex then
		return false,
			nil,
			"REAPER did not assign "
				.. displayName(file.path)
				.. " to version lane "
				.. tostring(file.versionIndex)
				.. "."
	end
	return true, length
end

---Creates a media item on an explicit target track and attaches the rendered file as its source.
---@param track MediaTrack
---@param file table
---@param laneIndex number
---@return MediaItem|nil item, number|nil length, string|nil error
local function createRenderItem(track, file, laneIndex)
	local source = r.PCM_Source_CreateFromFile(file.path)
	if not source then
		return nil, nil, "REAPER could not open " .. displayName(file.path)
	end

	local item = r.AddMediaItemToTrack(track)
	local take = item and r.AddTakeToMediaItem(item)
	if not item or not take then
		if item then
			r.DeleteTrackMediaItem(track, item)
		end
		r.PCM_Source_Destroy(source)
		return nil, nil, "REAPER could not create an item for " .. displayName(file.path)
	end

	if not r.SetMediaItemTake_Source(take, source) then
		r.PCM_Source_Destroy(source)
		r.DeleteTrackMediaItem(track, item)
		return nil, nil, "REAPER could not attach the source for " .. displayName(file.path)
	end

	local length = r.GetMediaSourceLength(source)
	if not length or length <= 0 then
		r.DeleteTrackMediaItem(track, item)
		return nil, nil, "REAPER reported an invalid source length for " .. displayName(file.path)
	end

	local takeNameSet = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", displayName(file.path), true)
	if not takeNameSet then
		r.DeleteTrackMediaItem(track, item)
		return nil, nil, "REAPER could not name the take after " .. displayName(file.path)
	end
	r.SetMediaItemInfo_Value(item, "D_POSITION", file.startPosition)
	r.SetMediaItemInfo_Value(item, "D_LENGTH", length)
	r.SetMediaItemInfo_Value(item, "I_FIXEDLANE", laneIndex)
	if r.GetMediaItemInfo_Value(item, "I_FIXEDLANE") ~= laneIndex then
		r.DeleteTrackMediaItem(track, item)
		return nil,
			nil,
			"REAPER did not assign "
				.. displayName(file.path)
				.. " to version lane "
				.. tostring(file.versionIndex)
				.. "."
	end
	return item, length
end

---Adds comp areas from all available items of each cue's latest discovered version.
---@param project ReaProject
---@param files table[]
---@param latestByCue table
---@return boolean success, number|nil compCount, string|nil error
local function applyLatestCueCompAreas(project, files, latestByCue)
	local cuesTrack
	for index = 0, r.CountTracks(project) - 1 do
		local track = r.GetTrack(project, index)
		local _, name = r.GetTrackName(track)
		if name == "CUES" and not r.GetParentTrack(track) then
			cuesTrack = track
			break
		end
	end
	if not cuesTrack then
		return false, nil, "Could not find the CUES folder while creating comp areas."
	end

	local _, sourceItems = inspectProjectSources(project)
	local candidatesByCue = {}
	for _, file in ipairs(files) do
		local latest = latestByCue[file.cueId]
		if latest and file.normalizedVersion == latest.normalizedVersion then
			local items = sourceItems[H.normalizePath(file.path)] or {}
			for _, sourceItem in ipairs(items) do
				if r.GetParentTrack(sourceItem.track) == cuesTrack then
					local candidate = candidatesByCue[file.cueId]
					if not candidate then
						candidate = { cueId = file.cueId, items = {}, itemSet = {}, position = sourceItem.startPos }
						candidatesByCue[file.cueId] = candidate
					end
					if not candidate.itemSet[sourceItem.item] then
						candidate.itemSet[sourceItem.item] = true
						table.insert(candidate.items, sourceItem.item)
						candidate.position = math.min(candidate.position, sourceItem.startPos)
					end
				end
			end
		end
	end
	local candidates = {}
	for _, candidate in pairs(candidatesByCue) do
		table.insert(candidates, candidate)
	end
	table.sort(candidates, function(a, b)
		if a.position == b.position then
			return a.cueId < b.cueId
		end
		return a.position < b.position
	end)
	local ok, err = xpcall(function()
		for _, candidate in ipairs(candidates) do
			for index = 0, r.CountMediaItems(project) - 1 do
				r.SetMediaItemSelected(r.GetMediaItem(project, index), false)
			end
			for _, item in ipairs(candidate.items) do
				r.SetMediaItemSelected(item, true)
			end
			r.Main_OnCommandEx(ADD_COMP_AREAS_COMMAND_ID, 0, project)
		end
	end, debug.traceback)
	local turnOffOk, turnOffError = pcall(r.Main_OnCommandEx, TURN_OFF_COMPING_COMMAND_ID, 0, project)
	if not turnOffOk then
		return false, nil, "Could not turn off comping after adding comp areas: " .. tostring(turnOffError)
	end
	if not ok then
		return false, nil, tostring(err)
	end
	return true, #candidates
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
	enumerateFullMixes(root .. "/05_Delivery", report.prefix, files, warnings)
	if #files == 0 then
		local suffix = #warnings > 0 and ("\n\n" .. table.concat(warnings, "\n")) or ""
		r.Undo_BeginBlock2(project)
		local groupCallOk, groupOk, groupError = pcall(ensureCueTrackGroup, project)
		r.Undo_EndBlock2(project, "EXPO: Configure CUES track group", -1)
		r.UpdateArrange()
		if not groupCallOk or not groupOk then
			suffix = suffix
				.. "\n\nCould not configure the CUES track group: "
				.. tostring(groupCallOk and groupError or groupOk)
		end
		r.ShowMessageBox(
			"No matching audio preview, pre-mix stem, or full mix renders were found." .. suffix,
			TITLE,
			MB_OK
		)
		return
	end

	local seenCandidates, uniqueFiles, maxVersionByCue = {}, {}, {}
	local maxVersionIndex = 0
	for _, file in ipairs(files) do
		local duplicateKey = table.concat({ file.cueId, file.normalizedVersion, file.mediaKind, file.stem or "" }, "|")
		duplicateKey = H.normalizePath(duplicateKey)
		if seenCandidates[duplicateKey] then
			table.insert(warnings, "Ambiguous duplicate render; skipped: " .. displayName(file.path))
		else
			seenCandidates[duplicateKey] = true
			table.insert(uniqueFiles, file)
			maxVersionIndex = math.max(maxVersionIndex, file.versionIndex)
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

	local _, sourceItems = inspectProjectSources(project)
	local alreadyPlaced = {}
	local sourceItemsByFile = {}
	local versionSpans = {}
	for _, file in ipairs(uniqueFiles) do
		local sourceKey = H.normalizePath(file.path)
		local existingItems = sourceItems[sourceKey]
		sourceItemsByFile[sourceKey] = existingItems
		if existingItems then
			table.insert(alreadyPlaced, displayName(file.path))
		end
	end
	local trackPaths = getTrackPathMap(project)
	local neededStems = {}
	for _, file in ipairs(uniqueFiles) do
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
	local originalSelectedItems = {}
	for i = 0, r.CountMediaItems(project) - 1 do
		local item = r.GetMediaItem(project, i)
		local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
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
		local orderReady, orderError = ensureCueTrackOrder(project)
		if not orderReady then
			error(orderError)
		end
		local groupReady, groupError = ensureCueTrackGroup(project)
		if not groupReady then
			error(groupError)
		end
		local lanesReady, laneError = ensureSharedCueLaneCount(project, maxVersionIndex)
		if not lanesReady then
			error(laneError)
		end

		for _, file in ipairs(uniqueFiles) do
			local targetPath = H.normalizePath(
				file.mediaKind == "preview" and "CUES/Preview"
					or file.mediaKind == "fullmix" and "CUES/Full Mix"
					or "CUES/" .. file.stem
			)
			local target = trackPaths[targetPath]
			if not target then
				local reason = target == false and ("Multiple tracks have the name path " .. targetPath .. ".")
					or ("No target track at " .. targetPath .. ".")
				table.insert(failures, reason .. " Could not place " .. displayName(file.path))
			else
				local laneIndex, laneError = ensureVersionLane(target, file.versionIndex)
				if laneIndex == nil then
					table.insert(
						failures,
						laneError or ("Could not resolve version lane for " .. displayName(file.path))
					)
				else
					local existingItems = sourceItemsByFile[H.normalizePath(file.path)]
					local length
					if existingItems and #existingItems > 0 then
						for _, existing in ipairs(existingItems) do
							local repaired, itemLength, repairError =
								configureRenderItem(existing.item, target, file, laneIndex)
							if not repaired then
								table.insert(failures, repairError)
							else
								length = itemLength
							end
						end
					else
						local inserted, itemLength, importError = createRenderItem(target, file, laneIndex)
						if not inserted then
							table.insert(
								failures,
								importError or ("REAPER could not import " .. displayName(file.path))
							)
						else
							importCount = importCount + 1
							length = itemLength
						end
					end
					if length and length > 0 then
						addSpan(
							versionSpans,
							file.cueId,
							file.normalizedVersion,
							file.startPosition,
							file.startPosition + length
						)
					end
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
	local compCount = 0
	if ok then
		local compCallOk, compOk, compResult = pcall(applyLatestCueCompAreas, project, uniqueFiles, maxVersionByCue)
		if not compCallOk then
			table.insert(failures, "Could not create latest-version comp areas: " .. tostring(compOk))
		elseif not compOk then
			table.insert(failures, compResult or "Could not create latest-version comp areas.")
		else
			compCount = compResult or 0
		end
	end
	r.PreventUIRefresh(-1)
	while r.CountSelectedTracks(project) > 0 do
		r.SetTrackSelected(r.GetSelectedTrack(project, 0), false)
	end
	for index = 0, r.CountTracks(project) - 1 do
		r.SetTrackSelected(r.GetTrack(project, index), true)
	end
	local lanesOpenOk, lanesOpenError = pcall(r.Main_OnCommandEx, OPEN_FIXED_ITEM_LANES_COMMAND_ID, 0, project)
	if not lanesOpenOk then
		table.insert(failures, "Could not open fixed item lanes before closing them: " .. tostring(lanesOpenError))
	end
	local lanesCloseOk, lanesCloseError = pcall(r.Main_OnCommandEx, TOGGLE_FIXED_ITEM_LANES_COMMAND_ID, 0, project)
	if not lanesCloseOk then
		table.insert(failures, "Could not toggle fixed item lanes closed: " .. tostring(lanesCloseError))
	end
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
	local result = "Imported "
		.. tostring(importCount)
		.. " new render file(s) and reconciled "
		.. tostring(#alreadyPlaced)
		.. " already-present file(s).\n\n"
		.. "Created latest-version comp areas for "
		.. tostring(compCount)
		.. " cue(s). Comping mode was turned off after setup."
	if #alreadyPlaced > 0 then
		table.sort(alreadyPlaced)
		result = result .. "\n\nAlready placed: \n" .. table.concat(alreadyPlaced, "\n")
	end
	if #failures > 0 then
		result = result .. "\n\nIssues:\n- " .. table.concat(failures, "\n- ")
	end
	if #warnings > 0 then
		result = result .. "\n\nSkipped or malformed files:\n- " .. table.concat(warnings, "\n- ")
	end
	r.ShowMessageBox(result, TITLE, MB_OK)
end

main()

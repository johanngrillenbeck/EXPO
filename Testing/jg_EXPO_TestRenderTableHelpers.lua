-- @description EXPO TEST RenderTable diagnostics helpers
-- @author Johann Grillenbeck
-- @about
--   Shared setup and console formatting for EXPO render-table diagnostic scripts.
-- @noindex

local T = {}
local r = reaper

local function loadGlobal(fileName)
	local source = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
	local scriptDir = source:match("^(.*)[/\\]") or ""
	local repoRoot = scriptDir:match("^(.*)[/\\][^/\\]+$") or scriptDir
	local path = repoRoot .. "/EXPO/Global/" .. fileName
	local ok, module = pcall(dofile, path)
	if ok and type(module) == "table" then
		return module
	end
	return nil, "Failed to load " .. path .. "\n" .. tostring(module)
end

function T.loadModules()
	local H, helperError = loadGlobal("jg_EXPO_Helper.lua")
	if not H then
		return nil, nil, helperError
	end
	local Render, renderError = loadGlobal("jg_EXPO_Render.lua")
	if not Render then
		return nil, nil, renderError
	end
	return H, Render
end

---Builds the intended pre-mix render table for the current Cue project and its first matched EXPO region.
---@param api table Ultraschall API
---@param H table EXPO Helper
---@param Render table EXPO Render helper
---@return table|nil renderTable, table|nil info, string|nil error
function T.buildDesiredRenderTable(api, H, Render)
	local project, projectPath = r.EnumProjects(-1)
	if not project or not projectPath or projectPath == "" then
		return nil, nil, "Save the current Cue project before building the desired render table."
	end

	local parsed, parseError = H.cueOrMulticue()
	if not parsed then
		return nil, nil, "Could not parse the current Cue project filename: " .. tostring(parseError)
	end
	local expoRoot = H.getExpoRoot(projectPath)
	if not expoRoot then
		return nil, nil, "Could not determine the EXPO root from the current project path."
	end

	local regions = H.getRegionsOnRulerLane("EXPO", project)
	if #regions == 0 then
		return nil, nil, "No regions were found on the EXPO ruler lane."
	end
	local matching = H.matchCueRegions(parsed.cues, regions)
	local region = matching.matched[1] or matching.versionMismatches[1]
	if not region or not region.cue then
		return nil, nil, "Could not associate a region on the EXPO ruler lane with a cue in the project filename."
	end

	local frameRate = r.TimeMap_curFrameRate(project)
	local startPos, endPos = H.alignRegionToFrames(region.startPos, region.endPos, frameRate)
	if endPos <= startPos then
		return nil, nil, "The matched EXPO region has invalid frame-aligned bounds."
	end
	local master = r.GetMasterTrack(project)
	local channels = math.floor(r.GetMediaTrackInfo_Value(master, "I_NCHAN") or 0)
	if channels < 1 then
		return nil, nil, "Could not determine the Master Channel count."
	end
	if type(api.CreateRenderCFG_WAV) ~= "function" then
		return nil, nil, "Ultraschall API does not provide CreateRenderCFG_WAV."
	end

	local cfg = {
		bitDepth = 2,
		largeFiles = 0,
		bwfChunk = 0,
		includeMarkers = 0,
		embedProjectTempo = false,
	}
	local cfgOk, renderString = pcall(
		api.CreateRenderCFG_WAV,
		cfg.bitDepth,
		cfg.largeFiles,
		cfg.bwfChunk,
		cfg.includeMarkers,
		cfg.embedProjectTempo
	)
	if not cfgOk or type(renderString) ~= "string" or renderString == "" then
		return nil, nil, "Could not create the intended 24-bit PCM WAV render string: " .. tostring(renderString)
	end

	local overrides = {
		AddToProj = false,
		Brickwall_Limiter_Target = 1.0, -- match GetRenderTable_Project's floating-point representation of the default 1 dB target
		Source = 3,
		Bounds = 0,
		ParallelRender = true, -- REAPER enables this option for selected-track stem rendering
		Startposition = startPos,
		Endposition = endPos,
		TailFlag = 18,
		TailMS = 0,
		RenderFile = expoRoot .. "/03_Cues/03-01_Exports/",
		RenderPattern = parsed.prefix
			.. "_"
			.. region.cue.cueId
			.. "_"
			.. region.cue.version
			.. "_$track_pre-mix_TC-$starttc",
		SampleRate = 48000,
		Channels = channels,
		OfflineOnlineRendering = 0,
		ProjectSampleRateFXProcessing = true,
		RenderResample = 10,
		OnlyMonoMedia = false,
		MultiChannelFiles = false,
		Dither = 0,
		RenderString = renderString,
		SilentlyIncrementFilename = false,
		CloseAfterRender = true,
		NoSilentRender = true,
		SaveRenderStatsFile = 2,
	}
	local renderTable, tableError = Render.createRenderTable(api, overrides)
	if not renderTable then
		return nil, nil, "Could not create a valid desired render table: " .. tostring(tableError)
	end

	return renderTable,
		{
			project = project,
			projectPath = projectPath,
			region = region,
			channels = channels,
			cue = region.cue,
		},
		nil
end

local function sortedKeys(tbl)
	local keys = {}
	for key in pairs(tbl) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function formatValue(value, depth)
	depth = depth or 0
	if type(value) ~= "table" then
		if type(value) == "string" then
			return string.format("%q", value)
		end
		return tostring(value)
	end
	if depth >= 3 then
		return "{...}"
	end
	local parts = {}
	for _, key in ipairs(sortedKeys(value)) do
		table.insert(parts, tostring(key) .. " = " .. formatValue(value[key], depth + 1))
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

---Formats a table recursively with stable key ordering for REAPER's ReaScript console.
---@param label string
---@param tbl table
---@return string
function T.formatTable(label, tbl)
	local lines = { "=== " .. label .. " ===" }
	for _, key in ipairs(sortedKeys(tbl)) do
		table.insert(lines, tostring(key) .. " = " .. formatValue(tbl[key], 0))
	end
	return table.concat(lines, "\n")
end

function T.printConsole(text)
	r.ShowConsoleMsg(text .. "\n\n")
end

return T

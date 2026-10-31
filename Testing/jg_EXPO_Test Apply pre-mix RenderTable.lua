-- @description EXPO TEST Apply pre-mix RenderTable to project settings
-- @author Johann Grillenbeck
-- @about
--   # EXPO TEST: Apply pre-mix RenderTable
--   Applies the pre-mix render settings to the current project's render settings for inspection.
--   This script does not render files and is intended for diagnosis only.
-- @noindex

local r = reaper
local TITLE = "EXPO TEST - Apply pre-mix RenderTable"
local MB_OK = 0
local MB_OKCANCEL = 1
local MB_RESULT_OK = 1

-- Keep this diagnostic table aligned with the pre-mix action's intended settings.
-- The wildcard pattern is passed to REAPER through the RenderTable for inspection in its render dialog.
local TEST_RENDER_STRING = {
	bitDepth = 2, -- WAV bit depth: 2 = 24-bit PCM
	largeFiles = 0, -- 0 = Auto WAV/Wave64
	bwfChunk = 0, -- 0 = no BWF chunk/project filename
	includeMarkers = 0, -- 0 = do not include markers/regions
	embedProjectTempo = false,
}

local TEST_RENDER_TABLE = {
	AddToProj = false,
	Brickwall_Limiter_Target = 1.0, -- same default target, represented as a float like GetRenderTable_Project returns
	Source = 3, -- 3 = stems from selected tracks
	ParallelRender = true, -- REAPER enables this option for selected-track stem rendering
	Bounds = 0, -- custom time range, taken from the first EXPO region below
	Startposition = 0,
	Endposition = 0,
	RenderFile = "", -- set dynamically to the project's 03-01_Exports folder
	RenderPattern = "", -- set dynamically; includes REAPER $track and $starttc wildcards
	CloseAfterRender = true,
	SampleRate = 48000,
	OfflineOnlineRendering = 0, -- full-speed offline
	RenderResample = 10, -- r8brain free
	RenderString = "", -- set dynamically from CreateRenderCFG_WAV
	SilentlyIncrementFilename = false,
	NoSilentRender = true,
	SaveRenderStatsFile = 2, -- per rendered file
}

local function stop(message)
	r.ShowMessageBox(message, TITLE, MB_OK)
end

local function loadGlobal(fileName)
	local source = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
	local scriptDir = source:match("^(.*)[/\\]") or ""
	local repoRoot = scriptDir:match("^(.*)[/\\][^/\\]+$") or scriptDir
	local path = repoRoot .. "/EXPO/Global/" .. fileName
	local ok, module = pcall(dofile, path)
	if ok and type(module) == "table" then
		return module
	end
	stop("Failed to load " .. path .. "\n\n" .. tostring(module))
	return nil
end

local H = loadGlobal("jg_EXPO_Helper.lua")
local Render = loadGlobal("jg_EXPO_Render.lua")
if not (H and Render) then
	return
end

local function main()
	local project, projectPath = r.EnumProjects(-1)
	if not project or not projectPath or projectPath == "" then
		stop("Save the current Cue project before applying the diagnostic render settings.")
		return
	end

	local parsed, parseError = H.cueOrMulticue()
	if not parsed then
		stop("Could not parse the current Cue project's filename.\n\n" .. tostring(parseError))
		return
	end
	local expoRoot = H.getExpoRoot(projectPath)
	if not expoRoot then
		stop("Could not determine the EXPO project root from:\n\n" .. projectPath)
		return
	end

	local api, apiError = Render.loadUltraschall()
	if not api then
		stop("Ultraschall API could not be loaded.\n\n" .. tostring(apiError))
		return
	end
	if type(api.ApplyRenderTable_Project) ~= "function" then
		stop("This Ultraschall API does not provide ApplyRenderTable_Project (requires Ultraschall 5.3).")
		return
	end
	if type(api.CreateRenderCFG_WAV) ~= "function" then
		stop("Ultraschall API does not provide CreateRenderCFG_WAV.")
		return
	end

	local cfg = TEST_RENDER_STRING
	local cfgOk, renderString = pcall(
		api.CreateRenderCFG_WAV,
		cfg.bitDepth,
		cfg.largeFiles,
		cfg.bwfChunk,
		cfg.includeMarkers,
		cfg.embedProjectTempo
	)
	if not cfgOk or type(renderString) ~= "string" or renderString == "" then
		stop("Could not create the configured WAV render string.\n\n" .. tostring(renderString))
		return
	end

	local regions = H.getRegionsOnRulerLane("EXPO", project)
	if #regions == 0 then
		stop("No regions were found on the EXPO ruler lane. Create a cue region before running this diagnostic.")
		return
	end
	local matching = H.matchCueRegions(parsed.cues, regions)
	local region = matching.matched[1] or matching.versionMismatches[1]
	if not region or not region.cue then
		stop("Could not associate an EXPO region with a cue in the current project filename.")
		return
	end
	local frameRate = r.TimeMap_curFrameRate(project)
	local startPos, endPos = H.alignRegionToFrames(region.startPos, region.endPos, frameRate)
	if endPos <= startPos then
		stop("The first EXPO region has invalid bounds.")
		return
	end

	local master = r.GetMasterTrack(project)
	local channels = math.floor(r.GetMediaTrackInfo_Value(master, "I_NCHAN") or 0)
	if channels < 1 then
		stop("Could not determine the Master Channel count.")
		return
	end
	local pattern = parsed.prefix
		.. "_"
		.. region.cue.cueId
		.. "_"
		.. region.cue.version
		.. "_$track_pre-mix_TC-$starttc"

	local renderTableOverrides = {}
	for key, value in pairs(TEST_RENDER_TABLE) do
		renderTableOverrides[key] = value
	end
	renderTableOverrides.Startposition = startPos
	renderTableOverrides.Endposition = endPos
	renderTableOverrides.RenderFile = expoRoot .. "/03_Cues/03-01_Exports/"
	renderTableOverrides.RenderPattern = pattern
	renderTableOverrides.Channels = channels
	renderTableOverrides.RenderString = renderString

	local renderTable, tableError = Render.createRenderTable(api, renderTableOverrides)
	if not renderTable then
		stop("Could not create a valid diagnostic render table.\n\n" .. tostring(tableError))
		return
	end

	local selectedNames = {}
	for index = 0, r.CountSelectedTracks(project) - 1 do
		local track = r.GetSelectedTrack(project, index)
		local _, name = r.GetTrackName(track)
		table.insert(selectedNames, name)
	end
	local selectedSummary = #selectedNames > 0 and table.concat(selectedNames, "\n- ") or "<none>"

	local summary = table.concat({
		"This applies render settings to the current project's render configuration only; it does not start a render.",
		"\nProject: " .. projectPath,
		"\nSelected normal tracks (Source=3 renders these):\n- " .. selectedSummary,
		"\nPlanned pattern: " .. pattern,
		"\nCue region: " .. region.cue.cueId .. "_" .. region.cue.version,
		"\nAligned bounds: " .. string.format("%.6f to %.6f seconds", startPos, endPos),
		"\nChannels: " .. tostring(channels),
		"\n\nThe project will be marked dirty if the settings change. Open REAPER's Render to File dialog afterward to inspect which settings were applied.",
	}, "\n")
	if r.ShowMessageBox(summary, TITLE, MB_OKCANCEL) ~= MB_RESULT_OK then
		return
	end

	-- apply_rendercfg_string=true applies the WAV format string; dirtyness=true
	-- marks the project modified so the settings change is visible to REAPER.
	local callOk, applied, dirty = pcall(api.ApplyRenderTable_Project, renderTable, true, true)
	if not callOk then
		stop("ApplyRenderTable_Project raised an error.\n\n" .. tostring(applied))
		return
	end
	if applied ~= true then
		stop("Ultraschall could not apply the render table to the current project settings.")
		return
	end

	stop(
		"Render table applied to the current project settings.\n\n"
			.. "Project marked dirty: "
			.. tostring(dirty)
			.. "\nSelected tracks at apply time: "
			.. tostring(r.CountSelectedTracks(project))
			.. "\nSource: "
			.. tostring(renderTable.Source)
			.. "\nFilename pattern: "
			.. tostring(renderTable.RenderPattern)
			.. "\n\nOpen Render to File in REAPER to inspect the applied settings. No render was started."
	)
end

main()

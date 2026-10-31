-- @description EXPO Render
-- @author Johann Grillenbeck
-- @about
--   # EXPO Render
--   Shared Ultraschall format builders and REAPER native-render helpers for EXPO actions.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @noindex

local R = {}

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

local function hasRequiredFunctions(api)
	return type(api) == "table"
		and type(api.GetApiVersion) == "function"
		and type(api.CreateNewRenderTable) == "function"
		and type(api.IsValidRenderTable) == "function"
		and type(api.RenderProject_RenderTable) == "function"
end

---Loads Ultraschall and validates the requested functions, defaulting to render-table support.
---@param requiredFunctions string[]|nil
---@return table|nil api, string|nil error
function R.loadUltraschall(requiredFunctions)
	local function supports(api)
		if type(api) ~= "table" then
			return false
		end
		for _, functionName in ipairs(requiredFunctions or {}) do
			if type(api[functionName]) ~= "function" then
				return false
			end
		end
		return requiredFunctions ~= nil or hasRequiredFunctions(api)
	end

	local api = rawget(_G, "ultraschall")
	if supports(api) then
		return api
	end

	local resourcePath = reaper.GetResourcePath()
	local apiPath = resourcePath .. "/UserPlugins/ultraschall_api.lua"
	if not reaper.file_exists(apiPath) then
		return nil, "Ultraschall API file was not found at:\n" .. apiPath
	end

	local ok, returnedApi = pcall(dofile, apiPath)
	if not ok then
		return nil, "Could not load Ultraschall API from:\n" .. apiPath .. "\n\n" .. tostring(returnedApi)
	end
	api = rawget(_G, "ultraschall")
	if not supports(api) and supports(returnedApi) then
		api = returnedApi
		rawset(_G, "ultraschall", api)
	end
	if not supports(api) then
		return nil,
			"Ultraschall API loaded, but the required functions are unavailable. Check the installation at:\n"
				.. apiPath
	end
	return api
end

---Snapshots the REAPER native render settings and project dirty state before temporary changes.
---@param project ReaProject
---@return table|nil state, string|nil error
function R.snapshotNativeRenderSettings(project)
	local state = { active = true, project = project, numbers = {}, strings = {} }
	state.dirty = reaper.GetSetProjectInfo(project, "DIRTY", 0, false)
	if type(state.dirty) ~= "number" then
		return nil, "Could not read the project's current dirty state."
	end
	for _, key in ipairs(NATIVE_RENDER_NUMBER_KEYS) do
		local ok, value = pcall(reaper.GetSetProjectInfo, project, key, 0, false)
		if not ok or type(value) ~= "number" then
			return nil, "Could not read the current REAPER render setting " .. key .. "."
		end
		state.numbers[key] = value
	end
	for _, key in ipairs(NATIVE_RENDER_STRING_KEYS) do
		local ok, retval, value = pcall(reaper.GetSetProjectInfo_String, project, key, "", false)
		if not ok or not retval or type(value) ~= "string" then
			return nil, "Could not read the current REAPER render setting " .. key .. "."
		end
		state.strings[key] = value
	end
	return state
end

---Restores a native render settings snapshot; safe to call more than once.
---@param state table|nil
---@param restoreDirty boolean|nil Set false when another state restoration failed.
---@return boolean success, string|nil error
function R.restoreNativeRenderSettings(state, restoreDirty)
	if not state or not state.active then
		return true, nil
	end
	local errors = {}
	for _, key in ipairs(NATIVE_RENDER_STRING_KEYS) do
		local ok, retval = pcall(reaper.GetSetProjectInfo_String, state.project, key, state.strings[key], true)
		if not ok or not retval then
			table.insert(errors, "Could not restore REAPER render setting " .. key .. ".")
		end
	end
	for _, key in ipairs(NATIVE_RENDER_NUMBER_KEYS) do
		local ok, value = pcall(reaper.GetSetProjectInfo, state.project, key, state.numbers[key], true)
		if not ok or type(value) ~= "number" or math.abs(value - state.numbers[key]) > 1e-7 then
			table.insert(errors, "Could not restore REAPER render setting " .. key .. ".")
		end
	end
	if restoreDirty ~= false then
		local dirtyOk, dirtyValue = pcall(reaper.GetSetProjectInfo, state.project, "DIRTY", state.dirty, true)
		if not dirtyOk or type(dirtyValue) ~= "number" or dirtyValue ~= state.dirty then
			table.insert(errors, "Could not restore the project's previous dirty state.")
		end
	end
	if #errors == 0 then
		state.active = false
		return true, nil
	end
	return false, table.concat(errors, "\n")
end

---Sets and verifies one numeric native render setting.
---@param project ReaProject
---@param key string
---@param value number
---@return boolean success, string|nil error
function R.setNativeRenderNumber(project, key, value)
	local ok, returnedValue = pcall(reaper.GetSetProjectInfo, project, key, value, true)
	if not ok or type(returnedValue) ~= "number" then
		return false, "Could not set REAPER render setting " .. key .. "."
	end
	local readOk, actualValue = pcall(reaper.GetSetProjectInfo, project, key, 0, false)
	if not readOk or type(actualValue) ~= "number" or math.abs(actualValue - value) > 1e-7 then
		return false,
			"REAPER did not retain render setting " .. key .. ": expected " .. tostring(value) .. ", got " .. tostring(
				actualValue
			)
	end
	return true
end

---Sets and verifies one string native render setting.
---@param project ReaProject
---@param key string
---@param value string
---@return boolean success, string|nil error
function R.setNativeRenderString(project, key, value)
	local ok, retval = pcall(reaper.GetSetProjectInfo_String, project, key, value, true)
	if not ok or not retval then
		return false, "Could not set REAPER render setting " .. key .. "."
	end
	local readOk, getOk, actualValue = pcall(reaper.GetSetProjectInfo_String, project, key, "", false)
	if not readOk or not getOk or actualValue ~= value then
		return false, "REAPER did not retain render setting " .. key .. "."
	end
	return true
end

---Applies numeric and string render-setting maps using verified setters.
---@param project ReaProject
---@param numbers table<string, number>
---@param strings table<string, string>
---@return boolean success, string|nil error
function R.applyNativeRenderSettings(project, numbers, strings)
	for _, key in ipairs(NATIVE_RENDER_NUMBER_KEYS) do
		if numbers and numbers[key] ~= nil then
			local ok, err = R.setNativeRenderNumber(project, key, numbers[key])
			if not ok then
				return false, err
			end
		end
	end
	for _, key in ipairs(NATIVE_RENDER_STRING_KEYS) do
		if strings and strings[key] ~= nil then
			local ok, err = R.setNativeRenderString(project, key, strings[key])
			if not ok then
				return false, err
			end
		end
	end
	return true
end

---Returns the current filenames in a directory, normalized for path separators and Windows case.
---@param directory string
---@return table<string, boolean> files
function R.snapshotDirectoryFiles(directory)
	local files, index = {}, 0
	local windows = reaper.GetOS():match("Win") ~= nil
	while true do
		local fileName = reaper.EnumerateFiles(directory, index)
		if not fileName then
			break
		end
		local key = fileName:gsub("\\", "/")
		if windows then
			key = key:lower()
		end
		files[key] = true
		index = index + 1
	end
	return files
end

---Finds files with the requested extension that were added since a directory snapshot.
---@param directory string
---@param before table<string, boolean>
---@param extension string Extension without a leading dot.
---@return string[] paths
function R.collectNewFiles(directory, before, extension)
	local files, index = {}, 0
	local windows = reaper.GetOS():match("Win") ~= nil
	local suffix = "." .. extension:gsub("^%.", "")
	while true do
		local fileName = reaper.EnumerateFiles(directory, index)
		if not fileName then
			break
		end
		local key = fileName:gsub("\\", "/")
		local compareName = windows and key:lower() or key
		if compareName:sub(-#suffix) == (windows and suffix:lower() or suffix) and not before[compareName] then
			table.insert(files, directory:gsub("[/\\]+$", "") .. "/" .. fileName)
		end
		index = index + 1
	end
	return files
end

---Creates a fresh Ultraschall render table, applies caller-supplied overrides and validates it.
---@param ultraschall table
---@param overrides table RenderTable keys and values chosen by the calling action.
---@return table|nil renderTable, string|nil error
function R.createRenderTable(ultraschall, overrides)
	if type(ultraschall) ~= "table" or type(ultraschall.CreateNewRenderTable) ~= "function" then
		return nil, "Ultraschall API render-table functions are unavailable."
	end
	if type(overrides) ~= "table" then
		return nil, "Render-table overrides must be provided as a table."
	end

	local ok, renderTable = pcall(ultraschall.CreateNewRenderTable)
	if not ok or type(renderTable) ~= "table" then
		return nil, "Could not create an Ultraschall render table."
	end
	for key, value in pairs(overrides) do
		renderTable[key] = value
	end

	if type(ultraschall.IsValidRenderTable) == "function" then
		local validOk, isValid = pcall(ultraschall.IsValidRenderTable, renderTable)
		if not validOk or not isValid then
			return nil, "Ultraschall rejected the configured render table. Check the table keys and values."
		end
	end
	return renderTable
end

---Executes a caller-configured render table and normalizes Ultraschall's return values.
---@param ultraschall table
---@param renderTable table
---@return table result {ok, count, files, detail}
function R.renderProjectWithTable(ultraschall, renderTable)
	if type(ultraschall) ~= "table" or type(ultraschall.RenderProject_RenderTable) ~= "function" then
		return { ok = false, count = -1, files = {}, detail = "Ultraschall RenderProject_RenderTable is unavailable." }
	end
	if type(renderTable) ~= "table" then
		return { ok = false, count = -1, files = {}, detail = "A valid render table is required." }
	end

	-- Keep the table as the single source of render configuration. Omitting the
	-- duplicate positional flags lets Ultraschall use the values in RenderTable.
	local ok, count, itemStateChunks, files = pcall(ultraschall.RenderProject_RenderTable, nil, renderTable)
	if not ok then
		return { ok = false, count = -1, files = {}, detail = tostring(count) }
	end
	if type(count) ~= "number" or count < 0 then
		return { ok = false, count = count or -1, files = files or {}, detail = "Ultraschall reported a render error." }
	end
	return {
		ok = count > 0,
		count = count,
		itemStateChunks = itemStateChunks or {},
		files = files or {},
		detail = count > 0 and nil or "Ultraschall completed without rendering an output file.",
	}
end

return R

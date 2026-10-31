-- @description EXPO Render
-- @author Johann Grillenbeck
-- @about
--   # EXPO Render
--   Shared Ultraschall render-table builders and rendering helpers for EXPO actions.
-- @links
--   GitHub https://github.com/johanngrillenbeck/EXPO
-- @noindex

local R = {}

local function hasRequiredFunctions(api)
	return type(api) == "table"
		and type(api.GetApiVersion) == "function"
		and type(api.CreateNewRenderTable) == "function"
		and type(api.IsValidRenderTable) == "function"
		and type(api.RenderProject_RenderTable) == "function"
end

---Loads Ultraschall's installed API and validates the generic render-table functions used here.
---@return table|nil api, string|nil error
function R.loadUltraschall()
	local api = rawget(_G, "ultraschall")
	if hasRequiredFunctions(api) then
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
	if not hasRequiredFunctions(api) and hasRequiredFunctions(returnedApi) then
		api = returnedApi
		rawset(_G, "ultraschall", api)
	end
	if not hasRequiredFunctions(api) then
		return nil,
			"Ultraschall API loaded, but its version or generic render-table functions are unavailable. Check the installation at:\n"
				.. apiPath
	end
	return api
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

---Executes any caller-configured render table and normalizes Ultraschall's return values.
---@param ultraschall table
---@param renderTable table
---@param options table|nil addToProject, closeAfterRender, silentlyIncrementFilename
---@return table result {ok, count, files, detail}
function R.renderProjectWithTable(ultraschall, renderTable, options)
	if type(ultraschall) ~= "table" or type(ultraschall.RenderProject_RenderTable) ~= "function" then
		return { ok = false, count = -1, files = {}, detail = "Ultraschall RenderProject_RenderTable is unavailable." }
	end
	options = options or {}
	local addToProject = options.addToProject == true
	local closeAfterRender = options.closeAfterRender ~= false
	local silentlyIncrementFilename = options.silentlyIncrementFilename == true

	local ok, count, itemStateChunks, files = pcall(
		ultraschall.RenderProject_RenderTable,
		nil,
		renderTable,
		addToProject,
		closeAfterRender,
		silentlyIncrementFilename
	)
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

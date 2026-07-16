local M = {}

local DEFAULTS = {
  enabled = true,
  diagnostics = "warn",
}

local DIAGNOSTICS = {
  silent = true,
  warn = true,
  error = true,
}

---@param options? table
---@return table
function M.resolve(options)
  if options == nil then options = {} end
  assert(type(options) == "table", "raccoon-inline-diff options must be a table")
  for key in pairs(options) do
    assert(DEFAULTS[key] ~= nil, "unknown raccoon-inline-diff option: " .. tostring(key))
  end

  local enabled = options.enabled
  if enabled == nil then enabled = DEFAULTS.enabled end
  assert(type(enabled) == "boolean", "raccoon-inline-diff enabled must be a boolean")

  local diagnostics = options.diagnostics or DEFAULTS.diagnostics
  assert(DIAGNOSTICS[diagnostics], "raccoon-inline-diff diagnostics must be silent, warn, or error")
  return { enabled = enabled, diagnostics = diagnostics }
end

return M

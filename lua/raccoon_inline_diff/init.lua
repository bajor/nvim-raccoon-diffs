local config = require("raccoon_inline_diff.config")
local lifecycle = require("raccoon_inline_diff.lifecycle")

local M = {}

---@param options? table
function M.setup(options)
  local resolved = config.resolve(options)
  if resolved.enabled then
    lifecycle.start(resolved)
  else
    lifecycle.stop()
  end
end

function M.disable()
  lifecycle.stop()
end

function M.refresh()
  lifecycle.scan()
end

return M

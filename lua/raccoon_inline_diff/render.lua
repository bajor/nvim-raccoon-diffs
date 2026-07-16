local utf16 = require("raccoon_inline_diff.utf16")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("raccoon_inline_diff")
local PRIORITY = 200

local function highlight_exists(name)
  return vim.fn.hlexists(name) == 1
end

local function default_link(name, host_name, fallback)
  if highlight_exists(name) then return end
  local target = highlight_exists(host_name) and host_name or fallback
  vim.api.nvim_set_hl(0, name, { default = true, link = target })
end

function M.setup_highlights()
  default_link("RaccoonInlineDiffAddText", "RaccoonAddText", "DiffAdd")
  default_link("RaccoonInlineDiffDeleteText", "RaccoonDeleteText", "DiffDelete")
end

---@return number
function M.namespace()
  return NAMESPACE
end

---@param buffer number
function M.clear(buffer)
  if vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_buf_clear_namespace(buffer, NAMESPACE, 0, -1)
  end
end

local function byte_boundaries(line)
  local ok, decoded = pcall(utf16.decode, line)
  if not ok then return nil end
  local boundaries = { [0] = true }
  for _, item in ipairs(decoded) do boundaries[item.byte_end] = true end
  return boundaries
end

local function validate_marks(buffer, marks)
  local line_count = vim.api.nvim_buf_line_count(buffer)
  local lines = {}
  for _, mark in ipairs(marks) do
    if type(mark.row) ~= "number" or mark.row < 0 or mark.row >= line_count or mark.row % 1 ~= 0 then
      return false, "mark row is outside the buffer"
    end
    if mark.side ~= "addition" and mark.side ~= "deletion" then
      return false, "mark side must be addition or deletion"
    end
    local line = lines[mark.row]
    if line == nil then
      line = vim.api.nvim_buf_get_lines(buffer, mark.row, mark.row + 1, false)[1] or ""
      lines[mark.row] = line
    end
    local boundaries = byte_boundaries(line)
    if not boundaries
      or not boundaries[mark.start_byte]
      or not boundaries[mark.end_byte]
      or mark.end_byte < mark.start_byte
    then
      return false, "mark columns are not valid UTF-8 boundaries"
    end
  end
  return true
end

---Replace extension-owned marks without touching any other namespace.
---@param buffer number
---@param marks table[]
---@return boolean
---@return string?
function M.apply(buffer, marks)
  if not vim.api.nvim_buf_is_valid(buffer) then return false, "buffer is invalid" end
  M.clear(buffer)
  local valid, err = validate_marks(buffer, marks)
  if not valid then return false, err end

  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buffer, NAMESPACE, mark.row, mark.start_byte, {
      end_row = mark.row,
      end_col = mark.end_byte,
      hl_group = mark.side == "addition" and "RaccoonInlineDiffAddText" or "RaccoonInlineDiffDeleteText",
      hl_mode = "combine",
      priority = PRIORITY,
    })
  end
  return true
end

return M

-- UTF-8 validation and JavaScript UTF-16 coordinate conversion.
local M = {}

local function invalid(byte_index)
  error(string.format("invalid UTF-8 at byte %d", byte_index - 1), 3)
end

local function continuation(value)
  return value ~= nil and value >= 0x80 and value <= 0xBF
end

---Decode a UTF-8 string into Unicode scalar values and coordinate boundaries.
---@param value string
---@return table[]
---@return number
function M.decode(value)
  assert(type(value) == "string", "UTF-8 input must be a string")
  local decoded = {}
  local byte_index = 1
  local utf16_index = 0

  while byte_index <= #value do
    local first = value:byte(byte_index)
    local codepoint
    local byte_length

    if first <= 0x7F then
      codepoint = first
      byte_length = 1
    elseif first >= 0xC2 and first <= 0xDF then
      local second = value:byte(byte_index + 1)
      if not continuation(second) then invalid(byte_index) end
      codepoint = (first - 0xC0) * 0x40 + (second - 0x80)
      byte_length = 2
    elseif first >= 0xE0 and first <= 0xEF then
      local second = value:byte(byte_index + 1)
      local third = value:byte(byte_index + 2)
      if not continuation(second) or not continuation(third) then invalid(byte_index) end
      if first == 0xE0 and second < 0xA0 then invalid(byte_index) end
      if first == 0xED and second > 0x9F then invalid(byte_index) end
      codepoint = (first - 0xE0) * 0x1000 + (second - 0x80) * 0x40 + (third - 0x80)
      byte_length = 3
    elseif first >= 0xF0 and first <= 0xF4 then
      local second = value:byte(byte_index + 1)
      local third = value:byte(byte_index + 2)
      local fourth = value:byte(byte_index + 3)
      if not continuation(second) or not continuation(third) or not continuation(fourth) then
        invalid(byte_index)
      end
      if first == 0xF0 and second < 0x90 then invalid(byte_index) end
      if first == 0xF4 and second > 0x8F then invalid(byte_index) end
      codepoint = (first - 0xF0) * 0x40000
        + (second - 0x80) * 0x1000
        + (third - 0x80) * 0x40
        + (fourth - 0x80)
      byte_length = 4
    else
      invalid(byte_index)
    end

    local utf16_length = codepoint > 0xFFFF and 2 or 1
    decoded[#decoded + 1] = {
      codepoint = codepoint,
      byte_start = byte_index - 1,
      byte_end = byte_index - 1 + byte_length,
      utf16_start = utf16_index,
      utf16_end = utf16_index + utf16_length,
    }
    byte_index = byte_index + byte_length
    utf16_index = utf16_index + utf16_length
  end

  return decoded, utf16_index
end

---@param value string
---@return number
function M.length(value)
  local _, length = M.decode(value)
  return length
end

---Convert a zero-based UTF-16 boundary to a zero-based UTF-8 byte column.
---@param value string
---@param utf16_column number
---@return number
function M.byte_column(value, utf16_column)
  assert(type(utf16_column) == "number" and utf16_column >= 0 and utf16_column % 1 == 0,
    "UTF-16 column must be a non-negative integer")
  local decoded, length = M.decode(value)
  if utf16_column == length then return #value end
  for _, item in ipairs(decoded) do
    if item.utf16_start == utf16_column then
      return item.byte_start
    end
  end
  error(string.format("UTF-16 column %d is not a code point boundary", utf16_column), 2)
end

---@param value string
---@param start_utf16 number
---@param end_utf16 number
---@return number
---@return number
function M.byte_range(value, start_utf16, end_utf16)
  assert(end_utf16 >= start_utf16, "UTF-16 range end must not precede its start")
  return M.byte_column(value, start_utf16), M.byte_column(value, end_utf16)
end

return M

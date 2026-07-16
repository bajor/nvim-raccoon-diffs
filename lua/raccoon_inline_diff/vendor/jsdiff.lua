-- SPDX-License-Identifier: BSD-3-Clause
--
-- Mechanically adapted from diff@9.0.0:
--   src/diff/base.ts
--   src/diff/word.ts (WordsWithSpaceDiff only)
-- See vendor/README.md and licenses/jsdiff.txt.
local utf16 = require("raccoon_inline_diff.utf16")

local M = {}

local function is_extended_word(codepoint)
  return (codepoint >= 0x61 and codepoint <= 0x7A)
    or (codepoint >= 0x41 and codepoint <= 0x5A)
    or (codepoint >= 0x30 and codepoint <= 0x39)
    or codepoint == 0x5F
    or codepoint == 0xAD
    or (codepoint >= 0xC0 and codepoint <= 0xD6)
    or (codepoint >= 0xD8 and codepoint <= 0xF6)
    or (codepoint >= 0xF8 and codepoint <= 0x2C6)
    or (codepoint >= 0x2C8 and codepoint <= 0x2D7)
    or (codepoint >= 0x2DE and codepoint <= 0x2FF)
    or (codepoint >= 0x1E00 and codepoint <= 0x1EFF)
end

local function is_javascript_whitespace(codepoint)
  return (codepoint >= 0x09 and codepoint <= 0x0D)
    or codepoint == 0x20
    or codepoint == 0xA0
    or codepoint == 0x1680
    or (codepoint >= 0x2000 and codepoint <= 0x200A)
    or codepoint == 0x2028
    or codepoint == 0x2029
    or codepoint == 0x202F
    or codepoint == 0x205F
    or codepoint == 0x3000
    or codepoint == 0xFEFF
end

local function slice_bytes(value, first, last)
  return value:sub(first + 1, last)
end

---Port of WordsWithSpaceDiff.tokenize.
---@param value string
---@return string[]
function M.tokenize_words_with_space(value)
  local decoded = utf16.decode(value)
  local tokens = {}
  local index = 1

  while index <= #decoded do
    local item = decoded[index]
    local codepoint = item.codepoint

    if codepoint == 0x0D and decoded[index + 1] and decoded[index + 1].codepoint == 0x0A then
      tokens[#tokens + 1] = slice_bytes(value, item.byte_start, decoded[index + 1].byte_end)
      index = index + 2
    elseif codepoint == 0x0A then
      tokens[#tokens + 1] = slice_bytes(value, item.byte_start, item.byte_end)
      index = index + 1
    elseif is_extended_word(codepoint) then
      local finish = index
      while decoded[finish + 1] and is_extended_word(decoded[finish + 1].codepoint) do
        finish = finish + 1
      end
      tokens[#tokens + 1] = slice_bytes(value, item.byte_start, decoded[finish].byte_end)
      index = finish + 1
    elseif is_javascript_whitespace(codepoint) and codepoint ~= 0x0A and codepoint ~= 0x0D then
      local finish = index
      while decoded[finish + 1]
        and is_javascript_whitespace(decoded[finish + 1].codepoint)
        and decoded[finish + 1].codepoint ~= 0x0A
        and decoded[finish + 1].codepoint ~= 0x0D
      do
        finish = finish + 1
      end
      tokens[#tokens + 1] = slice_bytes(value, item.byte_start, decoded[finish].byte_end)
      index = finish + 1
    else
      tokens[#tokens + 1] = slice_bytes(value, item.byte_start, item.byte_end)
      index = index + 1
    end
  end

  return tokens
end

local function add_to_path(path, added, removed, old_position_increment)
  local last = path.last_component
  if last and last.added == added and last.removed == removed then
    return {
      old_position = path.old_position + old_position_increment,
      last_component = {
        count = last.count + 1,
        added = added,
        removed = removed,
        previous_component = last.previous_component,
      },
    }
  end
  return {
    old_position = path.old_position + old_position_increment,
    last_component = {
      count = 1,
      added = added,
      removed = removed,
      previous_component = last,
    },
  }
end

local function extract_common(base_path, new_tokens, old_tokens, diagonal_path)
  local new_length = #new_tokens
  local old_length = #old_tokens
  local old_position = base_path.old_position
  local new_position = old_position - diagonal_path
  local common_count = 0

  while new_position + 1 < new_length
    and old_position + 1 < old_length
    and old_tokens[old_position + 2] == new_tokens[new_position + 2]
  do
    new_position = new_position + 1
    old_position = old_position + 1
    common_count = common_count + 1
  end

  if common_count > 0 then
    base_path.last_component = {
      count = common_count,
      previous_component = base_path.last_component,
      added = false,
      removed = false,
    }
  end
  base_path.old_position = old_position
  return new_position
end

local function join_tokens(tokens, position, count)
  local values = {}
  for offset = 1, count do
    values[offset] = tokens[position + offset]
  end
  return table.concat(values)
end

local function build_values(last_component, new_tokens, old_tokens)
  local reversed = {}
  while last_component do
    reversed[#reversed + 1] = last_component
    last_component = last_component.previous_component
  end

  local components = {}
  local new_position = 0
  local old_position = 0
  for reverse_index = #reversed, 1, -1 do
    local component = reversed[reverse_index]
    local value
    if component.removed then
      value = join_tokens(old_tokens, old_position, component.count)
      old_position = old_position + component.count
    else
      value = join_tokens(new_tokens, new_position, component.count)
      new_position = new_position + component.count
      if not component.added then
        old_position = old_position + component.count
      end
    end
    components[#components + 1] = {
      count = component.count,
      added = component.added,
      removed = component.removed,
      value = value,
    }
  end
  return components
end

---Synchronous Myers traversal used by diffWordsWithSpace in diff@9.0.0.
---@param old_value string
---@param new_value string
---@return table[]
function M.diff_words_with_space(old_value, new_value)
  local old_tokens = M.tokenize_words_with_space(old_value)
  local new_tokens = M.tokenize_words_with_space(new_value)
  local new_length = #new_tokens
  local old_length = #old_tokens
  local edit_length = 1
  local max_edit_length = new_length + old_length
  local best_path = {
    [0] = { old_position = -1, last_component = nil },
  }

  local new_position = extract_common(best_path[0], new_tokens, old_tokens, 0)
  if best_path[0].old_position + 1 >= old_length and new_position + 1 >= new_length then
    return build_values(best_path[0].last_component, new_tokens, old_tokens)
  end

  local min_diagonal = -math.huge
  local max_diagonal = math.huge
  while edit_length <= max_edit_length do
    local diagonal = math.max(min_diagonal, -edit_length)
    local diagonal_end = math.min(max_diagonal, edit_length)
    while diagonal <= diagonal_end do
      local remove_path = best_path[diagonal - 1]
      local add_path = best_path[diagonal + 1]
      if remove_path then best_path[diagonal - 1] = nil end

      local can_add = false
      if add_path then
        local add_path_new_position = add_path.old_position - diagonal
        can_add = add_path_new_position >= 0 and add_path_new_position < new_length
      end
      local can_remove = remove_path ~= nil and remove_path.old_position + 1 < old_length

      if not can_add and not can_remove then
        best_path[diagonal] = nil
      else
        local base_path
        if not can_remove or (can_add and remove_path.old_position < add_path.old_position) then
          base_path = add_to_path(add_path, true, false, 0)
        else
          base_path = add_to_path(remove_path, false, true, 1)
        end

        new_position = extract_common(base_path, new_tokens, old_tokens, diagonal)
        if base_path.old_position + 1 >= old_length and new_position + 1 >= new_length then
          return build_values(base_path.last_component, new_tokens, old_tokens)
        end

        best_path[diagonal] = base_path
        if base_path.old_position + 1 >= old_length then
          max_diagonal = math.min(max_diagonal, diagonal - 1)
        end
        if new_position + 1 >= new_length then
          min_diagonal = math.max(min_diagonal, diagonal + 1)
        end
      end
      diagonal = diagonal + 2
    end
    edit_length = edit_length + 1
  end

  error("jsdiff traversal exhausted without a result")
end

return M

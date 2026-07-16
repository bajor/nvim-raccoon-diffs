-- SPDX-License-Identifier: Apache-2.0
--
-- Pierre word-alt span planning, mechanically adapted from @pierre/diffs
-- 1.2.12. See vendor/README.md and licenses/pierre-diffs.txt.
local jsdiff = require("raccoon_inline_diff.vendor.jsdiff")
local utf16 = require("raccoon_inline_diff.utf16")

local M = {}

M.MAX_LINE_DIFF_UTF16_UNITS = 1000
local ROW_YIELD_INTERVAL = 32
local PATCH_LINE_YIELD_INTERVAL = 256

---Match @pierre/diffs cleanLastNewline exactly.
---@param contents string
---@return string
function M.clean_last_newline(contents)
  if contents:sub(-2) == "\r\n" then
    return contents:sub(1, -3)
  end
  if contents:sub(-1) == "\n" then
    return contents:sub(1, -2)
  end
  return contents
end

local function push_or_join_span(item, spans, is_neutral, is_last_item)
  local last = spans[#spans]
  if last == nil or is_last_item then
    spans[#spans + 1] = { changed = not is_neutral, value = item.value }
    return
  end

  local last_is_neutral = not last.changed
  if is_neutral == last_is_neutral
    or (is_neutral and utf16.length(item.value) == 1 and not last_is_neutral)
  then
    last.value = last.value .. item.value
    return
  end
  spans[#spans + 1] = { changed = not is_neutral, value = item.value }
end

local function ranges_from_spans(contents, spans)
  local ranges = {}
  local position = 0
  for _, span in ipairs(spans) do
    local length = utf16.length(span.value)
    if span.changed then
      local start_byte, end_byte = utf16.byte_range(contents, position, position + length)
      ranges[#ranges + 1] = {
        start_utf16 = position,
        end_utf16 = position + length,
        start_byte = start_byte,
        end_byte = end_byte,
      }
    end
    position = position + length
  end
  assert(position == utf16.length(contents), "jsdiff spans do not reconstruct their source")
  return ranges
end

---Compute exact Pierre word-alt decorations for one paired row.
---@param deletion_input string
---@param addition_input string
---@param yield_control? function Optional scheduling hook; does not alter semantic output.
---@return table
function M.line_diff(deletion_input, addition_input, yield_control)
  local deletion = M.clean_last_newline(deletion_input)
  local addition = M.clean_last_newline(addition_input)
  if utf16.length(deletion) > M.MAX_LINE_DIFF_UTF16_UNITS
    or utf16.length(addition) > M.MAX_LINE_DIFF_UTF16_UNITS
  then
    return {
      deletion = deletion,
      addition = addition,
      suppressed = true,
      changes = {},
      deletion_ranges = {},
      addition_ranges = {},
    }
  end

  local changes = jsdiff.diff_words_with_space(deletion, addition, yield_control)
  local deletion_spans = {}
  local addition_spans = {}
  for index, item in ipairs(changes) do
    local is_last_item = index == #changes
    if not item.added and not item.removed then
      push_or_join_span(item, deletion_spans, true, is_last_item)
      push_or_join_span(item, addition_spans, true, is_last_item)
    elseif item.removed then
      push_or_join_span(item, deletion_spans, false, is_last_item)
    else
      push_or_join_span(item, addition_spans, false, is_last_item)
    end
  end

  return {
    deletion = deletion,
    addition = addition,
    suppressed = false,
    changes = changes,
    deletion_ranges = ranges_from_spans(deletion, deletion_spans),
    addition_ranges = ranges_from_spans(addition, addition_spans),
  }
end

local function copy_record(record)
  local copy = {}
  for key, value in pairs(record) do copy[key] = value end
  return copy
end

---Plan positional rows for typed content from one hunk.
---@param records table[] Entries with kind=addition|deletion|context and content.
---@param yield_control? function Optional scheduling hook; does not alter semantic output.
---@return table[]
function M.plan_typed_lines(records, yield_control)
  local rows = {}
  local deletions = {}
  local additions = {}
  local rows_since_yield = 0

  local function flush_change()
    local count = math.max(#deletions, #additions)
    for index = 1, count do
      local deletion = deletions[index]
      local addition = additions[index]
      rows[#rows + 1] = {
        kind = "change",
        deletion = deletion,
        addition = addition,
        inline = deletion and addition and M.line_diff(deletion.content, addition.content, yield_control) or nil,
      }
      rows_since_yield = rows_since_yield + 1
      if yield_control and rows_since_yield == ROW_YIELD_INTERVAL then
        rows_since_yield = 0
        yield_control()
      end
    end
    deletions = {}
    additions = {}
  end

  for _, source in ipairs(records) do
    local record = copy_record(source)
    if record.kind == "deletion" then
      deletions[#deletions + 1] = record
    elseif record.kind == "addition" then
      additions[#additions + 1] = record
    elseif record.kind == "context" then
      flush_change()
      rows[#rows + 1] = { kind = "context", deletion = record, addition = record }
    else
      error("unknown typed line kind: " .. tostring(record.kind))
    end
  end
  flush_change()
  return rows
end

local function parse_hunk_header(line)
  local deletion_start, deletion_count, addition_start, addition_count =
    line:match("^@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")
  if not deletion_start then
    deletion_start, addition_start = line:match("^@@ %-(%d+) %+(%d+) @@")
    deletion_count, addition_count = "1", "1"
  end
  if not deletion_start then
    deletion_start, deletion_count, addition_start = line:match("^@@ %-(%d+),(%d+) %+(%d+) @@")
    addition_count = addition_start and "1" or nil
  end
  if not deletion_start then
    deletion_start, addition_start, addition_count = line:match("^@@ %-(%d+) %+(%d+),(%d+) @@")
    deletion_count = deletion_start and "1" or nil
  end
  if not deletion_start then return nil end
  return tonumber(deletion_start), tonumber(deletion_count), tonumber(addition_start), tonumber(addition_count)
end

local function split_with_newlines(contents)
  if contents == "" then return {} end
  local lines = {}
  local start = 1
  while start <= #contents do
    local newline = contents:find("\n", start, true)
    if newline then
      lines[#lines + 1] = contents:sub(start, newline)
      start = newline + 1
    else
      lines[#lines + 1] = contents:sub(start)
      break
    end
  end
  return lines
end

---Parse a host-style per-file unified patch and plan every hunk independently.
---@param patch string
---@param yield_control? function Optional scheduling hook; does not alter semantic output.
---@return table
function M.plan_patch(patch, yield_control)
  assert(type(patch) == "string", "patch must be a string")
  local hunks = {}
  local current
  local old_line
  local new_line
  local hunk_position
  local source_row
  local patch_lines_since_yield = 0

  local function finish_hunk()
    if not current then return end
    current.rows = M.plan_typed_lines(current.records, yield_control)
    hunks[#hunks + 1] = current
    current = nil
  end

  for _, raw_line in ipairs(split_with_newlines(patch)) do
    local deletion_start, deletion_count, addition_start, addition_count = parse_hunk_header(raw_line)
    if deletion_start then
      finish_hunk()
      current = {
        header = M.clean_last_newline(raw_line),
        deletion_start = deletion_start,
        deletion_count = deletion_count,
        addition_start = addition_start,
        addition_count = addition_count,
        records = {},
      }
      old_line = deletion_start
      new_line = addition_start
      hunk_position = 0
      source_row = 0
    elseif current then
      local prefix = raw_line:sub(1, 1)
      local content = raw_line:sub(2)
      if prefix == "\\" then
        local previous = current.records[#current.records]
        if previous then previous.no_eof_newline = true end
      elseif prefix == " " then
        hunk_position = hunk_position + 1
        current.records[#current.records + 1] = {
          kind = "context",
          content = M.clean_last_newline(content),
          raw_content = content,
          old_line = old_line,
          new_line = new_line,
          hunk_position = hunk_position,
          source_row = source_row,
        }
        old_line = old_line + 1
        new_line = new_line + 1
        source_row = source_row + 1
      elseif prefix == "-" then
        hunk_position = hunk_position + 1
        current.records[#current.records + 1] = {
          kind = "deletion",
          content = M.clean_last_newline(content),
          raw_content = content,
          old_line = old_line,
          anchor_line = new_line - 1,
          hunk_position = hunk_position,
          source_row = source_row,
        }
        old_line = old_line + 1
        source_row = source_row + 1
      elseif prefix == "+" then
        hunk_position = hunk_position + 1
        current.records[#current.records + 1] = {
          kind = "addition",
          content = M.clean_last_newline(content),
          raw_content = content,
          new_line = new_line,
          hunk_position = hunk_position,
          source_row = source_row,
        }
        new_line = new_line + 1
        source_row = source_row + 1
      end
    end
    patch_lines_since_yield = patch_lines_since_yield + 1
    if yield_control and patch_lines_since_yield == PATCH_LINE_YIELD_INTERVAL then
      patch_lines_since_yield = 0
      yield_control()
    end
  end
  finish_hunk()

  local rows = {}
  for hunk_index, hunk in ipairs(hunks) do
    for _, row in ipairs(hunk.rows) do
      row.hunk_index = hunk_index
      rows[#rows + 1] = row
    end
  end
  return { hunks = hunks, rows = rows }
end

return M
